import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'core/api_service.dart';
import 'core/app_config.dart';
import 'core/app_gate.dart';
import 'core/app_i18n.dart';
import 'core/app_theme.dart';
import 'core/auth_token_manager.dart';
import 'core/cm_components.dart';
import 'core/network_quality_service.dart';
import 'core/push_notification_service.dart';
import 'firebase_options.dart';
import 'core/realtime_events_service.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/session_store.dart';
import 'features/buyer/buyer_store.dart';
import 'features/shell/client_shell.dart';
import 'features/home/public_home_page.dart';
import 'features/splash/cm_splash_screen.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Surveillance connectivité (bannière hors-ligne + garde-fou écritures).
  NetworkQualityService.instance.init();

  final sessionStore = SessionStore();
  AuthTokenManager.instance.configure(
    getAccessToken: () => sessionStore.token,
    getRefreshToken: () => sessionStore.refreshToken,
    onTokensRefreshed: (accessToken, refreshToken) {
      sessionStore.updateTokens(
        accessToken: accessToken,
        refreshTokenValue: refreshToken,
      );
    },
    onAuthFailed: () => sessionStore.logout(
      notice: AppI18n.trForLocale(
        sessionStore.appLocale.languageCode,
        "auth.session_expired",
      ),
    ),
  );
  // Restore a persisted session (secure storage) so a returning user is not
  // forced to log in again after closing the app. Must run after the token
  // manager is configured (silent refresh of an expired access token).
  await sessionStore.restoreFromStorage();

  // Firebase (push notifications). Disabled on web: the firebase_messaging web
  // init can HANG (no VAPID configured / unreachable push endpoints), and a
  // hanging await — unlike an exception — is not caught by try/catch, so it
  // would block runApp() and blank the app. Mobile keeps Firebase. Matches the
  // guard already used by the Pro app.
  if (!kIsWeb) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await PushNotificationService.initialize();
    } catch (e) {
      debugPrint('[Firebase] init skipped: $e');
    }
  }

  // Panier serveur : synchro best-effort des mutations locales (persistant,
  // multi-appareils). L'hydratation au démarrage se fait dans ClientShell.
  final cartApi = ApiService();
  final buyerStore = BuyerStore();
  buyerStore.configureCartSync(
    onUpsert: (productId, quantity) async {
      final token = sessionStore.token;
      if (token == null || token.isEmpty) return;
      try {
        await cartApi.post(
          "/api/cart/",
          {"product": productId, "quantity": quantity},
          token: token,
        );
      } catch (_) {}
    },
    onRemove: (productId) async {
      final token = sessionStore.token;
      if (token == null || token.isEmpty) return;
      try {
        await cartApi.post("/api/cart/remove/", {"product": productId}, token: token);
      } catch (_) {}
    },
    onClear: () async {
      final token = sessionStore.token;
      if (token == null || token.isEmpty) return;
      try {
        await cartApi.post("/api/cart/clear/", {}, token: token);
      } catch (_) {}
    },
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionStore>.value(value: sessionStore),
        ChangeNotifierProvider<BuyerStore>.value(value: buyerStore),
      ],
      child: const ClientsApp(),
    ),
  );
}

class ClientsApp extends StatelessWidget {
  const ClientsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return MaterialApp(
      title: 'Market CM Clients',
      debugShowCheckedModeBanner: false,
      locale: session.appLocale,
      supportedLocales: const [
        Locale("fr"),
        Locale("en"),
      ],
      localizationsDelegates: const [
        CountryLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      builder: (context, child) => CmResponsive.appWrap(context, child),
      home: AppGate(
        systemEvents: RealtimeEventsService.instance.events,
        child: const _RootEntryPoint(),
      ),
    );
  }
}

class _RootEntryPoint extends StatefulWidget {
  const _RootEntryPoint();

  @override
  State<_RootEntryPoint> createState() => _RootEntryPointState();
}

class _RootEntryPointState extends State<_RootEntryPoint> {
  bool _bootSplashDone = false;
  String? _lastShownNotice;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _eventsSub = RealtimeEventsService.instance.events.listen(_onRealtimeEvent);
    if (AppConfig.authBypass) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final session = context.read<SessionStore>();
        final bypassToken = AppConfig.authBypassToken.trim();
        if (bypassToken.isEmpty) {
          return;
        }
        if (!session.isAuthenticated) {
          session.setSession(
            accessToken: bypassToken,
            userRole: UserRole.generalAdmin,
            currentUserId: 1,
            currentUsername: "debug.admin",
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootSplashDone) {
      return CmSplashScreen(
        onCompleted: () {
          if (!mounted) return;
          setState(() => _bootSplashDone = true);
        },
      );
    }

    final session = context.watch<SessionStore>();
    _syncRealtimeConnection(session);
    if (!session.isAuthenticated &&
        session.authNotice != null &&
        session.authNotice != _lastShownNotice) {
      final notice = session.consumeAuthNotice();
      if (notice != null && notice.isNotEmpty) {
        _lastShownNotice = notice;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(notice)),
          );
        });
      }
    }
    if (!session.isAuthenticated) {
      return PublicHomePage(
        onLoginRequested: _openAuthWithSplash,
        onRegisterRequested: _openAuthWithSplash,
      );
    }
    if (session.role != UserRole.buyer) {
      return _ProAccountBlockedPage(
        role: session.role,
        onLogout: () => session.logout(),
      );
    }
    return const ClientShell();
  }

  void _syncRealtimeConnection(SessionStore session) {
    final token = session.token?.trim() ?? "";
    if (token.isNotEmpty) {
      RealtimeEventsService.instance.connect(accessToken: token);
      return;
    }
    RealtimeEventsService.instance.disconnect();
  }

  void _onRealtimeEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final session = context.read<SessionStore>();
    if (!session.isAuthenticated) {
      return;
    }
    final topic = (event["topic"] ?? "").toString();
    final type = (event["type"] ?? "").toString();
    // "resync" est un signal interne émis par RealtimeEventsService après
    // reconnexion pour déclencher un rechargement silencieux des pages — ce
    // n'est jamais une notification destinée à l'utilisateur.
    if (type == "resync") return;
    final payload = event["payload"] is Map<String, dynamic>
        ? event["payload"] as Map<String, dynamic>
        : const <String, dynamic>{};

    final message = _eventMessage(topic: topic, type: type, payload: payload);
    if (message.isEmpty) {
      return;
    }

    final notificationId = _readInt(payload["notification_id"]);
    final createdAtRaw = (payload["created_at"] ?? "").toString();
    final createdAt = DateTime.tryParse(createdAtRaw);
    context.read<BuyerStore>().pushNotification(
          message,
          topic: topic,
          remoteId: notificationId,
          createdAt: createdAt,
        );
    if (topic == "notifications" || topic == "support") {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _eventMessage({
    required String topic,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final lang = context.read<SessionStore>().appLocale.languageCode;
    if (topic == "notifications" && type == "notification_created") {
      final title = (payload["title"] ?? "").toString().trim();
      final body = (payload["body"] ?? "").toString().trim();
      if (title.isNotEmpty && body.isNotEmpty) {
        return "$title - $body";
      }
      if (title.isNotEmpty) {
        return title;
      }
    }
    if (topic == "support") {
      final ticketId = (payload["ticket_id"] ?? "").toString();
      if (type == "ticket_created") {
        return AppI18n.trForLocale(
          lang,
          "tickets.event.created",
          params: {"ticket_id": ticketId},
        );
      }
      if (type == "ticket_updated") {
        return AppI18n.trForLocale(
          lang,
          "tickets.event.updated",
          params: {"ticket_id": ticketId},
        );
      }
      if (type == "ticket_message_created") {
        return AppI18n.trForLocale(
          lang,
          "tickets.event.message",
          params: {"ticket_id": ticketId},
        );
      }
      if (type == "ticket_closed") {
        return AppI18n.trForLocale(
          lang,
          "tickets.event.closed",
          params: {"ticket_id": ticketId},
        );
      }
      if (type == "ticket_assigned") {
        return AppI18n.trForLocale(
          lang,
          "tickets.event.assigned",
          params: {"ticket_id": ticketId},
        );
      }
    }
    if (topic.isEmpty) return "";
    final fallback = type.isEmpty
        ? AppI18n.trForLocale(lang, "realtime.generic_update")
        : type;
    return "[${topic.toUpperCase()}] $fallback";
  }

  int? _readInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse((raw ?? "").toString());
  }

  Future<void> _openAuthWithSplash() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => CmSplashScreen(
          onCompleted: () {
            if (Navigator.of(routeContext).canPop()) {
              Navigator.of(routeContext).pop();
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthPage()),
    );
  }
}

class _ProAccountBlockedPage extends StatelessWidget {
  const _ProAccountBlockedPage({required this.role, required this.onLogout});

  final UserRole role;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.store, size: 72, color: Colors.orange),
                const SizedBox(height: 24),
                Text(
                  "Compte professionnel détecté",
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Cette application est réservée aux acheteurs.\n"
                  "Pour accéder à votre espace professionnel (vendeur, grossiste, fournisseur, livreur ou admin), "
                  "veuillez utiliser l'application Market CM Pro.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(LucideIcons.logOut),
                  label: const Text("Se déconnecter"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

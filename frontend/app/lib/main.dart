import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_config.dart';
import 'core/app_i18n.dart';
import 'core/app_theme.dart';
import 'core/push_notification_service.dart';
import 'core/realtime_events_service.dart';
import 'core/security/secure_dio_client.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/session_store.dart';
import 'features/buyer/buyer_store.dart';
import 'features/home/public_home_page.dart';
import 'features/shell/main_shell.dart';
import 'features/splash/cm_splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — requires google-services.json (Android) / GoogleService-Info.plist (iOS).
  bool firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
  } catch (e) {
    debugPrint('[Firebase] Init skipped: $e');
  }

  final sessionStore = SessionStore();

  // Single Dio client — reads/writes tokens only through TokenRepository.
  await SecureDioClient.initialize(
    onTokensRefreshed: (accessToken, refreshToken) {
      sessionStore.updateTokens(
        accessToken: accessToken,
        refreshTokenValue: refreshToken,
      );
    },
    onAuthFailed: () => sessionStore.logout(
      notice: AppI18n.trForLocale(
        sessionStore.appLocale.languageCode,
        'auth.session_expired',
      ),
    ),
  );

  // Restore tokens from secure storage (survives app restarts).
  await sessionStore.restoreFromStorage();

  // FCM push notifications (foreground token registration + background handler).
  if (firebaseReady) {
    await PushNotificationService.initialize();

    // Show foreground FCM messages as snackbars via the global scaffold.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        final title = notification.title ?? '';
        final body = notification.body ?? '';
        _globalSnackbarKey.currentState?.showSnackBar(
          SnackBar(content: Text(title.isNotEmpty ? '$title — $body' : body)),
        );
      }
    });
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SessionStore>.value(value: sessionStore),
        ChangeNotifierProvider(create: (_) => BuyerStore()),
      ],
      child: MarcheCmApp(scaffoldKey: _globalSnackbarKey),
    ),
  );
}

final GlobalKey<ScaffoldMessengerState> _globalSnackbarKey =
    GlobalKey<ScaffoldMessengerState>();

class MarcheCmApp extends StatelessWidget {
  const MarcheCmApp({super.key, required this.scaffoldKey});

  final GlobalKey<ScaffoldMessengerState> scaffoldKey;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return MaterialApp(
      title: 'Marche CM Pro',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldKey,
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
      home: const _RootEntryPoint(),
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
        if (bypassToken.isEmpty) return;
        if (!session.isAuthenticated) {
          session.setSession(
            accessToken: bypassToken,
            userRole: UserRole.generalAdmin,
            currentUserId: 1,
            currentUsername: 'debug.admin',
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
    if (session.role == UserRole.buyer) {
      return _BuyerAccountBlockedPage(onLogout: () => session.logout());
    }
    return const MainShell();
  }

  void _syncRealtimeConnection(SessionStore session) {
    final token = session.token?.trim() ?? '';
    if (token.isNotEmpty) {
      RealtimeEventsService.instance.connect(accessToken: token);
      return;
    }
    RealtimeEventsService.instance.disconnect();
  }

  void _onRealtimeEvent(Map<String, dynamic> event) {
    if (!mounted) return;
    final session = context.read<SessionStore>();
    if (!session.isAuthenticated) return;

    final topic = (event['topic'] ?? '').toString();
    final type = (event['type'] ?? '').toString();
    final payload = event['payload'] is Map<String, dynamic>
        ? event['payload'] as Map<String, dynamic>
        : const <String, dynamic>{};

    final message = _eventMessage(topic: topic, type: type, payload: payload);
    if (message.isEmpty) return;

    final notificationId = _readInt(payload['notification_id']);
    final createdAt = DateTime.tryParse((payload['created_at'] ?? '').toString());
    context.read<BuyerStore>().pushNotification(
          message,
          topic: topic,
          remoteId: notificationId,
          createdAt: createdAt,
        );
    if (topic == 'notifications' || topic == 'support') {
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
    if (topic == 'notifications' && type == 'notification_created') {
      final title = (payload['title'] ?? '').toString().trim();
      final body = (payload['body'] ?? '').toString().trim();
      if (title.isNotEmpty && body.isNotEmpty) return '$title - $body';
      if (title.isNotEmpty) return title;
    }
    if (topic == 'support') {
      final ticketId = (payload['ticket_id'] ?? '').toString();
      if (type == 'ticket_created') {
        return AppI18n.trForLocale(lang, 'tickets.event.created',
            params: {'ticket_id': ticketId});
      }
      if (type == 'ticket_updated') {
        return AppI18n.trForLocale(lang, 'tickets.event.updated',
            params: {'ticket_id': ticketId});
      }
      if (type == 'ticket_message_created') {
        return AppI18n.trForLocale(lang, 'tickets.event.message',
            params: {'ticket_id': ticketId});
      }
      if (type == 'ticket_closed') {
        return AppI18n.trForLocale(lang, 'tickets.event.closed',
            params: {'ticket_id': ticketId});
      }
      if (type == 'ticket_assigned') {
        return AppI18n.trForLocale(lang, 'tickets.event.assigned',
            params: {'ticket_id': ticketId});
      }
    }
    if (topic.isEmpty) return '';
    final fallback = type.isEmpty
        ? AppI18n.trForLocale(lang, 'realtime.generic_update')
        : type;
    return '[${topic.toUpperCase()}] $fallback';
  }

  int? _readInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse((raw ?? '').toString());
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

class _BuyerAccountBlockedPage extends StatelessWidget {
  const _BuyerAccountBlockedPage({required this.onLogout});

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
                const Icon(Icons.shopping_bag_outlined,
                    size: 72, color: Colors.green),
                const SizedBox(height: 24),
                Text(
                  'Compte acheteur détecté',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Cette application est réservée aux professionnels (vendeurs, grossistes, fournisseurs, transitaires, admin).\n'
                  'Pour faire vos achats, veuillez utiliser l\'application Marche CM Clients.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

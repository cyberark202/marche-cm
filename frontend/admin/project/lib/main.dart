import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_gate.dart';
import 'core/app_theme.dart';
import 'core/cm_components.dart';
import 'core/network_quality_service.dart';
import 'core/push_notification_service.dart';
import 'core/realtime_events_service.dart';
import 'core/security/secure_dio_client.dart';
import 'firebase_options.dart';
import 'features/auth/admin_login_page.dart';
import 'features/auth/session_store.dart';
import 'features/shell/admin_shell.dart';
import 'features/splash/cm_splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  NetworkQualityService.instance.init();

  final session = AdminSessionStore();

  await SecureDioClient.initialize(
    onTokensRefreshed: (accessToken, refreshToken) {
      session.updateTokens(
        accessToken: accessToken,
        refreshTokenValue: refreshToken,
      );
    },
    onAuthFailed: () =>
        session.logout(notice: 'Session expirée. Veuillez vous reconnecter.'),
  );

  await session.restoreFromStorage();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('[Firebase] init skipped: $e');
  }

  runApp(
    ChangeNotifierProvider<AdminSessionStore>.value(
      value: session,
      child: const AdminConsoleApp(),
    ),
  );
}

class AdminConsoleApp extends StatelessWidget {
  const AdminConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Market CM Admin',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      builder: (context, child) =>
          CmResponsive.appWrap(context, child, maxWidth: 1280),
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

  @override
  Widget build(BuildContext context) {
    if (!_bootSplashDone) {
      return CmSplashScreen(
        onCompleted: () {
          if (mounted) setState(() => _bootSplashDone = true);
        },
      );
    }

    final session = context.watch<AdminSessionStore>();
    _syncRealtime(session);

    final notice = session.authNotice;
    if (!session.isAuthenticated &&
        notice != null &&
        notice != _lastShownNotice) {
      _lastShownNotice = session.consumeAuthNotice();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lastShownNotice ?? notice)),
        );
      });
    }

    if (!session.isAuthenticated || !session.isAdmin) {
      return const AdminLoginPage();
    }
    return const AdminShell();
  }

  void _syncRealtime(AdminSessionStore session) {
    if (session.isAuthenticated && session.isAdmin) {
      RealtimeEventsService.instance.connectFromStorage();
    } else {
      RealtimeEventsService.instance.disconnect();
    }
  }
}

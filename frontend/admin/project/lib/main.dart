import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'core/security/secure_dio_client.dart';
import 'features/auth/admin_login_page.dart';
import 'features/auth/session_store.dart';
import 'features/shell/admin_shell.dart';
import 'features/splash/admin_splash.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = AdminSessionStore();

  // Single Dio client — reads/writes tokens only through TokenRepository.
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

  // Restore an admin session from secure storage (survives restarts).
  await session.restoreFromStorage();

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
      title: 'Marché CM · Admin',
      debugShowCheckedModeBanner: false,
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

  @override
  Widget build(BuildContext context) {
    if (!_bootSplashDone) {
      return AdminSplash(
        onCompleted: () {
          if (mounted) setState(() => _bootSplashDone = true);
        },
      );
    }

    final session = context.watch<AdminSessionStore>();

    // Surface a one-shot auth notice (expired session, rejected role…).
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
}

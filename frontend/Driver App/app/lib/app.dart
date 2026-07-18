import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_gate.dart';
import 'core/cm_components.dart';
import 'core/realtime_events_service.dart';
import 'core/theme/driver_theme.dart';
import 'features/auth/application/auth_notifier.dart';
import 'routing/driver_router.dart';

class DriverApp extends ConsumerWidget {
  const DriverApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(driverRouterProvider);

    final isAuthenticated =
        ref.watch(authProvider.select((s) => s.isAuthenticated));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isAuthenticated) {
        RealtimeEventsService.instance.connectFromStorage();
      } else {
        RealtimeEventsService.instance.disconnect();
      }
    });

    return MaterialApp.router(
      title: 'Market CM Driver',
      debugShowCheckedModeBanner: false,
      theme: DriverTheme.light(),
      routerConfig: router,
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => AppGate(
        systemEvents: RealtimeEventsService.instance.events,
        child: CmResponsive.appWrap(context, child),
      ),
    );
  }
}

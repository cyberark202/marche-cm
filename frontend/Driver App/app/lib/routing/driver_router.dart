import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_notifier.dart';
import '../features/auth/domain/auth_state.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/onboarding_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/delivery/presentation/active_delivery_page.dart';
import '../features/delivery/presentation/delivery_proof_page.dart';
import '../features/delivery/presentation/otp_validation_page.dart';
import '../features/delivery/presentation/pickup_confirmation_page.dart';
import '../features/missions/presentation/mission_detail_page.dart';
import '../features/missions/presentation/missions_list_page.dart';
import '../features/profile/presentation/documents_page.dart';
import '../features/profile/presentation/profile_page.dart';
import '../features/profile/presentation/vehicle_page.dart';
import '../features/dashboard/presentation/dashboard_page.dart';
import '../features/shell/driver_shell.dart';
import '../features/tracking/presentation/tracking_page.dart';
import '../features/wallet/presentation/earnings_page.dart';
import '../features/wallet/presentation/wallet_page.dart';
import '../features/wallet/presentation/withdrawal_page.dart';

final driverRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: notifier,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;

      final isAuth = auth.isAuthenticated;
      final isOnboarded = auth.isOnboarded;
      final loc = state.uri.path;

      final isAuthRoute = loc.startsWith('/login') || loc.startsWith('/register');

      if (!isAuth && !isAuthRoute) return '/login';
      if (isAuth && !isOnboarded && loc != '/onboarding') return '/onboarding';
      if (isAuth && isOnboarded && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      // ── Auth ─────────────────────────────────────────────
      GoRoute(
        path: '/login',
        pageBuilder: (_, state) =>
            NoTransitionPage(key: state.pageKey, child: const LoginPage()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, state) =>
            MaterialPage(key: state.pageKey, child: const RegisterPage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, state) =>
            MaterialPage(key: state.pageKey, child: const OnboardingPage()),
      ),

      // ── Main shell ────────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => DriverShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const DashboardPage()),
          ),
          GoRoute(
            path: '/missions',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const MissionsListPage()),
            routes: [
              GoRoute(
                path: ':id',
                pageBuilder: (_, state) => MaterialPage(
                    key: state.pageKey,
                    child: MissionDetailPage(
                        missionId: state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/active',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const ActiveDeliveryPage()),
            routes: [
              GoRoute(
                path: 'pickup/:shipmentId',
                pageBuilder: (_, state) => MaterialPage(
                    key: state.pageKey,
                    child: PickupConfirmationPage(
                        shipmentId: state.pathParameters['shipmentId']!)),
              ),
              GoRoute(
                path: 'proof/:shipmentId',
                pageBuilder: (_, state) => MaterialPage(
                    key: state.pageKey,
                    child: DeliveryProofPage(
                        shipmentId: state.pathParameters['shipmentId']!)),
              ),
              GoRoute(
                path: 'otp/:shipmentId',
                pageBuilder: (_, state) => MaterialPage(
                    key: state.pageKey,
                    child: OtpValidationPage(
                        shipmentId: state.pathParameters['shipmentId']!)),
              ),
              GoRoute(
                path: 'tracking/:shipmentId',
                pageBuilder: (_, state) => MaterialPage(
                    key: state.pageKey,
                    child: TrackingPage(
                        shipmentId: state.pathParameters['shipmentId']!)),
              ),
            ],
          ),
          GoRoute(
            path: '/wallet',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const DriverWalletPage()),
            routes: [
              GoRoute(
                  path: 'earnings',
                  pageBuilder: (_, state) => MaterialPage(
                      key: state.pageKey, child: const EarningsPage())),
              GoRoute(
                  path: 'withdraw',
                  pageBuilder: (_, state) => MaterialPage(
                      key: state.pageKey, child: const WithdrawalPage())),
            ],
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, state) => NoTransitionPage(
                key: state.pageKey, child: const ProfilePage()),
            routes: [
              GoRoute(
                  path: 'documents',
                  pageBuilder: (_, state) => MaterialPage(
                      key: state.pageKey, child: const DocumentsPage())),
              GoRoute(
                  path: 'vehicle',
                  pageBuilder: (_, state) => MaterialPage(
                      key: state.pageKey, child: const VehiclePage())),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Page introuvable : ${state.error}')),
    ),
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  final Ref _ref;
  _AuthRefreshNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, __) => notifyListeners());
  }
}

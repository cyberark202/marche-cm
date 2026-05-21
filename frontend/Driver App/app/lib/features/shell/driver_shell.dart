import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/driver_theme.dart';

class DriverShell extends StatelessWidget {
  final Widget child;
  const DriverShell({super.key, required this.child});

  static const _tabs = [
    _Tab('/dashboard', 'Accueil'),
    _Tab('/missions',  'Demandes'),
    _Tab('/active',    'Mes courses'),
    _Tab('/wallet',    'Gains'),
    _Tab('/profile',   'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: T.surface,
          border: Border(top: BorderSide(color: T.line2)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final active = index == i;
                return Expanded(
                  child: InkWell(
                    onTap: () => context.go(_tabs[i].path),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: active ? T.primarySoft : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(T.rFull),
                          ),
                          child: Icon(
                            _tabs[i].icon(active),
                            size: 22,
                            color: active ? T.primary : T.ink3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _tabs[i].label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: active ? T.primary : T.ink3,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String path;
  final String label;
  const _Tab(this.path, this.label);

  IconData icon(bool active) => switch (path) {
        '/dashboard' => active ? Icons.home : Icons.home_outlined,
        '/missions'  => active ? Icons.balance : Icons.balance_outlined,
        '/active'    =>
          active ? Icons.local_shipping : Icons.local_shipping_outlined,
        '/wallet'    =>
          active ? Icons.account_balance_wallet : Icons.account_balance_wallet_outlined,
        '/profile'   => active ? Icons.person : Icons.person_outline,
        _            => Icons.circle,
      };
}

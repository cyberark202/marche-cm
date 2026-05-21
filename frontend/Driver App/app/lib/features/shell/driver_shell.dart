import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/driver_theme.dart';

class DriverShell extends StatelessWidget {
  final Widget child;
  const DriverShell({super.key, required this.child});

  static const _tabs = [
    _Tab('/missions', Icons.assignment_outlined, Icons.assignment, 'Missions'),
    _Tab('/active', Icons.local_shipping_outlined, Icons.local_shipping, 'En cours'),
    _Tab('/wallet', Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet, 'Gains'),
    _Tab('/profile', Icons.person_outline, Icons.person, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    int index = _tabs.indexWhere((t) => location.startsWith(t.path));
    if (index < 0) index = 0;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.selectedIcon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _Tab {
  final String path;
  final IconData icon, selectedIcon;
  final String label;
  const _Tab(this.path, this.icon, this.selectedIcon, this.label);
}

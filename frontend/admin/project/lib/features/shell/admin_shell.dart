import 'package:flutter/material.dart';

import '../audit/audit_page.dart';
import '../config/configuration_page.dart';
import '../dashboard/admin_dashboard_page.dart';
import '../disputes/disputes_page.dart';
import '../profile/admin_profile_page.dart';
import '../users/users_page.dart';
import '../wallet/reconciliation_page.dart';

/// Bottom-nav host matching catalogue screen 32 footer:
/// Accueil · Comptes · Litiges · Wallet · Profil.
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    AdminDashboardPage(onNavigate: _goTo, onOpenAudit: _openAudit, onOpenConfig: _openConfig),
    const UsersPage(),
    const DisputesPage(),
    const ReconciliationPage(),
    const AdminProfilePage(),
  ];

  void _goTo(int index) => setState(() => _index = index);

  void _openAudit() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuditPage()),
      );

  void _openConfig() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ConfigurationPage()),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Comptes',
          ),
          NavigationDestination(
            icon: Icon(Icons.gavel_outlined),
            selectedIcon: Icon(Icons.gavel),
            label: 'Litiges',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

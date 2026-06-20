import 'package:flutter/material.dart';

import '../../core/cm_components.dart';
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
      bottomNavigationBar: CmBottomNav(
        currentIndex: _index,
        onSelect: _goTo,
        items: const [
          CmNavItem(icon: Icons.dashboard_outlined, label: 'Accueil'),
          CmNavItem(icon: Icons.group_outlined, label: 'Comptes'),
          CmNavItem(icon: Icons.gavel_outlined, label: 'Litiges'),
          CmNavItem(
              icon: Icons.account_balance_wallet_outlined, label: 'Wallet'),
          CmNavItem(icon: Icons.person_outline, label: 'Profil'),
        ],
      ),
    );
  }
}

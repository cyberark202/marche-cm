import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../auth/auth_api_service.dart';
import '../auth/session_store.dart';
import '../config/configuration_page.dart';

/// Screen 42 — Admin profile: identity, permissions, security, logout.
class AdminProfilePage extends StatelessWidget {
  const AdminProfilePage({super.key});

  Future<void> _logout(BuildContext context) async {
    final session = context.read<AdminSessionStore>();
    final refresh = session.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      try {
        await AuthApiService().logout(refreshToken: refresh);
      } catch (_) {/* best-effort server-side revoke */}
    }
    session.logout();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSessionStore>();
    final name = session.username ?? 'Administrateur';
    final email = session.email ?? '—';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Profil admin',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 14),
            SectionCard(
              child: Row(
                children: [
                  AvatarChip(Fmt.initials(name),
                      size: 56, color: AppPalette.secondary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Row(
                          children: const [
                            StatusPill('SUPER ADMIN',
                                color: AppPalette.secondary),
                            SizedBox(width: 6),
                            StatusPill('2FA', color: AppPalette.success),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Compte'),
            SectionCard(
              child: Column(
                children: [
                  _kv(Icons.mail_outline, 'E-mail professionnel', email),
                  const Divider(height: 18),
                  _kv(Icons.verified_user_outlined, 'Authentification',
                      '2FA e-mail active'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const SectionLabel('Permissions'),
            SectionCard(
              child: Column(
                children: const [
                  _PermissionRow(
                      label: 'Gérer les utilisateurs',
                      sub: 'Création, suspension'),
                  Divider(height: 18),
                  _PermissionRow(
                      label: 'Décider les litiges',
                      sub: 'Arbitrage final'),
                  Divider(height: 18),
                  _PermissionRow(
                      label: 'Wallet & FinOps',
                      sub: 'Réconciliation, retraits'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConfigurationPage()),
              ),
              child: Row(
                children: const [
                  Icon(Icons.tune, color: AppPalette.textMuted),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Configuration de la plateforme',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.chevron_right, color: AppPalette.textMuted),
                ],
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _logout(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppPalette.danger,
                side: const BorderSide(color: AppPalette.danger),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppPalette.textMuted),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.textMuted)),
              Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.sub});
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(sub,
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.textMuted)),
            ],
          ),
        ),
        const StatusPill('ON', color: AppPalette.success),
      ],
    );
  }
}

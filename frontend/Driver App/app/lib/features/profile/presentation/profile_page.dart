import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/driver_theme.dart';
import '../../auth/application/auth_notifier.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final username = auth.username ?? 'Livreur';
    final initials = username.isNotEmpty
        ? username.trim().split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase()
        : 'L';

    return Scaffold(
      backgroundColor: DriverPalette.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 180,
            backgroundColor: DriverPalette.primary,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: DriverPalette.heroGradient),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 40),
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: Colors.white.withValues(alpha: 0.25),
                      child: Text(initials,
                          style: const TextStyle(color: Colors.white, fontSize: 24,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 10),
                    Text(username,
                        style: const TextStyle(color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    Text('Livreur Market CM',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _Section(title: 'Mon compte', items: [
                    _MenuItem(icon: Icons.assignment_outlined, label: 'Mes missions',
                        onTap: () => context.go('/missions')),
                    _MenuItem(icon: Icons.account_balance_wallet_outlined, label: 'Mon portefeuille',
                        onTap: () => context.go('/wallet')),
                  ]),
                  const SizedBox(height: 16),
                  _Section(title: 'Profil livreur', items: [
                    _MenuItem(icon: Icons.two_wheeler_outlined, label: 'Mon véhicule',
                        onTap: () => context.push('/profile/vehicle')),
                    _MenuItem(icon: Icons.badge_outlined, label: 'Mes documents',
                        onTap: () => context.push('/profile/documents')),
                  ]),
                  const SizedBox(height: 16),
                  _Section(title: 'Support', items: [
                    _MenuItem(icon: Icons.help_outline, label: 'Aide & FAQ', onTap: () {}),
                    _MenuItem(icon: Icons.policy_outlined, label: 'Conditions d\'utilisation',
                        onTap: () {}),
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Se déconnecter'),
                            content: const Text('Confirmer la déconnexion ?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Annuler')),
                              FilledButton(onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Déconnecter')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          await ref.read(authProvider.notifier).logout();
                        }
                      },
                      icon: const Icon(Icons.logout, color: Color(0xFFDC2626)),
                      label: const Text('Se déconnecter',
                          style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: DriverPalette.textMuted, letterSpacing: 0.8)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DriverPalette.border),
        ),
        child: Column(
          children: items.indexed.map((entry) {
            final (i, item) = entry;
            return Column(children: [
              item,
              if (i < items.length - 1) const Divider(height: 1, indent: 52),
            ]);
          }).toList(),
        ),
      ),
    ],
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: DriverPalette.primary, size: 22),
    title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
        color: DriverPalette.textPrimary)),
    trailing: const Icon(Icons.chevron_right, color: DriverPalette.textMuted, size: 20),
    onTap: onTap,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
  );
}

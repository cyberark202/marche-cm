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
    final initials = username.trim().split(' ').where((w) => w.isNotEmpty)
        .map((w) => w[0]).take(2).join().toUpperCase();

    return Scaffold(
      backgroundColor: T.bg,
      body: CustomScrollView(
        slivers: [
          // ── Hero amber ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: T.gradientDriverHeader,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2),
                        ),
                        child: Center(
                          child: Text(
                            initials.isEmpty ? 'L' : initials,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(username,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text('Livreur indépendant',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.8))),
                      const SizedBox(height: 16),
                      // Stats row
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            const _Stat(value: '4,8', label: 'Note'),
                            _Divider(),
                            const _Stat(value: '148', label: 'Livraisons'),
                            _Divider(),
                            const _Stat(value: '98 %', label: 'Ponctualité'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Menu sections ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _Section(title: 'Mon activité', items: [
                  _MenuItem(
                    icon: Icons.balance,
                    label: 'Mes demandes',
                    onTap: () => context.go('/missions'),
                  ),
                  _MenuItem(
                    icon: Icons.local_shipping_outlined,
                    label: 'Mes courses',
                    onTap: () => context.go('/active'),
                  ),
                  _MenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Mon portefeuille',
                    onTap: () => context.go('/wallet'),
                  ),
                ]),
                const SizedBox(height: 14),
                _Section(title: 'Profil livreur', items: [
                  _MenuItem(
                    icon: Icons.two_wheeler_outlined,
                    label: 'Mon véhicule',
                    onTap: () => context.push('/profile/vehicle'),
                  ),
                  _MenuItem(
                    icon: Icons.badge_outlined,
                    label: 'Mes documents KYC',
                    onTap: () => context.push('/profile/documents'),
                  ),
                ]),
                const SizedBox(height: 14),
                _Section(title: 'Support', items: [
                  _MenuItem(
                    icon: Icons.help_outline,
                    label: 'Aide & FAQ',
                    onTap: () {},
                  ),
                  _MenuItem(
                    icon: Icons.policy_outlined,
                    label: "Conditions d'utilisation",
                    onTap: () {},
                  ),
                ]),
                const SizedBox(height: 20),
                // Logout button
                GestureDetector(
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Se déconnecter'),
                        content: const Text('Confirmer la déconnexion ?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Annuler')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Déconnecter')),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(authProvider.notifier).logout();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: T.coralSoft,
                      borderRadius: BorderRadius.circular(T.r),
                      border: Border.all(color: T.coral.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout, color: T.coral, size: 18),
                        SizedBox(width: 8),
                        Text('Se déconnecter',
                            style: TextStyle(
                                color: T.coral,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500)),
      ]);
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 28, color: Colors.white.withValues(alpha: 0.3));
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: T.ink4,
                    letterSpacing: 0.8)),
          ),
          Container(
            decoration: BoxDecoration(
              color: T.surface,
              borderRadius: BorderRadius.circular(T.r),
              border: Border.all(color: T.line),
            ),
            child: Column(
              children: items.indexed.map((entry) {
                final (i, item) = entry;
                return Column(children: [
                  item,
                  if (i < items.length - 1)
                    const Divider(height: 1, indent: 52, color: T.line2),
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
  const _MenuItem(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: T.surface2,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: T.ink2, size: 18),
        ),
        title: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: T.ink)),
        trailing:
            const Icon(Icons.chevron_right, color: T.ink4, size: 20),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        minLeadingWidth: 34,
      );
}

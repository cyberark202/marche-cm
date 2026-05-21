import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../wallet/wallet_page.dart';
import 'buyer_kyc_page.dart';

class BuyerProfilePage extends StatelessWidget {
  const BuyerProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final name = session.username ?? 'Utilisateur';
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, name, initials)),
          SliverToBoxAdapter(child: _buildKycBanner(context)),
          SliverToBoxAdapter(child: _buildSection('Mon compte', [
            _MenuItem(
              icon: Icons.shopping_bag_outlined,
              label: 'Mes commandes',
              color: const Color(0xFF4F46E5),
              onTap: () {},
            ),
            _MenuItem(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Mon portefeuille',
              color: const Color(0xFF0F766E),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const WalletPage())),
            ),
            _MenuItem(
              icon: Icons.favorite_outline,
              label: 'Mes favoris',
              color: const Color(0xFFDB2777),
              onTap: () {},
            ),
            _MenuItem(
              icon: Icons.location_on_outlined,
              label: 'Mes adresses',
              color: const Color(0xFFF59E0B),
              onTap: () {},
            ),
          ])),
          SliverToBoxAdapter(child: _buildSection('Sécurité & Confidentialité', [
            _MenuItem(
              icon: Icons.shield_outlined,
              label: 'Vérification d\'identité (KYC)',
              color: const Color(0xFF059669),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const BuyerKycPage())),
              trailing: const _KycBadge(verified: false),
            ),
            _MenuItem(
              icon: Icons.lock_outline,
              label: 'Changer le mot de passe',
              color: const Color(0xFF64748B),
              onTap: () {},
            ),
          ])),
          SliverToBoxAdapter(child: _buildSection('Aide & Support', [
            _MenuItem(
              icon: Icons.help_outline,
              label: 'Centre d\'aide',
              color: const Color(0xFF2563EB),
              onTap: () {},
            ),
            _MenuItem(
              icon: Icons.info_outline,
              label: 'À propos de Market CM',
              color: const Color(0xFF64748B),
              onTap: () {},
            ),
          ])),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: OutlinedButton.icon(
                onPressed: () => session.logout(),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Se déconnecter'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFFCA5A5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String name, String initials) => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: AppPalette.primary.withValues(alpha: 0.12),
              child: Text(initials.isNotEmpty ? initials : '?',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: AppPalette.primary)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                  const Text('Compte Acheteur',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B)),
              onPressed: () {},
            ),
          ],
        ),
      );

  Widget _buildKycBanner(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const BuyerKycPage())),
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Vérifiez votre identité',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    Text('Débloquez toutes les fonctionnalités Market CM',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('Vérifier',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ],
          ),
        ),
      );

  Widget _buildSection(String title, List<_MenuItem> items) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF94A3B8),
                    letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: items
                    .asMap()
                    .entries
                    .map((e) => Column(children: [
                          e.value,
                          if (e.key < items.length - 1)
                            const Divider(height: 1, indent: 56),
                        ]))
                    .toList(),
              ),
            ),
          ],
        ),
      );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final Widget? trailing;
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
              ),
              trailing ?? const Icon(Icons.chevron_right, size: 18, color: Color(0xFFCBD5E1)),
            ],
          ),
        ),
      );
}

class _KycBadge extends StatelessWidget {
  final bool verified;
  const _KycBadge({required this.verified});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: verified
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          verified ? 'Vérifié' : 'En attente',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: verified ? const Color(0xFF16A34A) : const Color(0xFFD97706),
          ),
        ),
      );
}

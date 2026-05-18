import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../business/campaigns_page.dart';
import '../business/rfq_offers_page.dart';
import '../business/rfqs_page.dart';
import '../common/support_center_page.dart';
import '../common/support_tickets_page.dart';
import '../orders/orders_page.dart';
import '../orders/sales_summary_page.dart';
import '../profile/compliance_documents_page.dart';
import '../profile/security_center_page.dart';
import '../supplier/supplier_products_page.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final _api = ApiService();
  Map<String, dynamic> _me = const {};
  List<Map<String, dynamic>> _wallets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getObject('/api/auth/me/', token: token),
        _api.getList('/api/wallets/', token: token),
      ]);
      if (!mounted) return;
      setState(() {
        _me = results[0] as Map<String, dynamic>? ?? const {};
        _wallets = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        color: AppPalette.primary,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _ProfileHeader(
              session: session,
              me: _me,
              wallets: _wallets,
              loading: _loading,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverList.list(children: [
                _buildBusinessSection(context, session),
                const SizedBox(height: 16),
                _buildSecuritySection(context),
                const SizedBox(height: 16),
                _buildSupportSection(context),
                const SizedBox(height: 16),
                _buildAccountSection(context, session),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessSection(BuildContext context, SessionStore session) {
    final isSupplier = session.role == UserRole.supplier;
    final isWholesaler = session.role == UserRole.wholesaler;

    return _SettingsGroup(
      title: 'Mon activité',
      icon: Icons.business_center_rounded,
      children: [
        if (isSupplier) ...[
          _SettingsTile(
            icon: Icons.inventory_2_outlined,
            label: 'Mes produits',
            subtitle: 'Gérer votre catalogue',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupplierProductsPage()),
            ),
          ),
        ],
        _SettingsTile(
          icon: Icons.shopping_bag_outlined,
          label: 'Mes commandes',
          subtitle: 'Historique et suivi',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersPage()),
          ),
        ),
        _SettingsTile(
          icon: Icons.bar_chart_outlined,
          label: 'Résumé des ventes',
          subtitle: 'Chiffre d\'affaires et statistiques',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SalesSummaryPage()),
          ),
        ),
        if (isSupplier || isWholesaler) ...[
          _SettingsTile(
            icon: Icons.request_quote_outlined,
            label: 'Appels d\'offres',
            subtitle: 'RFQ reçus et ouverts',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RfqsPage()),
            ),
          ),
          _SettingsTile(
            icon: Icons.local_offer_outlined,
            label: 'Mes offres RFQ',
            subtitle: 'Offres envoyées',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RfqOffersPage()),
            ),
          ),
          _SettingsTile(
            icon: Icons.campaign_outlined,
            label: 'Campagnes',
            subtitle: 'Marketing et promotions',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CampaignsPage()),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return _SettingsGroup(
      title: 'Sécurité & conformité',
      icon: Icons.shield_outlined,
      children: [
        _SettingsTile(
          icon: Icons.verified_user_outlined,
          label: 'Documents KYC',
          subtitle: 'Vérification et certifications',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ComplianceDocumentsPage()),
          ),
        ),
        _SettingsTile(
          icon: Icons.security_outlined,
          label: 'Centre de sécurité',
          subtitle: '2FA, PIN wallet, sessions',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SecurityCenterPage()),
          ),
        ),
      ],
    );
  }

  Widget _buildSupportSection(BuildContext context) {
    return _SettingsGroup(
      title: 'Support',
      icon: Icons.help_outline_rounded,
      children: [
        _SettingsTile(
          icon: Icons.support_agent_outlined,
          label: 'Centre d\'aide',
          subtitle: 'FAQ et documentation',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SupportCenterPage()),
          ),
        ),
        _SettingsTile(
          icon: Icons.confirmation_number_outlined,
          label: 'Mes tickets',
          subtitle: 'Demandes en cours',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SupportTicketsPage()),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection(BuildContext context, SessionStore session) {
    return _SettingsGroup(
      title: 'Compte',
      icon: Icons.manage_accounts_outlined,
      children: [
        _SettingsTile(
          icon: Icons.language_outlined,
          label: 'Langue',
          subtitle: session.appLocale.languageCode == 'fr'
              ? 'Français'
              : 'English',
          trailing: const Icon(Icons.chevron_right, size: 18,
              color: AppPalette.textMuted),
          onTap: () {
            final newCode =
                session.appLocale.languageCode == 'fr' ? 'en' : 'fr';
            session.setLocale(newCode);
          },
        ),
        _SettingsTile(
          icon: Icons.logout_rounded,
          label: 'Déconnexion',
          labelColor: AppPalette.danger,
          iconColor: AppPalette.danger,
          onTap: () => _confirmLogout(context, session),
        ),
      ],
    );
  }

  Future<void> _confirmLogout(
      BuildContext context, SessionStore session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text(
            'Voulez-vous vraiment vous déconnecter de votre compte ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      session.logout();
    }
  }
}

// ─── Profile Header ───────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.session,
    required this.me,
    required this.wallets,
    required this.loading,
  });

  final SessionStore session;
  final Map<String, dynamic> me;
  final List<Map<String, dynamic>> wallets;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final username = session.username ?? 'Utilisateur';
    final email = (me['email'] ?? '').toString();
    final kycLevel = (me['kyc_level'] ?? 0) is int
        ? (me['kyc_level'] ?? 0) as int
        : int.tryParse('${me['kyc_level'] ?? 0}') ?? 0;
    final isVerified = me['is_verified'] == true;
    final roleLabel = _roleLabel(session.role);
    final balance = wallets.isNotEmpty
        ? (wallets.first['balance'] ?? '0').toString()
        : '—';
    final initials = _initials(username);

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppPalette.gradientHero,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Column(
              children: [
                // Avatar + info
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 2),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12.5,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _Badge(label: roleLabel),
                              const SizedBox(width: 6),
                              _KycBadge(level: kycLevel, verified: isVerified),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Wallet mini card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Solde wallet',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      loading
                          ? Container(
                              width: 80,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            )
                          : Text(
                              '$balance FCFA',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'[\s._]+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  static String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.supplier:
        return 'Fournisseur';
      case UserRole.wholesaler:
        return 'Grossiste';
      case UserRole.transitAgent:
        return 'Transitaire';
      case UserRole.generalAdmin:
        return 'Administrateur';
      default:
        return role.name;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _KycBadge extends StatelessWidget {
  const _KycBadge({required this.level, required this.verified});
  final int level;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final String label;
    if (verified && level >= 2) {
      bg = AppPalette.success.withValues(alpha: 0.85);
      label = 'KYC Vérifié';
    } else if (level >= 1) {
      bg = AppPalette.warning.withValues(alpha: 0.85);
      label = 'KYC Partiel';
    } else {
      bg = Colors.white.withValues(alpha: 0.2);
      label = 'Non vérifié';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified ? Icons.verified_rounded : Icons.info_outline_rounded,
            color: Colors.white,
            size: 10,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings Group ───────────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppPalette.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textMuted,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  const Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 0,
                    color: AppPalette.borderSoft,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.labelColor,
    this.iconColor,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final Color? labelColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (iconColor ?? AppPalette.primary).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor ?? AppPalette.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: labelColor ?? AppPalette.text,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppPalette.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

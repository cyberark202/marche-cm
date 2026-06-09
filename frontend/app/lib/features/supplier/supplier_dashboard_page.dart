import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../business/rfq_offers_page.dart';
import '../feed/video_publish_page.dart';
import '../logistics/seller_dispute_page.dart';
import '../orders/orders_page.dart';
import '../orders/sales_summary_page.dart';
import '../profile/compliance_documents_page.dart';
import '../wallet/wallet_page.dart';
import 'supplier_products_page.dart';

class SupplierDashboardPage extends StatefulWidget {
  const SupplierDashboardPage({super.key});

  @override
  State<SupplierDashboardPage> createState() => _SupplierDashboardPageState();
}

class _SupplierDashboardPageState extends State<SupplierDashboardPage> {
  final ApiService _api = ApiService();
  late Future<_SupplierPayload> _future;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SupplierPayload> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList('/api/products/mine/', token: token),
        _api.getList('/api/orders/', token: token),
        _api.getList('/api/rfqs/', token: token),
        _api.getList('/api/rfq-offers/', token: token),
        _api.getList('/api/wallets/', token: token),
        _api.getList('/api/compliance-documents/', token: token),
      ]);
      return _SupplierPayload(
        products: results[0],
        orders: results[1],
        rfqs: results[2],
        offers: results[3],
        wallets: results[4],
        complianceDocs: results[5],
        fallback: false,
      );
    } catch (_) {
      return const _SupplierPayload(
        products: <Map<String, dynamic>>[],
        orders: <Map<String, dynamic>>[],
        rfqs: <Map<String, dynamic>>[],
        offers: <Map<String, dynamic>>[],
        wallets: <Map<String, dynamic>>[],
        complianceDocs: <Map<String, dynamic>>[],
        fallback: false,
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _onBottomNavTapped(int index) {
    setState(() => _navIndex = index);
    if (index == 0) return;
    if (index == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SupplierProductsPage()),
      );
      return;
    }
    if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const OrdersPage()),
      );
      return;
    }
    if (index == 3) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RfqOffersPage()),
      );
      return;
    }
    if (index == 4) {
      _openModules();
    }
  }

  void _openModules() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.smart_display_outlined),
              title: const Text('Publication video'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const VideoPublishPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Certifications'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ComplianceDocumentsPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Wallet'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Litiges'),
              subtitle: const Text('Contre acheteur ou transitaire'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SellerDisputePage()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: FutureBuilder<_SupplierPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payload = snapshot.data!;
          final confirmedOrders = payload.orders
              .where((o) => '${o['status']}' == 'CONFIRMED')
              .length;
          final activeProducts =
              payload.products.where((p) => p['is_active'] == true).length;
          final pendingCompliance = payload.complianceDocs
              .where((d) => '${d['status']}' == 'PENDING')
              .length;
          final wallet = payload.wallets.isEmpty
              ? const <String, dynamic>{}
              : payload.wallets.first;
          final walletBalance = '${wallet['balance'] ?? '0'}';
          final walletBlocked = '${wallet['blocked_balance'] ?? '0'}';

          return CustomScrollView(
            slivers: [
              // ── Hero header ───────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: AppPalette.gradientHero,
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(AppRadii.xl),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Titre + badge rôle
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Bonjour 👋',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      session.username ?? 'Utilisateur',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              _RoleBadge(session: session),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: _refresh,
                                child: const Icon(
                                  Icons.refresh,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Balance card
                          _BalanceCard(
                            balance: walletBalance,
                            blocked: walletBlocked,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── KPI grid ─────────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.5,
                  children: [
                    _KpiCard(
                      icon: Icons.inventory_2_outlined,
                      iconColor: AppPalette.primary,
                      value: '$activeProducts',
                      label: 'Produits actifs',
                      subLabel: 'ce mois',
                    ),
                    _KpiCard(
                      icon: Icons.shopping_bag_outlined,
                      iconColor: AppPalette.secondary,
                      value: '$confirmedOrders',
                      label: 'Commandes',
                      subLabel: 'ce mois',
                    ),
                    _KpiCard(
                      icon: Icons.request_quote_outlined,
                      iconColor: AppPalette.accent,
                      value: '${payload.offers.length}',
                      label: 'Offres RFQ',
                      subLabel: 'à traiter',
                    ),
                    _KpiCard(
                      icon: Icons.account_balance_wallet_outlined,
                      iconColor: AppPalette.success,
                      value: '$walletBalance FCFA',
                      label: 'Solde wallet',
                      subLabel: 'disponible',
                    ),
                  ],
                ),
              ),

              // ── Accès rapides ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Accès rapides',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _QuickButton(
                            icon: Icons.inventory_2_outlined,
                            iconColor: AppPalette.primary,
                            label: 'Produits',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SupplierProductsPage()),
                            ),
                          ),
                          _QuickButton(
                            icon: Icons.shopping_bag_outlined,
                            iconColor: AppPalette.secondary,
                            label: 'Commandes',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const OrdersPage()),
                            ),
                          ),
                          _QuickButton(
                            icon: Icons.bar_chart_outlined,
                            iconColor: AppPalette.accent,
                            label: 'Ventes',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const SalesSummaryPage()),
                            ),
                          ),
                          _QuickButton(
                            icon: Icons.video_camera_back_outlined,
                            iconColor: AppPalette.info,
                            label: 'Vidéo',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const VideoPublishPage()),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // ── Conformité ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Conformité',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.text,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppPalette.borderSoft),
                          boxShadow: AppPalette.shadowSoft,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppPalette.primary
                                  .withValues(alpha: 0.10),
                              borderRadius:
                                  BorderRadius.circular(AppRadii.xs),
                            ),
                            child: const Icon(
                              Icons.verified_user_outlined,
                              color: AppPalette.primary,
                              size: 20,
                            ),
                          ),
                          title: const Text(
                            'Documents de conformité',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.text,
                            ),
                          ),
                          subtitle: pendingCompliance > 0
                              ? Text(
                                  '$pendingCompliance document(s) en attente',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.warning,
                                  ),
                                )
                              : const Text(
                                  'Gérez vos certifications KYC',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppPalette.textMuted,
                                  ),
                                ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppPalette.textMuted,
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ComplianceDocumentsPage()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onBottomNavTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Produits',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag),
              label: 'Commandes',
            ),
            NavigationDestination(
              icon: Icon(Icons.request_quote_outlined),
              selectedIcon: Icon(Icons.request_quote),
              label: 'RFQ',
            ),
            NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps),
              label: 'Modules',
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ──────────────────────────────────────────────────────────────

class _SupplierPayload {
  const _SupplierPayload({
    required this.products,
    required this.orders,
    required this.rfqs,
    required this.offers,
    required this.wallets,
    required this.complianceDocs,
    required this.fallback,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> rfqs;
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> complianceDocs;
  final bool fallback;
}

// ── Local widgets ────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.session});
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        session.role.name,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.blocked});
  final String balance;
  final String blocked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: Colors.white70,
            size: 22,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Solde',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$balance FCFA',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Bloqué escrow',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$blocked FCFA',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.subLabel,
  });
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppPalette.text,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppPalette.textMuted,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subLabel != null)
            Text(
              subLabel!,
              style: const TextStyle(
                fontSize: 10,
                color: AppPalette.textFaint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppPalette.borderSoft),
          boxShadow: AppPalette.shadowSoft,
        ),
        child: Column(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppPalette.text,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

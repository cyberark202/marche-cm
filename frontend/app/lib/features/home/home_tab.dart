import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../business/rfq_offers_page.dart';
import '../business/rfqs_page.dart';
import '../feed/video_publish_page.dart';
import '../logistics/shipment_disputes_page.dart';
import '../logistics/transport_profile_page.dart';
import '../orders/orders_page.dart';
import '../orders/sales_summary_page.dart';
import '../supplier/supplier_products_page.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _wallets = const [];
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _products = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    final role = context.read<SessionStore>().role;
    try {
      final futures = <Future<List<Map<String, dynamic>>>>[
        _api.getList('/api/wallets/', token: token),
        _api.getList('/api/orders/', token: token),
      ];
      if (role == UserRole.supplier || role == UserRole.wholesaler) {
        futures.add(_api.getList('/api/products/mine/', token: token));
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      setState(() {
        _wallets = results[0];
        _orders = results[1];
        if (results.length > 2) _products = results[2];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final wallet = _wallets.isNotEmpty ? _wallets.first : <String, dynamic>{};
    final balance = (wallet['balance'] ?? '0').toString();
    final blocked = (wallet['blocked_balance'] ?? '0').toString();

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        color: AppPalette.primary,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _HeroHeader(
              session: session,
              balance: balance,
              blockedBalance: blocked,
              loading: _loading,
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
              sliver: SliverList.list(
                children: [
                  _KpiRow(
                    loading: _loading,
                    orders: _orders,
                    products: _products,
                    role: session.role,
                  ),
                  const SizedBox(height: 24),
                  _QuickActions(session: session),
                  const SizedBox(height: 24),
                  if (_orders.isNotEmpty) _RecentOrders(orders: _orders),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({
    required this.session,
    required this.balance,
    required this.blockedBalance,
    required this.loading,
  });

  final SessionStore session;
  final String balance;
  final String blockedBalance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final greeting = _greeting();
    final roleLabel = _roleLabel(session.role);

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
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            greeting,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontSize: 13,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _RoleBadge(label: roleLabel),
                  ],
                ),
                const SizedBox(height: 20),
                _BalanceCard(
                  balance: balance,
                  blocked: blockedBalance,
                  loading: loading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.balance,
    required this.blocked,
    required this.loading,
  });

  final String balance;
  final String blocked;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solde disponible',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                loading
                    ? Container(
                        width: 130,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : Text(
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
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Bloqué escrow',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$blocked FCFA',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
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

// ─── KPI Row ─────────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({
    required this.loading,
    required this.orders,
    required this.products,
    required this.role,
  });

  final bool loading;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> products;
  final UserRole role;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        children: List.generate(
          3,
          (_) => Expanded(
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppPalette.borderSoft),
              ),
            ),
          ),
        ),
      );
    }

    final confirmed =
        orders.where((o) => o['status'] == 'CONFIRMED').length;
    final pending =
        orders.where((o) => o['status'] == 'PENDING').length;
    final active =
        products.where((p) => p['is_active'] == true).length;

    final kpis = <_KpiData>[];
    if (role == UserRole.supplier || role == UserRole.wholesaler) {
      kpis.addAll([
        _KpiData('Confirmées', '$confirmed', Icons.check_circle_rounded,
            AppPalette.success),
        _KpiData('En attente', '$pending', Icons.hourglass_top_rounded,
            AppPalette.warning),
        _KpiData('Produits actifs', '$active', Icons.inventory_2_rounded,
            AppPalette.secondary),
      ]);
    } else if (role == UserRole.transitAgent) {
      kpis.addAll([
        _KpiData('Total', '${orders.length}', Icons.local_shipping_rounded,
            AppPalette.primary),
        _KpiData('En attente', '$pending', Icons.hourglass_top_rounded,
            AppPalette.warning),
        _KpiData('Confirmées', '$confirmed', Icons.check_circle_rounded,
            AppPalette.success),
      ]);
    } else {
      kpis.addAll([
        _KpiData('Total', '${orders.length}', Icons.shopping_bag_rounded,
            AppPalette.primary),
        _KpiData('Confirmées', '$confirmed', Icons.check_circle_rounded,
            AppPalette.success),
        _KpiData('En attente', '$pending', Icons.hourglass_top_rounded,
            AppPalette.warning),
      ]);
    }

    return Row(
      children: kpis
          .map((k) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _KpiCard(data: k),
                ),
              ))
          .toList(),
    );
  }
}

class _KpiData {
  const _KpiData(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.data});
  final _KpiData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Icon(data.icon, color: data.color, size: 17),
          ),
          const SizedBox(height: 8),
          Text(
            data.value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppPalette.text,
            ),
          ),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppPalette.textMuted,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.session});
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    final actions = _actionsForRole(context, session.role);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions rapides',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppPalette.text,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: actions
              .map((a) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _ActionButton(data: a),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  List<_ActionData> _actionsForRole(BuildContext context, UserRole role) {
    switch (role) {
      case UserRole.supplier:
        return [
          _ActionData(
            'Produits',
            Icons.inventory_2_rounded,
            AppPalette.secondary,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const SupplierProductsPage()),
            ),
          ),
          _ActionData(
            'Commandes',
            Icons.shopping_bag_rounded,
            AppPalette.primary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrdersPage())),
          ),
          _ActionData(
            'Ventes',
            Icons.bar_chart_rounded,
            AppPalette.success,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SalesSummaryPage())),
          ),
          _ActionData(
            'Vidéo',
            Icons.video_camera_back_rounded,
            AppPalette.accentWarm,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const VideoPublishPage())),
          ),
        ];
      case UserRole.wholesaler:
        return [
          _ActionData(
            'Commandes',
            Icons.shopping_bag_rounded,
            AppPalette.primary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrdersPage())),
          ),
          _ActionData(
            'Appels d\'offre',
            Icons.request_quote_rounded,
            AppPalette.secondary,
            () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RfqsPage())),
          ),
          _ActionData(
            'Offres RFQ',
            Icons.local_offer_rounded,
            AppPalette.accent,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RfqOffersPage())),
          ),
          _ActionData(
            'Ventes',
            Icons.bar_chart_rounded,
            AppPalette.success,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SalesSummaryPage())),
          ),
        ];
      case UserRole.transitAgent:
        return [
          _ActionData(
            'Litiges',
            Icons.gavel_rounded,
            AppPalette.danger,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ShipmentDisputesPage())),
          ),
          _ActionData(
            'Transport',
            Icons.directions_car_rounded,
            AppPalette.secondary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TransportProfilePage())),
          ),
          _ActionData(
            'Commandes',
            Icons.shopping_bag_rounded,
            AppPalette.primary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrdersPage())),
          ),
        ];
      default:
        return [
          _ActionData(
            'Commandes',
            Icons.shopping_bag_rounded,
            AppPalette.primary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const OrdersPage())),
          ),
          _ActionData(
            'Ventes',
            Icons.bar_chart_rounded,
            AppPalette.success,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SalesSummaryPage())),
          ),
          _ActionData(
            'Offres RFQ',
            Icons.request_quote_rounded,
            AppPalette.secondary,
            () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RfqOffersPage())),
          ),
        ];
    }
  }
}

class _ActionData {
  const _ActionData(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.data});
  final _ActionData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(data.icon, color: data.color, size: 21),
              ),
              const SizedBox(height: 8),
              Text(
                data.label,
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
      ),
    );
  }
}

// ─── Recent Orders ────────────────────────────────────────────────────────────

class _RecentOrders extends StatelessWidget {
  const _RecentOrders({required this.orders});
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Commandes récentes',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.text,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersPage()),
              ),
              child: const Text('Voir tout'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...orders.take(5).map((o) => _OrderCard(order: o)),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});
  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final status = (order['status'] ?? 'PENDING').toString().toUpperCase();
    final ref = (order['reference'] ?? '${order['id'] ?? ''}').toString();
    final amount =
        (order['total_amount'] ?? order['total'] ?? '').toString();

    final Color statusColor;
    final String statusLabel;
    switch (status) {
      case 'CONFIRMED':
        statusColor = AppPalette.success;
        statusLabel = 'Confirmée';
      case 'PENDING':
        statusColor = AppPalette.warning;
        statusLabel = 'En attente';
      case 'CANCELLED':
        statusColor = AppPalette.danger;
        statusLabel = 'Annulée';
      default:
        statusColor = AppPalette.textMuted;
        statusLabel = status;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.shopping_bag_outlined,
                color: AppPalette.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ref.isNotEmpty ? 'Commande #$ref' : 'Commande',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                if (amount.isNotEmpty)
                  Text(
                    '$amount FCFA',
                    style: const TextStyle(
                        color: AppPalette.textMuted, fontSize: 12.5),
                  ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: statusColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
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
      appBar: AppBar(
        title: Text('Fournisseur - ${session.username ?? "Utilisateur"}'),
        actions: [
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          _RoleMenu(session: session),
        ],
      ),
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

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Produits actifs',
                      value: '$activeProducts',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiCard(
                      title: 'Commandes confirmees',
                      value: '$confirmedOrders',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiCard(
                      title: 'Offres RFQ',
                      value: '${payload.offers.length}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _KpiCard(
                      title: 'Wallet',
                      value: '${wallet['balance'] ?? '0'} FCFA',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _KpiCard(
                      title: 'Blocage escrow',
                      value: '${wallet['blocked_balance'] ?? '0'} FCFA',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _WindowCard(
                title: 'Ecrans dedies fournisseur',
                icon: Icons.apps_outlined,
                body: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: const Text("Produits / publication d'articles"),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const SupplierProductsPage()),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: const Text('Commandes passees'),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrdersPage()),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.bar_chart_outlined),
                      title: const Text('Montants des ventes'),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SalesSummaryPage(),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.request_quote_outlined),
                      title: const Text('Offres RFQ'),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RfqOffersPage()),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smart_display_outlined),
                      title: const Text('Publication video'),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const VideoPublishPage()),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Certifications'),
                      subtitle: const Text('Ecran separe'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ComplianceDocumentsPage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Synthese',
                icon: Icons.query_stats_outlined,
                body: _SimpleList(
                  items: [
                    _SimpleItem(
                      title: 'Documents en attente',
                      subtitle: '$pendingCompliance',
                    ),
                    _SimpleItem(
                      title: 'RFQ ouverts',
                      subtitle:
                          "${payload.rfqs.where((rfq) => '${rfq['status']}' == 'OPEN').length}",
                    ),
                  ],
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

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.session});
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.verified_user_outlined, size: 16),
      label: Text(session.role.name),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value});
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.title, required this.icon, this.body});
  final String title;
  final IconData icon;
  final Widget? body;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 10),
            body!,
          ],
        ],
      ),
    );
  }
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({required this.items});
  final List<_SimpleItem> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Aucune donnee.');
    }
    return Column(
      children: items
          .map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.subtitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
    );
  }
}

class _SimpleItem {
  const _SimpleItem({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

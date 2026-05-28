import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import 'supplier_order_detail_page.dart';

/// Commandes reçues vendeur (PDF 17).
class SupplierOrdersReceivedPage extends StatefulWidget {
  const SupplierOrdersReceivedPage({super.key});

  @override
  State<SupplierOrdersReceivedPage> createState() =>
      _SupplierOrdersReceivedPageState();
}

class _SupplierOrdersReceivedPageState
    extends State<SupplierOrdersReceivedPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _orders = const [];
  bool _loading = true;
  int _tab = 0; // 0 Nouvelles · 1 Préparer · 2 Expédiées

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      _orders = await _api.getList("/api/orders/?role=seller", token: token);
    } catch (_) {
      _orders = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _filtered() {
    String tabStatus;
    switch (_tab) {
      case 0:
        tabStatus = "PENDING";
        break;
      case 1:
        tabStatus = "CONFIRMED";
        break;
      default:
        tabStatus = "SHIPPED";
    }
    return _orders
        .where((o) =>
            (o["status"] ?? "").toString().toUpperCase() == tabStatus)
        .toList();
  }

  int _countByStatus(String status) => _orders
      .where((o) => (o["status"] ?? "").toString().toUpperCase() == status)
      .length;

  Future<void> _accept(Map<String, dynamic> order) async {
    final token = context.read<SessionStore>().token;
    final id = order["id"];
    try {
      await _api.post("/api/orders/$id/confirm/", const {}, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Commande acceptée.")),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Acceptation impossible."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => Navigator.maybePop(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  _TabChip(
                      label: "Nouvelles",
                      count: _countByStatus("PENDING"),
                      selected: _tab == 0,
                      onTap: () => setState(() => _tab = 0)),
                  const SizedBox(width: 8),
                  _TabChip(
                      label: "Préparer",
                      count: _countByStatus("CONFIRMED"),
                      selected: _tab == 1,
                      onTap: () => setState(() => _tab = 1)),
                  const SizedBox(width: 8),
                  _TabChip(
                      label: "Expédiées",
                      count: _countByStatus("SHIPPED"),
                      selected: _tab == 2,
                      onTap: () => setState(() => _tab = 2)),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? _Empty(
                          label: _tab == 0
                              ? "Pas de nouvelles commandes."
                              : _tab == 1
                                  ? "Aucune commande à préparer."
                                  : "Aucune commande expédiée.",
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 24),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _OrderCard(
                              order: filtered[i],
                              onAccept: () => _accept(filtered[i]),
                              onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SupplierOrderDetailPage(
                                      order: filtered[i]),
                                ),
                              ),
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Row(
        children: [
          IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Commandes",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                Text("Reçues · à traiter",
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip(
      {required this.label,
      required this.count,
      required this.selected,
      required this.onTap});
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppPalette.primary : AppPalette.card,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
                color:
                    selected ? AppPalette.primary : AppPalette.borderSoft),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppPalette.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  "$count",
                  style: TextStyle(
                    color: selected ? Colors.white : AppPalette.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard(
      {required this.order, required this.onAccept, required this.onOpen});
  final Map<String, dynamic> order;
  final VoidCallback onAccept;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final id = order["id"]?.toString() ?? "—";
    final buyer =
        (order["buyer_name"] ?? order["buyer"] ?? "Acheteur").toString();
    final productTitle =
        (order["product_title"] ?? order["product"] ?? "Produit").toString();
    final qty = order["quantity"]?.toString() ?? "—";
    final total =
        (order["payable_total"] ?? order["total_price"] ?? "—").toString();
    final urgent = (order["is_urgent"] ?? false) == true ||
        (order["priority"] ?? "").toString().toUpperCase() == "URGENT";
    final city = (order["delivery_city"] ?? "—").toString();
    final status = (order["status"] ?? "").toString().toUpperCase();

    final initials = () {
      final src = buyer.trim();
      if (src.isEmpty) return "·";
      final parts = src.split(RegExp(r"\s+"));
      if (parts.length == 1) {
        return parts.first
            .substring(0, parts.first.length.clamp(0, 2))
            .toUpperCase();
      }
      return (parts[0].isNotEmpty ? parts[0][0] : "") +
          (parts[1].isNotEmpty ? parts[1][0] : "");
    }();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppPalette.gradientPrimary,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Text(
                      initials,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                buyer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppPalette.text),
                              ),
                            ),
                            if (urgent) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppPalette.dangerSoft,
                                  borderRadius: BorderRadius.circular(
                                      AppRadii.pill),
                                ),
                                child: const Text("URGENT",
                                    style: TextStyle(
                                        color: AppPalette.danger,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "$city · #$id",
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppPalette.textMuted,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Text("$total F",
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.primaryDark,
                          letterSpacing: -0.3)),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 14, color: AppPalette.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "$productTitle · ${qty} unités",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.text),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 12, color: AppPalette.primaryDark),
                        SizedBox(width: 4),
                        Text("Séquestré",
                            style: TextStyle(
                                fontSize: 11,
                                color: AppPalette.primaryDark,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (status == "PENDING")
                    FilledButton.icon(
                      onPressed: onAccept,
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text("Accepter"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                      ),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.arrow_forward, size: 16),
                      label: const Text("Détails"),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_outlined,
                  color: AppPalette.primaryDark, size: 32),
            ),
            const SizedBox(height: 14),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textMuted)),
          ],
        ),
      ),
    );
  }
}

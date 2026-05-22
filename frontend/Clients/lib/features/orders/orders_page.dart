import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _shipments = const [];
  List<Map<String, dynamic>> _quotes = const [];
  List<String> _orderTimelineSteps = const [];
  int _defaultTransitRatingScore = 0;
  bool _loading = true;
  int _selectedTab = 0; // 0=En cours, 1=Livrées, 2=Litiges

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final isOrders =
          RealtimeEventsService.instance.matchesTopic(event, "orders");
      final isLogistics =
          RealtimeEventsService.instance.matchesTopic(event, "logistics");
      if (isOrders || isLogistics) _load();
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _orderTimelineSteps = BackendUiConfigService.instance
            .readStringList(config, ["choices", "order_timeline_steps"]);
        _defaultTransitRatingScore = BackendUiConfigService.instance
            .readInt(config, ["defaults", "transit_rating_score"]);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList("/api/orders/", token: token),
        _api.getList("/api/shipments/", token: token),
        _api.getList("/api/transport-quotes/", token: token),
      ]);
      setState(() {
        _orders = results[0];
        _shipments = results[1];
        _quotes = results[2];
      });
    } catch (_) {
      setState(() {
        _orders = const [];
        _shipments = const [];
        _quotes = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDelivery(int orderId) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/orders/$orderId/confirm_delivery/", {},
          token: token);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Livraison confirmée.")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Action non disponible.")));
    }
  }

  Map<String, dynamic>? _shipmentForOrder(int orderId) {
    for (final shipment in _shipments) {
      if (shipment["order"] == orderId) return shipment;
    }
    return null;
  }

  List<Map<String, dynamic>> _pendingQuotesForShipment(int shipmentId) {
    return _quotes
        .where((q) =>
            q["shipment"] == shipmentId &&
            (q["status"] ?? "").toString().toUpperCase() == "PENDING")
        .toList();
  }

  Future<void> _acceptQuote(int shipmentId, int quoteId) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
          "/api/shipments/$shipmentId/accept_quote/", {"quote_id": quoteId},
          token: token);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Devis accepté.")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'accepter ce devis.")));
    }
  }

  Future<void> _validateDelivery(int shipmentId) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/shipments/$shipmentId/validate_delivery/", {},
          token: token);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Livraison validée.")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Validation livraison indisponible.")));
    }
  }

  Future<void> _rateTransitAgent(int shipmentId) async {
    final scoreController =
        TextEditingController(text: _defaultTransitRatingScore.toString());
    final reviewController = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Noter le transitaire"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: scoreController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Score (1-5)"),
            ),
            TextField(
              controller: reviewController,
              decoration: const InputDecoration(labelText: "Avis"),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Envoyer")),
        ],
      ),
    );
    if (send != true || !mounted) return;
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/shipments/$shipmentId/rate_transit_agent/",
        {
          "score": int.tryParse(scoreController.text.trim()) ?? 5,
          "review": reviewController.text.trim(),
        },
        token: token,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Note enregistrée.")));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Notation impossible.")));
    }
  }

  Future<void> _reviewOrder(int orderId) async {
    final ratingController = TextEditingController(text: "5");
    final commentController = TextEditingController();
    final submit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Avis vérifié"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ratingController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Note (1-5)"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: "Commentaire"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
    if (submit != true || !mounted) return;
    final rating = int.tryParse(ratingController.text.trim()) ?? 0;
    if (rating < 1 || rating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Note invalide (1 à 5).")),
      );
      return;
    }
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/orders/$orderId/review/",
        {
          "rating": rating,
          "comment": commentController.text.trim(),
        },
        token: token,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Avis enregistré.")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _api.toUserMessage(e, fallback: "Impossible d'envoyer l'avis."),
          ),
        ),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    if (_selectedTab == 0) {
      // En cours: tout sauf COMPLETED et CANCELLED
      return _orders.where((o) {
        final s = (o["status"] ?? "").toString().toUpperCase();
        return s != "COMPLETED" && s != "CANCELLED";
      }).toList();
    } else if (_selectedTab == 1) {
      // Livrées: COMPLETED ou DELIVERED
      return _orders.where((o) {
        final s = (o["status"] ?? "").toString().toUpperCase();
        return s == "COMPLETED" || s == "DELIVERED";
      }).toList();
    } else {
      // Litiges: CANCELLED
      return _orders.where((o) {
        final s = (o["status"] ?? "").toString().toUpperCase();
        return s == "CANCELLED";
      }).toList();
    }
  }

  int get _inProgressCount => _orders
      .where((o) {
        final s = (o["status"] ?? "").toString().toUpperCase();
        return s != "COMPLETED" && s != "CANCELLED";
      })
      .length;

  int get _deliveredCount => _orders
      .where((o) {
        final s = (o["status"] ?? "").toString().toUpperCase();
        return s == "COMPLETED" || s == "DELIVERED";
      })
      .length;

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionStore>().role;
    final isBuyer = role == UserRole.buyer;
    final isSeller = role == UserRole.supplier || role == UserRole.wholesaler;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        backgroundColor: AppPalette.bg,
        surfaceTintColor: Colors.transparent,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Commandes",
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
            Text(
              "Suivi et historique",
              style: TextStyle(fontSize: 12, color: Color(0xFF666666),
                  fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          // Tabs chips scrollable
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TabChip(
                    label: "En cours $_inProgressCount",
                    selected: _selectedTab == 0,
                    onTap: () => setState(() => _selectedTab = 0),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: "Livrées $_deliveredCount",
                    selected: _selectedTab == 1,
                    onTap: () => setState(() => _selectedTab = 1),
                  ),
                  const SizedBox(width: 8),
                  _TabChip(
                    label: "Litiges",
                    selected: _selectedTab == 2,
                    onTap: () => setState(() => _selectedTab = 2),
                  ),
                ],
              ),
            ),
          ),
          // Contenu
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filteredOrders.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 60),
                              Center(
                                child: Text(
                                  "Aucune commande dans cette catégorie.",
                                  style: TextStyle(color: Colors.black45),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _filteredOrders.length,
                            itemBuilder: (context, index) {
                              return _buildOrderCard(
                                _filteredOrders[index],
                                isBuyer: isBuyer,
                                isSeller: isSeller,
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(
    Map<String, dynamic> order, {
    required bool isBuyer,
    required bool isSeller,
  }) {
    final orderId = order["id"] as int? ?? 0;
    final status = (order["status"] ?? "").toString();
    final statusUpper = status.toUpperCase();
    final amount =
        "${order["payable_total"] ?? order["total_price"]} FCFA";
    final shipment = _shipmentForOrder(orderId);
    final shipmentId = shipment?["id"] as int?;
    final pendingQuotes = shipmentId == null
        ? const <Map<String, dynamic>>[]
        : _pendingQuotesForShipment(shipmentId);

    // Couleur du badge statut
    Color badgeColor;
    if (statusUpper == "CONFIRMED" || statusUpper == "SHIPPED") {
      badgeColor = const Color(0xFFF5B400);
    } else if (statusUpper == "COMPLETED" || statusUpper == "DELIVERED") {
      badgeColor = AppPalette.success;
    } else if (statusUpper == "CANCELLED") {
      badgeColor = AppPalette.danger;
    } else {
      badgeColor = const Color(0xFF94A3B8);
    }

    String badgeLabel;
    if (statusUpper == "CONFIRMED") {
      badgeLabel = "En transit";
    } else if (statusUpper == "COMPLETED") {
      badgeLabel = "Livré";
    } else if (statusUpper == "CANCELLED") {
      badgeLabel = "Litige";
    } else {
      badgeLabel = status;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icône produit
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shopping_bag_outlined,
                    color: Color(0xFFF5B400), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "CMD #$orderId",
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      "Commande · ${shipment != null ? "Expédition #${shipment["id"]}" : "Pas d'expédition"}",
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                "Aujourd'hui",
                style: TextStyle(fontSize: 11, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Badge statut
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                amount,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF0F1F1A),
                ),
              ),
            ],
          ),
          // Actions
          if (isSeller && pendingQuotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: pendingQuotes.take(2).map((q) {
                return OutlinedButton(
                  onPressed: () =>
                      _acceptQuote(shipmentId!, q["id"] as int),
                  child: Text("Accepter devis #${q["id"]}"),
                );
              }).toList(),
            ),
          ],
          if (isBuyer &&
              shipmentId != null &&
              (shipment?["status"] ?? "").toString() != "DELIVERED") ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _validateDelivery(shipmentId),
              child: const Text("Valider livraison"),
            ),
          ],
          if (isBuyer &&
              shipmentId != null &&
              (shipment?["status"] ?? "").toString() == "DELIVERED") ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _rateTransitAgent(shipmentId),
              child: const Text("Noter le transitaire"),
            ),
          ],
          if (statusUpper == "COMPLETED" &&
              (order["has_review"] ?? false) != true) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _reviewOrder(orderId),
              child: const Text("Laisser un avis"),
            ),
          ],
          if (statusUpper != "COMPLETED") ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => _confirmDelivery(orderId),
              child: const Text("Valider réception"),
            ),
          ],
          // Timeline
          if (_orderTimelineSteps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OrderTimeline(
              status: status,
              steps: _orderTimelineSteps,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppPalette.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppPalette.primary : const Color(0xFFE5DECC),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppPalette.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF666666),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  const _OrderTimeline({required this.status, required this.steps});

  final String status;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();
    final currentIndex = steps.indexOf(status);
    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= currentIndex
                    ? AppPalette.primary
                    : const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (i < steps.length - 1) const SizedBox(width: 4),
        ]
      ],
    );
  }
}

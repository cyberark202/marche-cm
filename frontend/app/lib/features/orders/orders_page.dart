import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';
import 'sales_summary_page.dart';

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
      if (isOrders || isLogistics) {
        _load();
      }
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
      if (mounted) {
        setState(() => _loading = false);
      }
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
          .showSnackBar(const SnackBar(content: Text("Devis accepte.")));
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
          .showSnackBar(const SnackBar(content: Text("Livraison validee.")));
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
          .showSnackBar(const SnackBar(content: Text("Note enregistree.")));
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
        title: const Text("Avis verifie"),
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
        const SnackBar(content: Text("Note invalide (1 a 5).")),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Avis enregistre.")),
      );
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

  Color _orderStatusColor(String statusRaw) {
    final status = statusRaw.toUpperCase();
    if (status == "COMPLETED") return AppPalette.success;
    if (status == "CANCELLED") return AppPalette.danger;
    if (status == "DELIVERED") return AppPalette.secondary;
    if (status == "CONFIRMED") return AppPalette.primary;
    return AppPalette.warning;
  }

  @override
  Widget build(BuildContext context) {
    final username = context.watch<SessionStore>().username ?? "Utilisateur";
    final role = context.watch<SessionStore>().role;
    final isBuyer = role == UserRole.buyer;
    final isSeller = role == UserRole.supplier || role == UserRole.wholesaler;
    final completedCount = _orders
        .where((order) => (order["status"] ?? "").toString() == "COMPLETED")
        .length;
    final inProgressCount = _orders
        .where((order) => (order["status"] ?? "").toString() != "COMPLETED")
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text("Commandes passees"),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SalesSummaryPage()),
            ),
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: "Montants des ventes",
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AppPageBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              AppHeaderPanel(
                title: "Commandes de $username",
                subtitle:
                    "Consultez le statut de chaque commande et validez la reception.",
                trailing: const Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppMetricTile(
                      label: "Total",
                      value: "${_orders.length}",
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppMetricTile(
                      label: "En cours",
                      value: "$inProgressCount",
                      icon: Icons.local_shipping_outlined,
                      tint: AppPalette.warning,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppMetricTile(
                      label: "Finalisees",
                      value: "$completedCount",
                      icon: Icons.verified_outlined,
                      tint: AppPalette.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Column(
                  children: [
                    AppSkeletonCard(),
                    AppSkeletonCard(),
                    AppSkeletonCard(),
                  ],
                )
              else if (_orders.isEmpty)
                const _SectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text("Aucune commande"),
                    subtitle: Text("Vos commandes s'afficheront ici."),
                  ),
                )
              else
                ..._orders.map(
                  (order) => _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(builder: (_) {
                          final orderId = order["id"] as int? ?? 0;
                          final shipment = _shipmentForOrder(orderId);
                          final shipmentId = shipment?["id"] as int?;
                          final pendingQuotes = shipmentId == null
                              ? const <Map<String, dynamic>>[]
                              : _pendingQuotesForShipment(shipmentId);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (shipment != null)
                                Text(
                                  "Expedition #${shipment["id"]} | ${shipment["status"] ?? "-"}",
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              if (isSeller && pendingQuotes.isNotEmpty)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: pendingQuotes.take(2).map((q) {
                                    return OutlinedButton(
                                      onPressed: () => _acceptQuote(
                                        shipmentId!,
                                        q["id"] as int,
                                      ),
                                      child: Text("Accepter devis #${q["id"]}"),
                                    );
                                  }).toList(),
                                ),
                              if (isBuyer &&
                                  shipmentId != null &&
                                  (shipment?["status"] ?? "").toString() !=
                                      "DELIVERED")
                                TextButton(
                                  onPressed: () =>
                                      _validateDelivery(shipmentId),
                                  child:
                                      const Text("Valider livraison shipment"),
                                ),
                              if (isBuyer &&
                                  shipmentId != null &&
                                  (shipment?["status"] ?? "").toString() ==
                                      "DELIVERED")
                                TextButton(
                                  onPressed: () =>
                                      _rateTransitAgent(shipmentId),
                                  child: const Text("Noter le transitaire"),
                                ),
                              const SizedBox(height: 6),
                            ],
                          );
                        }),
                        Row(
                          children: [
                            Text(
                              "CMD-${order["id"]}",
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const Spacer(),
                            AppStatusBadge(
                              text: (order["status"] ?? "").toString(),
                              color: _orderStatusColor(
                                (order["status"] ?? "").toString(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${order["payable_total"] ?? order["total_price"]} FCFA",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (order["shipping_fee"] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              "Produit: ${order["total_price"]} FCFA | Transport: ${order["shipping_fee"]} FCFA",
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ),
                        const SizedBox(height: 6),
                        _OrderTimeline(
                          status: (order["status"] ?? "").toString(),
                          steps: _orderTimelineSteps,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text("Statut: ${order["status"]}"),
                            const Spacer(),
                            if ((order["status"] ?? "").toString() ==
                                    "COMPLETED" &&
                                (order["has_review"] ?? false) != true)
                              TextButton(
                                onPressed: () =>
                                    _reviewOrder(order["id"] as int),
                                child: const Text("Laisser avis"),
                              ),
                            if ((order["status"] ?? "").toString() !=
                                "COMPLETED")
                              TextButton(
                                onPressed: () =>
                                    _confirmDelivery(order["id"] as int),
                                child: const Text("Valider reception"),
                              )
                          ],
                        )
                      ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _OrderTimeline extends StatelessWidget {
  const _OrderTimeline({required this.status, required this.steps});
  final String status;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) {
      return const SizedBox.shrink();
    }
    final currentIndex = steps.indexOf(status);
    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= currentIndex
                    ? const Color(0xFF15803D)
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';

/// Suivi commande — timeline transitaire (PDF 10).
///
/// Affiche le statut, l'itinéraire, le produit, le transitaire et un stepper
/// vertical des étapes (commande → enlevée → en transit → preuve → libération).
class OrderTrackingPage extends StatefulWidget {
  const OrderTrackingPage({
    super.key,
    required this.order,
    this.shipment,
  });

  final Map<String, dynamic> order;
  final Map<String, dynamic>? shipment;

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  final ApiService _api = ApiService();
  late Map<String, dynamic> _order;
  Map<String, dynamic>? _shipment;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _shipment = widget.shipment;
    _refresh();
  }

  Future<void> _refresh() async {
    final token = context.read<SessionStore>().token;
    final id = _order["id"];
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final order = await _api.getObject("/api/orders/$id/", token: token);
      final shipments = await _api.getList(
          "/api/shipments/?order=$id", token: token);
      if (!mounted) return;
      setState(() {
        _order = order.isEmpty ? _order : order;
        _shipment = shipments.isEmpty ? _shipment : shipments.first;
      });
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _statusUpper =>
      (_order["status"] ?? "").toString().toUpperCase();

  String get _shipmentStatusUpper =>
      (_shipment?["status"] ?? "").toString().toUpperCase();

  Color get _statusTone {
    switch (_statusUpper) {
      case "COMPLETED":
      case "DELIVERED":
        return AppPalette.success;
      case "CANCELLED":
        return AppPalette.danger;
      case "PENDING":
        return AppPalette.warning;
      default:
        return AppPalette.primary;
    }
  }

  String get _statusLabel {
    switch (_statusUpper) {
      case "PENDING":
        return "EN PRÉPARATION";
      case "CONFIRMED":
        return "CONFIRMÉE";
      case "SHIPPED":
        return "EN TRANSIT";
      case "DELIVERED":
        return "LIVRÉE";
      case "COMPLETED":
        return "TERMINÉE";
      case "CANCELLED":
        return "ANNULÉE";
      default:
        return _statusUpper.isEmpty ? "EN COURS" : _statusUpper;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = _order["id"]?.toString() ?? "—";
    final shortRef = orderId.padLeft(7, '0').substring(0, 7);
    final totalAmount = _order["payable_total"] ?? _order["total_price"] ?? "—";
    final productTitle =
        (_order["product_title"] ?? _order["product"]?.toString() ?? "Produit")
            .toString();
    final sellerName = (_order["seller_name"] ??
            _order["seller"]?.toString() ??
            "Fournisseur")
        .toString();
    final qty = _order["quantity"]?.toString() ?? "—";
    final transitName = (_shipment?["transit_agent_name"] ??
            _shipment?["preferred_transit_agent"]?.toString() ??
            "—")
        .toString();
    final pickupCity =
        (_shipment?["pickup_city"] ?? _order["pickup_city"] ?? "Douala")
            .toString();
    final dropCity =
        (_shipment?["delivery_city"] ?? _order["delivery_city"] ?? "Yaoundé")
            .toString();
    final distanceKm = _shipment?["distance_km"]?.toString() ?? "—";
    final etaDate = _shipment?["estimated_delivery_date"]?.toString() ??
        _order["estimated_delivery_date"]?.toString();

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                statusLabel: _statusLabel,
                statusTone: _statusTone,
                orderRef: shortRef,
                pickup: pickupCity,
                drop: dropCity,
                distanceKm: distanceKm,
                etaDate: etaDate,
                onBack: () => Navigator.maybePop(context),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _ProductCard(
                      title: productTitle,
                      qty: qty,
                      sellerName: sellerName,
                      totalAmount: totalAmount.toString()),
                  const SizedBox(height: 12),
                  _TransitCard(
                    name: transitName,
                    eta: etaDate,
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel(label: "ÉTAPES DE LA COMMANDE"),
                  const SizedBox(height: 10),
                  _TimelineList(
                    statusUpper: _statusUpper,
                    shipmentStatus: _shipmentStatusUpper,
                    order: _order,
                    shipment: _shipment,
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.statusLabel,
    required this.statusTone,
    required this.orderRef,
    required this.pickup,
    required this.drop,
    required this.distanceKm,
    required this.etaDate,
    required this.onBack,
  });

  final String statusLabel;
  final Color statusTone;
  final String orderRef;
  final String pickup;
  final String drop;
  final String distanceKm;
  final String? etaDate;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  "Suivi commande",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.28)),
                ),
                child: Text(
                  "#$orderRef",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusTone.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(color: statusTone.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusTone,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (etaDate != null && etaDate!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.event_available_outlined,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    "Arrivée estimée — ${etaDate!}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 8),
            child: _RouteCard(
                pickup: pickup, drop: drop, distanceKm: distanceKm),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard(
      {required this.pickup, required this.drop, required this.distanceKm});
  final String pickup;
  final String drop;
  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(
              height: 1.4,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          const Icon(Icons.local_shipping_outlined,
              color: Colors.white, size: 16),
          Expanded(
            child: Container(
              height: 1.4,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.6),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$pickup → $drop",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
              if (distanceKm != "—")
                Text(
                  "≈ $distanceKm km",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.title,
    required this.qty,
    required this.sellerName,
    required this.totalAmount,
  });
  final String title;
  final String qty;
  final String sellerName;
  final String totalAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                color: AppPalette.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "$title · $qty",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppPalette.text,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.verified,
                        size: 13, color: AppPalette.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        "$sellerName · KYC validé",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "MONTANT",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                "$totalAmount F",
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primaryDark,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransitCard extends StatelessWidget {
  const _TransitCard({required this.name, required this.eta});
  final String name;
  final String? eta;

  @override
  Widget build(BuildContext context) {
    final initials = () {
      final src = name.trim();
      if (src.isEmpty || src == "—") return "TR";
      final parts = src.split(RegExp(r"\s+"));
      if (parts.length == 1) {
        return parts.first
            .substring(0, parts.first.length.clamp(0, 2))
            .toUpperCase();
      }
      return (parts[0].isNotEmpty ? parts[0][0] : "") +
          (parts[1].isNotEmpty ? parts[1][0] : "");
    }();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppPalette.gradientOcean,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: AppPalette.shadowSoft,
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TRANSITAIRE",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.textMuted,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.text,
                  ),
                ),
                if (eta != null && eta!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    "ETA : $eta",
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppPalette.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Discussion transitaire à venir.")),
              );
            },
            icon: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  color: AppPalette.primaryDark, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppPalette.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STEPPER VERTICAL
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineList extends StatelessWidget {
  const _TimelineList({
    required this.statusUpper,
    required this.shipmentStatus,
    required this.order,
    required this.shipment,
  });

  final String statusUpper;
  final String shipmentStatus;
  final Map<String, dynamic> order;
  final Map<String, dynamic>? shipment;

  int _currentIndex() {
    if (statusUpper == "COMPLETED" || statusUpper == "DELIVERED") return 5;
    if (shipmentStatus == "DELIVERED") return 4;
    if (shipmentStatus == "IN_TRANSIT" || statusUpper == "SHIPPED") return 3;
    if (shipmentStatus == "PICKED_UP") return 2;
    if (statusUpper == "CONFIRMED") return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final steps = <_TimelineStep>[
      _TimelineStep(
        title: "Commande passée",
        subtitle:
            "Créée le ${order["created_at"]?.toString().split('T').first ?? "—"} · "
            "${(order["payable_total"] ?? order["total_price"] ?? "—")} FCFA séquestrés",
        icon: Icons.shopping_bag_outlined,
      ),
      _TimelineStep(
        title: "Devis transitaire accepté",
        subtitle: shipment?["accepted_quote_amount"] != null
            ? "${shipment!["accepted_quote_amount"]} FCFA"
            : "En attente d'acceptation",
        icon: Icons.assignment_turned_in_outlined,
      ),
      _TimelineStep(
        title: "Colis pris en charge",
        subtitle: shipment?["pickup_at"]?.toString() ??
            "En attente d'enlèvement",
        icon: Icons.inventory_outlined,
      ),
      _TimelineStep(
        title: "En route vers la destination",
        subtitle: shipment?["current_position"]?.toString() ??
            (shipment?["delivery_city"]?.toString() ?? "Trajet en cours"),
        icon: Icons.local_shipping_outlined,
      ),
      _TimelineStep(
        title: "Preuve de livraison",
        subtitle: "Photo + code 4 chiffres à valider",
        icon: Icons.photo_camera_outlined,
      ),
      _TimelineStep(
        title: "Libération séquestre",
        subtitle: "Fonds débloqués pour le vendeur et le transitaire",
        icon: Icons.lock_open_outlined,
      ),
    ];

    final current = _currentIndex();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _TimelineRow(
              step: steps[i],
              done: i < current,
              active: i == current,
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _TimelineStep {
  const _TimelineStep({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final IconData icon;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.step,
    required this.done,
    required this.active,
    required this.isLast,
  });

  final _TimelineStep step;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppPalette.primary
        : active
            ? AppPalette.primary
            : AppPalette.border;
    final fill = done
        ? AppPalette.primary
        : active
            ? Colors.white
            : Colors.white;
    final ringColor = active
        ? AppPalette.primary
        : done
            ? AppPalette.primary
            : AppPalette.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 12)
                    : active
                        ? Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppPalette.primary,
                              shape: BoxShape.circle,
                            ),
                          )
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: done ? AppPalette.primary : AppPalette.borderSoft,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(step.icon, size: 14, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          step.title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: done || active
                                ? AppPalette.text
                                : AppPalette.textMuted,
                          ),
                        ),
                      ),
                      if (active)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppPalette.primarySoft,
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                          ),
                          child: const Text(
                            "EN COURS",
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.primaryDark,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    step.subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: done || active
                          ? AppPalette.textMuted
                          : AppPalette.textFaint,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';

/// Détail commande vendeur — stepper séquestre (PDF 18).
class SupplierOrderDetailPage extends StatefulWidget {
  const SupplierOrderDetailPage({super.key, required this.order});
  final Map<String, dynamic> order;

  @override
  State<SupplierOrderDetailPage> createState() =>
      _SupplierOrderDetailPageState();
}

class _SupplierOrderDetailPageState extends State<SupplierOrderDetailPage> {
  final ApiService _api = ApiService();
  late Map<String, dynamic> _order;
  Map<String, dynamic>? _shipment;
  bool _loading = false;

  static const double _supplierShare = 0.92;
  static const double _transitShare = 0.05;
  static const double _platformShare = 0.03;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
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

  Future<void> _confirm() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
          "/api/orders/${_order["id"]}/confirm/", const {}, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Commande acceptée.")),
      );
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Action impossible."))),
      );
    }
  }

  Future<void> _requestQuote() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
          "/api/orders/${_order["id"]}/request-quote/", const {},
          token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Demande de devis envoyée.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Demande devis impossible."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = _order["id"]?.toString() ?? "—";
    final statusUpper = (_order["status"] ?? "").toString().toUpperCase();
    final totalRaw = double.tryParse(
            "${_order["payable_total"] ?? _order["total_price"] ?? 0}") ??
        0;
    final supplierAmount = totalRaw * _supplierShare;
    final buyerName =
        (_order["buyer_name"] ?? _order["buyer"] ?? "Acheteur").toString();
    final buyerCity = (_order["delivery_city"] ?? "—").toString();
    final productTitle =
        (_order["product_title"] ?? "Produit").toString();
    final qty = _order["quantity"]?.toString() ?? "—";
    final unitPrice = (_order["unit_price"] ?? _order["price"]).toString();

    final initials = () {
      final src = buyerName.trim();
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

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Hero(
                  orderId: orderId,
                  onBack: () => Navigator.maybePop(context)),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _BuyerCard(
                      name: buyerName,
                      city: buyerCity,
                      initials: initials),
                  const SizedBox(height: 12),
                  _EscrowCard(
                      total: totalRaw,
                      supplierAmount: supplierAmount,
                      supplierShare: _supplierShare,
                      transitShare: _transitShare,
                      platformShare: _platformShare),
                  const SizedBox(height: 12),
                  _ProductLine(
                      title: productTitle,
                      qty: qty,
                      unitPrice: unitPrice),
                  const SizedBox(height: 20),
                  const _SectionLabel(label: "ACTIONS À FAIRE"),
                  const SizedBox(height: 10),
                  _ActionStepper(
                    statusUpper: statusUpper,
                    shipment: _shipment,
                    onConfirm: _confirm,
                    onRequestQuote: _requestQuote,
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.orderId, required this.onBack});
  final String orderId;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 22),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "CMD #$orderId",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3),
                ),
                const Text(
                  "Détail commande — vendeur",
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyerCard extends StatelessWidget {
  const _BuyerCard(
      {required this.name, required this.city, required this.initials});
  final String name;
  final String city;
  final String initials;
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
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppPalette.gradientPrimary,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Text(initials,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.text)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppPalette.primarySoft,
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified,
                              size: 10, color: AppPalette.primaryDark),
                          SizedBox(width: 2),
                          Text("KYC",
                              style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.primaryDark)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(city,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
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

class _EscrowCard extends StatelessWidget {
  const _EscrowCard({
    required this.total,
    required this.supplierAmount,
    required this.supplierShare,
    required this.transitShare,
    required this.platformShare,
  });
  final double total;
  final double supplierAmount;
  final double supplierShare;
  final double transitShare;
  final double platformShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        boxShadow: AppPalette.shadowMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.white, size: 14),
              SizedBox(width: 5),
              Text("SÉQUESTRE HELD",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${total.toStringAsFixed(0)} FCFA",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Vous recevrez ${supplierAmount.toStringAsFixed(0)} FCFA après libération (${(supplierShare * 100).round()} %)",
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _ShareTile(
                  label: "VOTRE PART",
                  pct: (supplierShare * 100).round(),
                  accent: Colors.white),
              const SizedBox(width: 8),
              _ShareTile(
                  label: "TRANSITAIRE",
                  pct: (transitShare * 100).round(),
                  accent: AppPalette.accent),
              const SizedBox(width: 8),
              _ShareTile(
                  label: "PLATEFORME",
                  pct: (platformShare * 100).round(),
                  accent: AppPalette.secondaryLight),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareTile extends StatelessWidget {
  const _ShareTile(
      {required this.label, required this.pct, required this.accent});
  final String label;
  final int pct;
  final Color accent;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text("$pct %",
                style: TextStyle(
                    color: accent,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ],
        ),
      ),
    );
  }
}

class _ProductLine extends StatelessWidget {
  const _ProductLine(
      {required this.title, required this.qty, required this.unitPrice});
  final String title;
  final String qty;
  final String unitPrice;

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
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.inventory_2_outlined,
                color: AppPalette.primaryDark, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$title · $qty",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.text)),
                const SizedBox(height: 2),
                Text(
                  unitPrice == "null" ? "—" : "$unitPrice FCFA · palier B2B",
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: AppPalette.textMuted,
                      fontWeight: FontWeight.w600),
                ),
              ],
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
    return Text(label,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppPalette.textMuted,
            letterSpacing: 1.2));
  }
}

class _ActionStepper extends StatelessWidget {
  const _ActionStepper({
    required this.statusUpper,
    required this.shipment,
    required this.onConfirm,
    required this.onRequestQuote,
  });
  final String statusUpper;
  final Map<String, dynamic>? shipment;
  final VoidCallback onConfirm;
  final VoidCallback onRequestQuote;

  int _currentIndex() {
    if (statusUpper == "DELIVERED" || statusUpper == "COMPLETED") return 4;
    if (statusUpper == "SHIPPED") return 3;
    if ((shipment?["status"] ?? "").toString() == "PICKED_UP") return 3;
    if (shipment?["accepted_quote_amount"] != null) return 2;
    if (statusUpper == "CONFIRMED") return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex();
    final steps = <_Step>[
      _Step(
        title: "Commande acceptée",
        subtitle: "Confirmer la commande pour l'acheteur",
        icon: Icons.thumb_up_alt_outlined,
        action: statusUpper == "PENDING"
            ? _StepAction(label: "Accepter", onTap: onConfirm)
            : null,
      ),
      _Step(
        title: "Demander un devis transitaire",
        subtitle: "Express Logistics répond en ~2 h",
        icon: Icons.local_shipping_outlined,
        action: statusUpper == "CONFIRMED" &&
                shipment?["accepted_quote_amount"] == null
            ? _StepAction(
                label: "Envoyer la demande", onTap: onRequestQuote)
            : null,
      ),
      const _Step(
        title: "Préparer la marchandise",
        subtitle: "Emballage et conformité de l'envoi",
        icon: Icons.inventory_outlined,
      ),
      const _Step(
        title: "Remettre au transitaire",
        subtitle: "Scanner le QR du transitaire à l'enlèvement",
        icon: Icons.qr_code_scanner,
      ),
      const _Step(
        title: "Libération séquestre",
        subtitle: "Fonds versés sur votre wallet",
        icon: Icons.lock_open_outlined,
      ),
    ];
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
            _StepRow(
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

class _Step {
  const _Step({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final _StepAction? action;
}

class _StepAction {
  const _StepAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.done,
    required this.active,
    required this.isLast,
  });
  final _Step step;
  final bool done;
  final bool active;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ringColor = active
        ? AppPalette.primary
        : done
            ? AppPalette.primary
            : AppPalette.border;
    final fillColor = done ? AppPalette.primary : Colors.white;
    final textColor =
        done || active ? AppPalette.text : AppPalette.textMuted;
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
                  color: fillColor,
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
                    color: done
                        ? AppPalette.primary
                        : AppPalette.borderSoft,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(step.icon, size: 14, color: ringColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(step.title,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(step.subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: done || active
                              ? AppPalette.textMuted
                              : AppPalette.textFaint,
                          height: 1.4)),
                  if (step.action != null && active) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: FilledButton.icon(
                        onPressed: step.action!.onTap,
                        icon: const Icon(Icons.bolt, size: 15),
                        label: Text(step.action!.label),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14),
                          textStyle: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

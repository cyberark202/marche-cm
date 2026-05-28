import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

/// RFQ entrantes vendeur (PDF 19).
class RfqOffersPage extends StatefulWidget {
  const RfqOffersPage({super.key});

  @override
  State<RfqOffersPage> createState() => _RfqOffersPageState();
}

class _RfqOffersPageState extends State<RfqOffersPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _rfqs = const [];
  List<Map<String, dynamic>> _offers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "analytics") ||
          RealtimeEventsService.instance.matchesTopic(event, "rfq")) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList("/api/rfqs/?open=1", token: token),
        _api.getList("/api/rfq-offers/", token: token),
      ]);
      _rfqs = results[0];
      _offers = results[1];
    } catch (_) {
      _rfqs = const [];
      _offers = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _respondedThisMonth {
    final now = DateTime.now();
    return _offers.where((o) {
      final created = DateTime.tryParse(
              (o["created_at"] ?? "").toString());
      return created != null &&
          created.year == now.year &&
          created.month == now.month;
    }).length;
  }

  Future<void> _sendOffer(Map<String, dynamic> rfq) async {
    final priceCtrl = TextEditingController();
    final etaCtrl = TextEditingController(text: "3");
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20,
            MediaQuery.of(context).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              "Envoyer une offre — RFQ #${rfq["id"]}",
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppPalette.text),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: "Prix unitaire (FCFA)",
                  prefixIcon: Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: etaCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: "Délai de livraison (jours)",
                  prefixIcon: Icon(Icons.schedule)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Annuler"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.send, size: 16),
                    label: const Text("Envoyer"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final price = double.tryParse(priceCtrl.text) ?? 0;
    final eta = int.tryParse(etaCtrl.text) ?? 3;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Prix invalide.")),
      );
      return;
    }
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/rfq-offers/",
        {"rfq": rfq["id"], "price": price, "lead_time_days": eta},
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offre envoyée.")),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Envoi impossible."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
                count: _rfqs.length,
                onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rfqs.isEmpty
                      ? const _Empty()
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding:
                                const EdgeInsets.fromLTRB(16, 16, 16, 24),
                            children: [
                              for (final rfq in _rfqs)
                                _RfqCard(
                                  rfq: rfq,
                                  onSend: () => _sendOffer(rfq),
                                ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppPalette.bgSoft,
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.md),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history,
                                        size: 14,
                                        color: AppPalette.textMuted),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        "$_respondedThisMonth RFQ déjà répondues ce mois",
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: AppPalette.textMuted),
                                      ),
                                    ),
                                    const Text(
                                      "Voir →",
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: AppPalette.primaryDark),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
  const _Header({required this.count, required this.onBack});
  final int count;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: onBack,
                  icon:
                      const Icon(Icons.arrow_back, color: Colors.white)),
              const Expanded(
                child: Text("Demandes de devis",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 4),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.request_quote_outlined,
                      color: Colors.white, size: 13),
                  const SizedBox(width: 5),
                  Text("$count RFQ à traiter",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RfqCard extends StatelessWidget {
  const _RfqCard({required this.rfq, required this.onSend});
  final Map<String, dynamic> rfq;
  final VoidCallback onSend;

  Color _urgencyColor(String urgency) {
    final u = urgency.toLowerCase();
    if (u.contains("24") || u.contains("urgent")) return AppPalette.danger;
    if (u.contains("48")) return AppPalette.warning;
    return AppPalette.info;
  }

  @override
  Widget build(BuildContext context) {
    final buyer = (rfq["buyer_name"] ?? "Acheteur").toString();
    final city = (rfq["delivery_city"] ?? "—").toString();
    final segment = (rfq["segment"] ?? "B2B").toString();
    final productLabel =
        (rfq["product_label"] ?? rfq["title"] ?? "Produit").toString();
    final qty = rfq["quantity"]?.toString() ?? "—";
    final urgency = (rfq["urgency"] ?? rfq["lead_time_days"]?.toString() ?? "48 h")
        .toString();
    final includesDelivery = (rfq["includes_delivery"] ?? true) == true;

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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                child: Text(initials,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(buyer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.text)),
                    const SizedBox(height: 2),
                    Text("$city · $segment",
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: AppPalette.textMuted,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _urgencyColor(urgency).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  urgency.length > 7 ? "URGENT" : urgency,
                  style: TextStyle(
                      color: _urgencyColor(urgency),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.bgSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("DEMANDE",
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.textMuted,
                        letterSpacing: 0.9)),
                const SizedBox(height: 4),
                Text(productLabel,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppPalette.text)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 13, color: AppPalette.textMuted),
                    const SizedBox(width: 4),
                    Text("$qty unités",
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.text)),
                    const SizedBox(width: 10),
                    if (includesDelivery) ...[
                      const Icon(Icons.local_shipping_outlined,
                          size: 13, color: AppPalette.textMuted),
                      const SizedBox(width: 4),
                      const Text("Livraison incluse",
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.textMuted)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Chat à venir.")),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text("Discuter"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: onSend,
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text("Envoyer offre"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.request_quote_outlined,
                  color: AppPalette.primaryDark, size: 36),
            ),
            const SizedBox(height: 14),
            const Text("Pas de RFQ en attente",
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.text)),
            const SizedBox(height: 4),
            const Text(
              "Les demandes d'acheteurs apparaissent ici.",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, color: AppPalette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

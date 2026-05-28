import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

/// Envoyer un devis — driver bid sur une mission (PDF 25).
class QuoteSendPage extends ConsumerStatefulWidget {
  const QuoteSendPage({super.key, required this.mission});
  final Map<String, dynamic> mission;

  @override
  ConsumerState<QuoteSendPage> createState() => _QuoteSendPageState();
}

class _QuoteSendPageState extends ConsumerState<QuoteSendPage> {
  final _price = TextEditingController();
  String _vehicle = "VAN";
  int _etaDays = 5;
  bool _insurance = true;
  bool _handling = false;
  bool _express = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _price.text = (widget.mission["suggested_fee"] ??
            widget.mission["delivery_fee"] ??
            "")
        .toString();
    _price.addListener(() => setState(() {}));
    final v = (widget.mission["vehicle_type"] ?? "").toString();
    if (v.isNotEmpty) _vehicle = v;
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final price = double.tryParse(_price.text) ?? 0;
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Indiquez un prix valide.")),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await DriverDioClient.dio.post(
        "/api/shipments/${widget.mission["id"]}/quote/",
        data: {
          "price": price,
          "vehicle_type": _vehicle,
          "lead_time_days": _etaDays,
          "with_insurance": _insurance,
          "with_handling": _handling,
          "express": _express,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Devis envoyé.")),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Envoi impossible : ${e.toString()}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final from = (m["pickup_city"] ?? "Départ").toString();
    final to = (m["delivery_city"] ?? "Arrivée").toString();
    final dist = m["distance_km"]?.toString() ?? "—";
    final weight = m["weight_kg"]?.toString() ?? "—";
    final cargo = (m["cargo_description"] ?? m["description"] ?? "").toString();
    final urgent = m["is_urgent"] == true;
    final bidsCount = m["bids_count"] ?? m["quotes_count"] ?? 0;
    final avgFee = m["average_fee"];
    final price = double.tryParse(_price.text) ?? 0;

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
                from: from,
                to: to,
                weight: weight,
                onBack: () => context.pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: urgent ? T.accentSoft : T.surface,
                      borderRadius: BorderRadius.circular(T.rLg),
                      border: Border.all(
                          color: urgent ? T.accent : T.line,
                          width: urgent ? 1.4 : 1),
                      boxShadow: T.shadowSm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (urgent) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: T.accent,
                                  borderRadius:
                                      BorderRadius.circular(T.rFull),
                                ),
                                child: const Text("URGENT · 6 h",
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1a0f00))),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: T.surface2,
                                borderRadius:
                                    BorderRadius.circular(T.rFull),
                              ),
                              child: Text("$bidsCount devis déjà soumis",
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: T.ink2)),
                            ),
                            const Spacer(),
                            Text("$dist km · $weight T",
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: T.ink2)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text("$from → $to",
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: T.ink)),
                        if (cargo.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(cargo,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  color: T.ink3,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: "VÉHICULE"),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _VehicleCard(
                              label: "Moto",
                              hint: "< 50 kg",
                              icon: Icons.two_wheeler,
                              code: "MOTO",
                              selected: _vehicle == "MOTO",
                              onTap: () =>
                                  setState(() => _vehicle = "MOTO"))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _VehicleCard(
                              label: "Hiace",
                              hint: "< 3 T",
                              icon: Icons.airport_shuttle,
                              code: "VAN",
                              selected: _vehicle == "VAN",
                              onTap: () =>
                                  setState(() => _vehicle = "VAN"))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _VehicleCard(
                              label: "Camion",
                              hint: "lourd",
                              icon: Icons.local_shipping,
                              code: "TRUCK",
                              selected: _vehicle == "TRUCK",
                              onTap: () =>
                                  setState(() => _vehicle = "TRUCK"))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: "VOTRE PRIX PROPOSÉ"),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(T.rLg),
                      border: Border.all(color: T.line),
                      boxShadow: T.shadowSm,
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _price,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  color: T.primaryDeep,
                                  letterSpacing: -1.0,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "0",
                                  hintStyle: TextStyle(
                                      color: T.ink4,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text("FCFA",
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: T.ink3)),
                            ),
                          ],
                        ),
                        if (avgFee != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: T.primarySoft,
                              borderRadius:
                                  BorderRadius.circular(T.rFull),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.show_chart,
                                    size: 13, color: T.primaryDark),
                                const SizedBox(width: 4),
                                Text(
                                  "Tarif moyen : $avgFee F · $bidsCount devis",
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: T.primaryDark),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: "DÉLAI DE LIVRAISON"),
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: T.surface,
                      borderRadius: BorderRadius.circular(T.rLg),
                      border: Border.all(color: T.line),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 18, color: T.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Slider(
                            value: _etaDays.toDouble(),
                            min: 1,
                            max: 15,
                            divisions: 14,
                            label: "$_etaDays j",
                            onChanged: (v) =>
                                setState(() => _etaDays = v.round()),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            "$_etaDays jours",
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: T.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: "OPTIONS"),
                  const SizedBox(height: 10),
                  _OptionTile(
                    title: "Assurance incluse",
                    subtitle: "Couvre la valeur marchandise",
                    icon: Icons.shield_outlined,
                    value: _insurance,
                    onChanged: (v) => setState(() => _insurance = v),
                  ),
                  _OptionTile(
                    title: "Manutention chargement",
                    subtitle: "Aide à la mise en charge",
                    icon: Icons.handshake_outlined,
                    value: _handling,
                    onChanged: (v) => setState(() => _handling = v),
                  ),
                  _OptionTile(
                    title: "Livraison express +50 %",
                    subtitle: "Garantie en 2 jours",
                    icon: Icons.bolt_outlined,
                    value: _express,
                    onChanged: (v) => setState(() => _express = v),
                  ),
                ],
              ),
            ),
            _Footer(
              busy: _busy,
              priceValue: price,
              onSend: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(
      {required this.from,
      required this.to,
      required this.weight,
      required this.onBack});
  final String from;
  final String to;
  final String weight;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 22),
      decoration: const BoxDecoration(
        gradient: T.gradientDriverHeader,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(T.rXl),
          bottomRight: Radius.circular(T.rXl),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back, color: Colors.white)),
              const Expanded(
                child: Text("Envoyer un devis",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 2),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(T.rFull),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    "$from → $to · $weight T",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800),
                  ),
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
            color: T.ink3,
            letterSpacing: 1.2));
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard({
    required this.label,
    required this.hint,
    required this.icon,
    required this.code,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String hint;
  final IconData icon;
  final String code;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(T.r),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? T.primary : T.surface,
          borderRadius: BorderRadius.circular(T.r),
          border: Border.all(
            color: selected ? T.primary : T.line,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? T.shadowSm : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: selected ? Colors.white : T.ink2),
            const SizedBox(height: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : T.ink,
                )),
            Text(hint,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.85)
                      : T.ink3,
                )),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.r),
        border: Border.all(color: value ? T.primary : T.line),
        boxShadow: T.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? T.primarySoft : T.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon,
                size: 16, color: value ? T.primary : T.ink3),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: T.ink)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 11.5,
                        color: T.ink3,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(
      {required this.busy,
      required this.priceValue,
      required this.onSend});
  final bool busy;
  final double priceValue;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: T.surface,
          boxShadow: T.shadowMd,
          border: const Border(
              top: BorderSide(color: T.line2, width: 1)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: busy ? null : onSend,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send, size: 18),
            label: Text(
              busy
                  ? "Envoi..."
                  : priceValue > 0
                      ? "Envoyer le devis · ${priceValue.toStringAsFixed(0)} F"
                      : "Envoyer le devis",
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: T.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';

enum _StatsRange { d7, d30, d90, m12 }

/// Statistiques vendeur — CA & top produits (PDF 21).
class SupplierStatsPage extends StatefulWidget {
  const SupplierStatsPage({super.key});

  @override
  State<SupplierStatsPage> createState() => _SupplierStatsPageState();
}

class _SupplierStatsPageState extends State<SupplierStatsPage> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _kpis = const {};
  List<Map<String, dynamic>> _series = const [];
  List<Map<String, dynamic>> _topProducts = const [];
  bool _loading = true;
  _StatsRange _range = _StatsRange.d30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _rangeKey() {
    switch (_range) {
      case _StatsRange.d7:
        return "7d";
      case _StatsRange.d30:
        return "30d";
      case _StatsRange.d90:
        return "90d";
      case _StatsRange.m12:
        return "12m";
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final kpis = await _api
          .getObject("/api/seller/stats/?range=${_rangeKey()}", token: token);
      _kpis = kpis;
      _series = (kpis["series"] as List?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          const [];
      _topProducts = (kpis["top_products"] as List?)
              ?.whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList() ??
          const [];
    } catch (_) {
      _kpis = const {};
      _series = const [];
      _topProducts = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ca = double.tryParse("${_kpis["total_revenue"] ?? 0}") ?? 0;
    final delta = double.tryParse("${_kpis["delta_pct"] ?? 0}") ?? 0;
    final orders =
        int.tryParse("${_kpis["orders_count"] ?? 0}") ?? 0;
    final buyers =
        int.tryParse("${_kpis["buyers_count"] ?? 0}") ?? 0;
    final newBuyers =
        int.tryParse("${_kpis["new_buyers_count"] ?? 0}") ?? 0;
    final rating = double.tryParse("${_kpis["avg_rating"] ?? 0}") ?? 0;
    final reviews = int.tryParse("${_kpis["reviews_count"] ?? 0}") ?? 0;
    final acceptance =
        double.tryParse("${_kpis["acceptance_rate"] ?? 0}") ?? 0;
    final onTime =
        double.tryParse("${_kpis["on_time_rate"] ?? 0}") ?? 0;
    final values = _series
        .map((e) =>
            double.tryParse("${e["revenue"] ?? e["value"] ?? 0}") ?? 0)
        .toList();

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _Header(onBack: () => Navigator.maybePop(context)),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(
                delegate: SliverChildListDelegate.fixed([
                  _RangeToggle(
                    range: _range,
                    onChanged: (r) {
                      setState(() => _range = r);
                      _load();
                    },
                  ),
                  const SizedBox(height: 14),
                  _CARevenueCard(amount: ca, deltaPct: delta),
                  const SizedBox(height: 12),
                  _ChartCard(values: values),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                          child: _KpiTile(
                              label: "COMMANDES",
                              value: "$orders",
                              sub: "ce mois",
                              icon: Icons.shopping_bag_outlined,
                              tone: _StatsTone.primary)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _KpiTile(
                              label: "ACHETEURS",
                              value: "$buyers",
                              sub: "dont $newBuyers nouveaux",
                              icon: Icons.group_outlined,
                              tone: _StatsTone.info)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _KpiTile(
                              label: "NOTE MOYENNE",
                              value: rating.toStringAsFixed(1),
                              sub: "$reviews avis",
                              icon: Icons.star_rounded,
                              tone: _StatsTone.accent)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _KpiTile(
                              label: "ON-TIME",
                              value: "${onTime.toStringAsFixed(0)} %",
                              sub:
                                  "${acceptance.toStringAsFixed(0)}% acceptation",
                              icon: Icons.timeline,
                              tone: _StatsTone.success)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: "PRODUITS PERFORMANTS"),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_topProducts.isEmpty)
                    const _EmptyTop()
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppPalette.card,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: AppPalette.borderSoft),
                        boxShadow: AppPalette.shadowSoft,
                      ),
                      child: Column(
                        children: [
                          for (var i = 0;
                              i < math.min(_topProducts.length, 5);
                              i++) ...[
                            if (i > 0)
                              const Divider(
                                  height: 1,
                                  color: AppPalette.borderSoft),
                            _ProductRow(
                                product: _topProducts[i], rank: i + 1),
                          ],
                        ],
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
                Text("Statistiques",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                Text("Performance vendeur",
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

class _RangeToggle extends StatelessWidget {
  const _RangeToggle({required this.range, required this.onChanged});
  final _StatsRange range;
  final ValueChanged<_StatsRange> onChanged;
  @override
  Widget build(BuildContext context) {
    final items = [
      (_StatsRange.d7, "7 j"),
      (_StatsRange.d30, "30 j"),
      (_StatsRange.d90, "90 j"),
      (_StatsRange.m12, "12 mois"),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppPalette.bgSoft,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(item.$1),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: range == item.$1
                        ? AppPalette.card
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    boxShadow: range == item.$1
                        ? AppPalette.shadowSoft
                        : null,
                  ),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: range == item.$1
                          ? AppPalette.primaryDark
                          : AppPalette.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CARevenueCard extends StatelessWidget {
  const _CARevenueCard(
      {required this.amount, required this.deltaPct});
  final double amount;
  final double deltaPct;
  @override
  Widget build(BuildContext context) {
    final positive = deltaPct >= 0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowMedium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("CHIFFRE D'AFFAIRES",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textMuted,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Text("${amount.toStringAsFixed(0)} FCFA",
              style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primaryDark,
                  letterSpacing: -1.0,
                  height: 1.1)),
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: positive
                  ? AppPalette.successSoft
                  : AppPalette.dangerSoft,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    positive
                        ? Icons.trending_up
                        : Icons.trending_down,
                    size: 13,
                    color: positive
                        ? AppPalette.success
                        : AppPalette.danger),
                const SizedBox(width: 4),
                Text(
                  "${positive ? '+' : ''}${deltaPct.toStringAsFixed(1)} % vs période précédente",
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: positive
                          ? AppPalette.success
                          : AppPalette.danger),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.values});
  final List<double> values;
  @override
  Widget build(BuildContext context) {
    final maxVal = values.isEmpty ? 1.0 : values.fold<double>(1, math.max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: SizedBox(
        height: 140,
        child: values.isEmpty
            ? const Center(
                child: Text("Pas de données pour cette période.",
                    style: TextStyle(
                        fontSize: 12.5, color: AppPalette.textMuted)),
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0;
                      i < math.min(values.length, 24);
                      i++)
                    Expanded(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 1.5),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 380),
                          height: math.max(
                              4, (values[i] / maxVal) * 120),
                          decoration: BoxDecoration(
                            gradient: AppPalette.gradientPrimary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
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

enum _StatsTone { primary, accent, info, success }

class _KpiTile extends StatelessWidget {
  const _KpiTile({
    required this.label,
    required this.value,
    required this.sub,
    required this.icon,
    required this.tone,
  });
  final String label;
  final String value;
  final String sub;
  final IconData icon;
  final _StatsTone tone;
  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (tone) {
      case _StatsTone.primary:
        bg = AppPalette.primarySoft;
        fg = AppPalette.primaryDark;
      case _StatsTone.accent:
        bg = AppPalette.accentSoft;
        fg = AppPalette.accentDark;
      case _StatsTone.info:
        bg = AppPalette.infoSoft;
        fg = AppPalette.info;
      case _StatsTone.success:
        bg = AppPalette.successSoft;
        fg = AppPalette.success;
    }
    return Container(
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
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: fg, size: 15),
              ),
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textMuted,
                      letterSpacing: 0.6)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.text,
                  letterSpacing: -0.5,
                  height: 1.1)),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(
                  fontSize: 11,
                  color: AppPalette.textMuted,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.rank});
  final Map<String, dynamic> product;
  final int rank;
  @override
  Widget build(BuildContext context) {
    final title = (product["title"] ?? "Produit").toString();
    final qty = product["sold_quantity"]?.toString() ??
        product["quantity"]?.toString() ??
        "—";
    final revenue =
        double.tryParse("${product["revenue"] ?? 0}") ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppPalette.gradientPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text("#$rank",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.text)),
                Text("$qty unités vendues",
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Text("${revenue.toStringAsFixed(0)} F",
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primaryDark)),
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

class _EmptyTop extends StatelessWidget {
  const _EmptyTop();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.bgSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Center(
        child: Text(
          "Pas encore de produits performants sur cette période.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: AppPalette.textMuted),
        ),
      ),
    );
  }
}

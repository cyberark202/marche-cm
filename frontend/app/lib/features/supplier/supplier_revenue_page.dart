import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../wallet/wallet_withdraw_page.dart';

/// Revenus vendeur — wallet & retraits (PDF 20).
class SupplierRevenuePage extends StatefulWidget {
  const SupplierRevenuePage({super.key});

  @override
  State<SupplierRevenuePage> createState() => _SupplierRevenuePageState();
}

class _SupplierRevenuePageState extends State<SupplierRevenuePage> {
  final ApiService _api = ApiService();
  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _transactions = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final wallets = await _api.getList("/api/wallets/", token: token);
      final txs =
          await _api.getList("/api/wallets/transactions/", token: token);
      _wallet = wallets.isEmpty ? const {} : wallets.first;
      _transactions = txs;
    } catch (_) {
      _wallet = const {};
      _transactions = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _balance(String key) =>
      double.tryParse("${_wallet[key] ?? 0}") ?? 0;

  List<double> _dailyRevenues() {
    final now = DateTime.now();
    final buckets = List<double>.filled(7, 0);
    for (final tx in _transactions) {
      final status = (tx["status"] ?? "").toString().toUpperCase();
      final kind = (tx["kind"] ?? "").toString().toUpperCase();
      if (status != "SUCCESS") continue;
      if (kind != "ORDER_RELEASE" && kind != "DEPOSIT") continue;
      final at = DateTime.tryParse((tx["created_at"] ?? "").toString());
      if (at == null) continue;
      final diff = now.difference(at).inDays;
      if (diff < 0 || diff >= 7) continue;
      buckets[6 - diff] +=
          (double.tryParse("${tx["amount"] ?? 0}") ?? 0).abs();
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final available = _balance("available_balance");
    final locked = _balance("locked_balance");
    final week = _dailyRevenues();
    final weekTotal = week.fold<double>(0, (a, b) => a + b);

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
                  _AvailableCard(
                    amount: available,
                    onWithdraw: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const WalletWithdrawPage()),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _StatCard(
                              label: "EN SÉQUESTRE",
                              value: locked.toStringAsFixed(0),
                              suffix: "FCFA",
                              sub:
                                  "${_transactions.where((t) => (t["status"] ?? "").toString().toUpperCase() == "HOLD").length} commandes",
                              tone: _StatTone.accent)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _StatCard(
                              label: "CETTE SEMAINE",
                              value: "+ ${weekTotal.toStringAsFixed(0)}",
                              suffix: "FCFA",
                              sub: "à libérer",
                              tone: _StatTone.primary)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel(label: "REVENUS · 7 DERNIERS JOURS"),
                  const SizedBox(height: 10),
                  _ChartCard(values: week),
                  const SizedBox(height: 20),
                  const _SectionLabel(label: "HISTORIQUE PAIEMENTS"),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_transactions.isEmpty)
                    const _Empty()
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
                              i < math.min(_transactions.length, 8);
                              i++) ...[
                            if (i > 0)
                              const Divider(
                                  height: 1,
                                  color: AppPalette.borderSoft),
                            _PaymentRow(tx: _transactions[i]),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Revenus",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                Text("Wallet vendeur",
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

class _AvailableCard extends StatelessWidget {
  const _AvailableCard({required this.amount, required this.onWithdraw});
  final double amount;
  final VoidCallback onWithdraw;
  @override
  Widget build(BuildContext context) {
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
          const Text("DISPONIBLE POUR RETRAIT",
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textMuted,
                  letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Text("${amount.toStringAsFixed(0)} FCFA",
              style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.0,
                  color: AppPalette.primaryDark,
                  height: 1.1)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onWithdraw,
              icon: const Icon(Icons.south, size: 18),
              label: const Text("Retirer"),
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatTone { primary, accent }

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.suffix,
    required this.sub,
    required this.tone,
  });
  final String label;
  final String value;
  final String suffix;
  final String sub;
  final _StatTone tone;
  @override
  Widget build(BuildContext context) {
    final accent = tone == _StatTone.accent
        ? AppPalette.accent
        : AppPalette.primaryDark;
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
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.textMuted,
                  letterSpacing: 1.0)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(value,
                    style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: accent,
                        letterSpacing: -0.5,
                        height: 1.1)),
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(suffix,
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textMuted)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(sub,
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AppPalette.textMuted,
                  fontWeight: FontWeight.w600)),
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
    const days = ["L", "M", "M", "J", "V", "S", "D"];
    final maxVal = values.fold<double>(1, math.max);
    final total = values.fold<double>(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 380),
                            height: math.max(
                                4, (values[i] / maxVal) * 100),
                            decoration: const BoxDecoration(
                              gradient: AppPalette.gradientPrimary,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(days[i],
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textMuted)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Total semaine",
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.textMuted,
                            letterSpacing: 0.8)),
                    Text("${total.toStringAsFixed(0)} FCFA",
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.primaryDark,
                            letterSpacing: -0.4)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.successSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.trending_up,
                        size: 12, color: AppPalette.success),
                    SizedBox(width: 3),
                    Text("+22 %",
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppPalette.success)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.tx});
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final kind = (tx["kind"] ?? "").toString().toUpperCase();
    final status = (tx["status"] ?? "").toString().toUpperCase();
    final amount =
        (double.tryParse("${tx["amount"] ?? 0}") ?? 0).abs();
    final isOut = kind.contains("WITHDRAW");
    final label = isOut
        ? "Retrait ${(tx["provider"] ?? "MoMo").toString()}"
        : "Revenu commande";
    final dt = (tx["created_at"] ?? "").toString().split("T").first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isOut
                  ? AppPalette.infoSoft
                  : AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              isOut ? Icons.north : Icons.south,
              size: 16,
              color: isOut
                  ? AppPalette.info
                  : AppPalette.primaryDark,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.text)),
                Text(dt,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${isOut ? '−' : '+'} ${amount.toStringAsFixed(0)} F",
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isOut ? AppPalette.danger : AppPalette.success),
              ),
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: status == "SUCCESS"
                      ? AppPalette.successSoft
                      : AppPalette.warningSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(status,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: status == "SUCCESS"
                            ? AppPalette.success
                            : AppPalette.warning,
                        letterSpacing: 0.6)),
              ),
            ],
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

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.bgSoft,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: const Center(
        child: Text("Aucun paiement enregistré.",
            style: TextStyle(
                fontSize: 12.5, color: AppPalette.textMuted)),
      ),
    );
  }
}

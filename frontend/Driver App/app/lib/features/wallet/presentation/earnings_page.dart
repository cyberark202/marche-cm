import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

// Audit ref: [Front-Driver] no /api/wallets/driver/earnings/ endpoint exists
// server-side. Earnings are now aggregated client-side from the wallet
// transactions feed (kind=DELIVERY_PAYOUT). A dedicated backend endpoint
// can be added later for performance.
final _earningsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get(
    '/api/wallets/transactions/',
    queryParameters: {'kind': 'DELIVERY_PAYOUT'},
  );
  final data = res.data;
  final List items = (data is Map && data['results'] is List)
      ? data['results'] as List
      : (data is List ? data : const []);

  num total = 0;
  num thisMonth = 0;
  final now = DateTime.now();
  for (final raw in items) {
    if (raw is! Map) continue;
    final amount = num.tryParse('${raw['amount'] ?? 0}') ?? 0;
    if ((raw['status'] ?? '') == 'FAILED') continue;
    total += amount.abs();
    final ts = raw['created_at'];
    if (ts is String) {
      final dt = DateTime.tryParse(ts);
      if (dt != null && dt.year == now.year && dt.month == now.month) {
        thisMonth += amount.abs();
      }
    }
  }
  return <String, dynamic>{
    'total': total,
    'month': thisMonth,
    'count': items.length,
    'transactions': items,
  };
});

class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(_earningsProvider);
    return Scaffold(
      backgroundColor: T.bg,
      body: earningsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: T.primary)),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: T.ink4),
            const SizedBox(height: 12),
            const Text('Erreur de chargement',
                style: TextStyle(color: T.ink3, fontSize: 14)),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => ref.invalidate(_earningsProvider),
              child: const Text('Réessayer'),
            ),
          ]),
        ),
        data: (data) {
          final total = (data['total_earned'] ?? 0).toString();
          final thisMonth = (data['this_month'] ?? 0).toString();
          final thisWeek = (data['this_week'] ?? 0).toString();
          final deliveries = data['total_deliveries'] ?? 0;
          final history = data['history'] is List
              ? (data['history'] as List).cast<Map<String, dynamic>>()
              : <Map<String, dynamic>>[];

          return CustomScrollView(
            slivers: [
              // ── Amber gradient hero ─────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: T.gradientDriverHeader,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Back + title
                          Row(children: [
                            GestureDetector(
                              onTap: () => context.pop(),
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.arrow_back,
                                    color: Colors.white, size: 20),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Text('Mes gains',
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ]),
                          const SizedBox(height: 20),
                          // Total ce mois
                          Text("Ce mois-ci",
                              style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Colors.white.withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.1)),
                          const SizedBox(height: 4),
                          Text(
                            '${_fmt(thisMonth)} FCFA',
                            style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -1),
                          ),
                          const SizedBox(height: 4),
                          Text('$deliveries livraisons complétées',
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      Colors.white.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Stats grid ──────────────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Total',
                        value: _fmt(total),
                        icon: Icons.emoji_events_outlined,
                        iconBg: T.accentSoft,
                        iconFg: T.accentDark,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatCard(
                        label: 'Cette semaine',
                        value: _fmt(thisWeek),
                        icon: Icons.date_range_outlined,
                        iconBg: T.primarySoft,
                        iconFg: T.primaryDark,
                      ),
                    ),
                  ]),
                ),
              ),

              // ── History header ──────────────────────────────────────────
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: Text('Historique',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: T.ink,
                          letterSpacing: -0.2)),
                ),
              ),

              // ── History list ────────────────────────────────────────────
              if (history.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('Aucun gain enregistré.',
                        style: TextStyle(color: T.ink3, fontSize: 14)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverList.separated(
                    itemCount: history.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) =>
                        _EarningTile(entry: history[i]),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _fmt(dynamic v) {
    final n = num.tryParse(v.toString()) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)} k';
    return n.toStringAsFixed(0);
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color iconBg, iconFg;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconFg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.r),
          border: Border.all(color: T.line),
          boxShadow: T.shadowSm,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: iconFg, size: 18),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: T.ink,
                  letterSpacing: -0.3)),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: T.ink3)),
        ]),
      );
}

class _EarningTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _EarningTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final amount = (entry['amount'] ?? 0).toString();
    final missionRef = entry['mission_reference'] ?? 'Livraison';
    final createdAt = entry['created_at'] as String?;
    String date = '';
    if (createdAt != null) {
      try {
        date = DateFormat('dd MMM · HH:mm')
            .format(DateTime.parse(createdAt).toLocal());
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.r),
        border: Border.all(color: T.line),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: T.primarySoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_downward,
              color: T.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(missionRef,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: T.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (date.isNotEmpty)
              Text(date,
                  style: const TextStyle(fontSize: 11, color: T.ink3)),
          ]),
        ),
        Text('+$amount FCFA',
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: T.success)),
      ]),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _earningsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/wallets/driver/earnings/');
  return res.data as Map<String, dynamic>;
});

class EarningsPage extends ConsumerWidget {
  const EarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(_earningsProvider);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Mes gains'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: earningsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: DriverPalette.textMuted),
            const SizedBox(height: 12),
            FilledButton.tonal(
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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats grid
                Row(children: [
                  Expanded(child: _StatCard(label: 'Total gagné', value: '$total FCFA',
                      icon: Icons.emoji_events_outlined, color: DriverPalette.secondary)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: 'Ce mois', value: '$thisMonth FCFA',
                      icon: Icons.calendar_month_outlined, color: DriverPalette.primary)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _StatCard(label: 'Cette semaine', value: '$thisWeek FCFA',
                      icon: Icons.date_range_outlined, color: const Color(0xFF6366F1))),
                  const SizedBox(width: 10),
                  Expanded(child: _StatCard(label: 'Livraisons', value: '$deliveries',
                      icon: Icons.local_shipping_outlined, color: const Color(0xFF10B981))),
                ]),
                const SizedBox(height: 24),
                const Text('Historique des gains',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: DriverPalette.textMuted, letterSpacing: 0.5)),
                const SizedBox(height: 10),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('Aucun gain enregistré.',
                          style: TextStyle(color: DriverPalette.textSecondary, fontSize: 14)),
                    ),
                  )
                else
                  ...history.map((e) => _EarningTile(entry: e)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(DriverRadii.md),
      border: Border.all(color: DriverPalette.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
          color: DriverPalette.textPrimary)),
      Text(label, style: const TextStyle(fontSize: 12, color: DriverPalette.textSecondary)),
    ]),
  );
}

class _EarningTile extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _EarningTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final amount = (entry['amount'] ?? 0).toString();
    final missionRef = entry['mission_reference'] ?? 'Mission';
    final createdAt = entry['created_at'] as String?;
    String date = '';
    if (createdAt != null) {
      try { date = DateFormat('dd MMM HH:mm').format(DateTime.parse(createdAt).toLocal()); } catch (_) {}
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DriverPalette.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_downward, color: Colors.green, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(missionRef, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: DriverPalette.textPrimary)),
            if (date.isNotEmpty)
              Text(date, style: const TextStyle(fontSize: 11, color: DriverPalette.textMuted)),
          ]),
        ),
        Text('+$amount FCFA',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.green)),
      ]),
    );
  }
}

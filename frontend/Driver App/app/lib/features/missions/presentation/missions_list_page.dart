import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _missionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/logistics/missions/available/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

class MissionsListPage extends ConsumerStatefulWidget {
  const MissionsListPage({super.key});

  @override
  ConsumerState<MissionsListPage> createState() => _MissionsListPageState();
}

class _MissionsListPageState extends ConsumerState<MissionsListPage> {
  String _filter = 'ALL';

  static const _filters = [
    ('ALL', 'Toutes'),
    ('MOTO', 'Moto'),
    ('CAR', 'Voiture'),
    ('VAN', 'Camionnette'),
    ('FOOT', 'À pied'),
  ];

  @override
  Widget build(BuildContext context) {
    final missionsAsync = ref.watch(_missionsProvider);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: DriverPalette.primary,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: const Text('Missions disponibles',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              background: Container(
                decoration: const BoxDecoration(gradient: DriverPalette.heroGradient),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => ref.invalidate(_missionsProvider),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _filters[i];
                  final sel = _filter == f.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? DriverPalette.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? DriverPalette.primary : DriverPalette.border),
                      ),
                      child: Text(f.$2,
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : DriverPalette.textSecondary)),
                    ),
                  );
                },
              ),
            ),
          ),
          missionsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, size: 48, color: DriverPalette.textMuted),
                  const SizedBox(height: 12),
                  Text('Erreur de chargement',
                      style: TextStyle(color: DriverPalette.textSecondary, fontSize: 14)),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    onPressed: () => ref.invalidate(_missionsProvider),
                    child: const Text('Réessayer'),
                  ),
                ]),
              ),
            ),
            data: (missions) {
              final filtered = _filter == 'ALL'
                  ? missions
                  : missions.where((m) => m['vehicle_type'] == _filter).toList();
              if (filtered.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.assignment_outlined, size: 56, color: DriverPalette.textMuted),
                      SizedBox(height: 12),
                      Text('Aucune mission disponible',
                          style: TextStyle(color: DriverPalette.textSecondary, fontSize: 15)),
                    ]),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                sliver: SliverList.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _MissionCard(
                    mission: filtered[i],
                    onTap: () => context.push('/missions/${filtered[i]['id']}'),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final VoidCallback onTap;
  const _MissionCard({required this.mission, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fee = (mission['delivery_fee'] ?? 0).toString();
    final dist = mission['distance_km'];
    final createdAt = mission['created_at'] as String?;
    String timeAgo = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeAgo = DateFormat('HH:mm').format(dt);
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(DriverRadii.md),
          boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: DriverPalette.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.local_shipping_outlined, color: DriverPalette.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mission['reference'] ?? 'Mission #${mission['id']}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                          color: DriverPalette.textPrimary)),
                  Text(mission['pickup_address'] ?? '',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: DriverPalette.textSecondary)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('$fee FCFA',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15,
                        color: DriverPalette.primary)),
                if (timeAgo.isNotEmpty)
                  Text(timeAgo, style: const TextStyle(fontSize: 11, color: DriverPalette.textMuted)),
              ]),
            ]),
            const Divider(height: 16),
            Row(children: [
              const Icon(Icons.place_outlined, size: 14, color: DriverPalette.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(mission['delivery_address'] ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: DriverPalette.textSecondary)),
              ),
              if (dist != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: DriverPalette.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${dist} km',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: DriverPalette.secondary)),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _missionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  // Audit ref: [Front-Driver] no /api/logistics/missions/available/ endpoint
  // exists. Backend exposes /api/shipments/ (router) — we filter to status
  // PENDING with no transit_agent assigned to surface assignable missions.
  final res = await DriverDioClient.dio.get(
    '/api/shipments/',
    queryParameters: {'status': 'PENDING', 'assignable': '1'},
  );
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
    ('VAN', 'Camion'),
    ('FOOT', 'À pied'),
  ];

  @override
  Widget build(BuildContext context) {
    final missionsAsync = ref.watch(_missionsProvider);
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Demandes',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: T.ink,
                                letterSpacing: -0.4)),
                        missionsAsync.maybeWhen(
                          data: (m) => Text('${m.length} disponibles',
                              style:
                                  const TextStyle(fontSize: 13, color: T.ink3)),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ]),
                ),
                _HeaderBtn(
                  icon: Icons.refresh,
                  onTap: () => ref.invalidate(_missionsProvider),
                ),
              ]),
            ),

            // ── Filter chips ───────────────────────────────────────────────
            SizedBox(
              height: 50,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final f = _filters[i];
                  final sel = _filter == f.$1;
                  return GestureDetector(
                    onTap: () => setState(() => _filter = f.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? T.ink : T.surface,
                        borderRadius: BorderRadius.circular(T.rFull),
                        border: Border.all(color: sel ? T.ink : T.line),
                      ),
                      child: Text(f.$2,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : T.ink3)),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1, color: T.line2),

            // ── List ───────────────────────────────────────────────────────
            Expanded(
              child: missionsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: T.primary)),
                error: (e, _) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_outlined,
                        size: 48, color: T.ink4),
                    const SizedBox(height: 12),
                    const Text('Erreur de chargement',
                        style: TextStyle(color: T.ink3, fontSize: 14)),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: () => ref.invalidate(_missionsProvider),
                      child: const Text('Réessayer'),
                    ),
                  ]),
                ),
                data: (missions) {
                  final filtered = _filter == 'ALL'
                      ? missions
                      : missions
                          .where((m) => m['vehicle_type'] == _filter)
                          .toList();
                  if (filtered.isEmpty) {
                    return const Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.balance_outlined, size: 56, color: T.ink4),
                        SizedBox(height: 12),
                        Text('Aucune demande disponible',
                            style: TextStyle(color: T.ink3, fontSize: 15)),
                      ]),
                    );
                  }
                  return RefreshIndicator(
                    color: T.primary,
                    onRefresh: () => ref.refresh(_missionsProvider.future),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _MissionCard(
                        mission: filtered[i],
                        onTap: () =>
                            context.push('/missions/${filtered[i]['id']}'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Local widgets ─────────────────────────────────────────────────────────────

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: T.line),
          ),
          child: Icon(icon, size: 18, color: T.ink3),
        ),
      );
}

class _MissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final VoidCallback onTap;
  const _MissionCard({required this.mission, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fee = (mission['delivery_fee'] ?? 0).toString();
    final dist = mission['distance_km'];
    final weight = mission['weight_kg'];
    final cargo =
        mission['cargo_description'] ?? mission['description'] ?? '';
    final from =
        mission['pickup_city'] ?? mission['pickup_address'] ?? 'Départ';
    final to =
        mission['delivery_city'] ?? mission['delivery_address'] ?? 'Arrivée';
    final bidsCount = mission['bids_count'] ?? mission['quotes_count'] ?? 0;
    final isUrgent = mission['is_urgent'] == true;
    final vehicleType = (mission['vehicle_type'] ?? '') as String;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(T.rLg),
          border: Border.all(
              color: isUrgent ? T.accent : T.line,
              width: isUrgent ? 1.5 : 1),
          boxShadow: T.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge row + fee
            Row(children: [
              if (isUrgent) ...[
                const _Badge(
                    label: 'URGENT',
                    bg: T.accent,
                    fg: Color(0xFF1a0f00)),
                const SizedBox(width: 6),
              ],
              if (vehicleType.isNotEmpty)
                _Badge(
                    label: _vehicleLabel(vehicleType),
                    bg: T.surface2,
                    fg: T.ink3),
              const Spacer(),
              Text('$fee FCFA',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: T.ink,
                      letterSpacing: -0.3)),
            ]),
            const SizedBox(height: 10),
            // Route dots
            Row(children: [
              Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: T.primary, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(from,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: T.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward, size: 14, color: T.ink3),
              ),
              Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: T.accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(to,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: T.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 8),
            // Details chip row
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: T.surface2,
                  borderRadius: BorderRadius.circular(T.r)),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 13, color: T.ink3),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      if (cargo.isNotEmpty) cargo,
                      if (dist != null) '$dist km',
                      if (weight != null) '$weight kg',
                    ].join(' · '),
                    style:
                        const TextStyle(fontSize: 12, color: T.ink2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: T.surface3,
                      borderRadius:
                          BorderRadius.circular(T.rFull)),
                  child: Text('$bidsCount devis',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: T.ink2)),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _vehicleLabel(String v) => switch (v) {
        'MOTO' => 'Moto',
        'CAR' => 'Voiture',
        'VAN' => 'Camion',
        'FOOT' => 'À pied',
        _ => v,
      };
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Badge({required this.label, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(T.rFull)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: fg)),
      );
}

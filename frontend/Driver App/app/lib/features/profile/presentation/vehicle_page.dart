import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

// Audit ref: [Front-Driver] backend exposes TransportProfileViewSet at
// /api/transport-profiles/ (filtered to current user). The /api/accounts/
// /driver-profile/ path does not exist server-side.
final _vehicleProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/transport-profiles/');
  final data = res.data;
  if (data is Map<String, dynamic> && data['results'] is List) {
    final results = data['results'] as List;
    if (results.isNotEmpty) return results.first as Map<String, dynamic>;
  }
  if (data is List && data.isNotEmpty) {
    return data.first as Map<String, dynamic>;
  }
  return <String, dynamic>{};
});

class VehiclePage extends ConsumerStatefulWidget {
  const VehiclePage({super.key});

  @override
  ConsumerState<VehiclePage> createState() => _VehiclePageState();
}

class _VehiclePageState extends ConsumerState<VehiclePage> {
  String? _selectedType;
  bool _saving = false;
  String? _error;

  static const _vehicles = [
    ('MOTO', 'Moto / Scooter', Icons.two_wheeler),
    ('CAR', 'Voiture', Icons.directions_car),
    ('VAN', 'Camionnette', Icons.airport_shuttle),
    ('TRUCK', 'Camion', Icons.local_shipping),
    ('BICYCLE', 'Vélo', Icons.pedal_bike),
    ('FOOT', 'À pied', Icons.directions_walk),
  ];

  Future<void> _save() async {
    if (_selectedType == null) return;
    setState(() { _saving = true; _error = null; });
    try {
      // Audit ref: [Front-Driver] transport-profiles is a regular DRF
      // ViewSet — update by id (PATCH detail) or create the singleton if
      // the driver has no profile yet (POST list).
      final current = ref.read(_vehicleProvider).value ?? const {};
      final profileId = current['id'];
      if (profileId != null) {
        await DriverDioClient.dio.patch(
          '/api/transport-profiles/$profileId/',
          data: {'vehicle_type': _selectedType},
        );
      } else {
        await DriverDioClient.dio.post(
          '/api/transport-profiles/',
          data: {'vehicle_type': _selectedType},
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Véhicule mis à jour !')),
      );
      ref.invalidate(_vehicleProvider);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiError.friendly(e);
          _saving = false;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(_vehicleProvider);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Mon véhicule'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(_vehicleProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (profile) {
          final currentType = profile['vehicle_type'] as String?;
          _selectedType ??= currentType;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!,
                          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('TYPE DE VÉHICULE',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: DriverPalette.textMuted, letterSpacing: 0.5)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 1.3,
                  children: _vehicles.map((v) {
                    final sel = _selectedType == v.$1;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedType = v.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        decoration: BoxDecoration(
                          color: sel ? DriverPalette.primary.withValues(alpha: 0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: sel ? DriverPalette.primary : DriverPalette.border,
                              width: sel ? 2 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(v.$3,
                              color: sel ? DriverPalette.primary : DriverPalette.textMuted,
                              size: 26),
                          const SizedBox(height: 6),
                          Text(v.$2,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 10.5, fontWeight: FontWeight.w600,
                                  color: sel ? DriverPalette.primary : DriverPalette.textSecondary)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: (_selectedType != currentType && !_saving) ? _save : null,
                    child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Enregistrer',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

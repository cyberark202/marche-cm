import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _missionDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  final res = await DriverDioClient.dio.get('/api/logistics/missions/$id/');
  return res.data as Map<String, dynamic>;
});

class MissionDetailPage extends ConsumerStatefulWidget {
  final String missionId;
  const MissionDetailPage({super.key, required this.missionId});

  @override
  ConsumerState<MissionDetailPage> createState() => _MissionDetailPageState();
}

class _MissionDetailPageState extends ConsumerState<MissionDetailPage> {
  bool _accepting = false;

  Future<void> _accept() async {
    setState(() => _accepting = true);
    try {
      await DriverDioClient.dio.post('/api/logistics/missions/${widget.missionId}/accept/');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mission acceptée ! Bonne livraison.')),
      );
      context.go('/active');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
        setState(() => _accepting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missionAsync = ref.watch(_missionDetailProvider(widget.missionId));
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Détail mission'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: missionAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 48, color: DriverPalette.textMuted),
            const SizedBox(height: 12),
            Text('Impossible de charger la mission',
                style: TextStyle(color: DriverPalette.textSecondary)),
          ]),
        ),
        data: (mission) => _MissionDetail(
          mission: mission,
          accepting: _accepting,
          onAccept: _accept,
        ),
      ),
    );
  }
}

class _MissionDetail extends StatelessWidget {
  final Map<String, dynamic> mission;
  final bool accepting;
  final VoidCallback onAccept;
  const _MissionDetail({required this.mission, required this.accepting, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final fee = (mission['delivery_fee'] ?? 0).toString();
    final dist = mission['distance_km'];
    final packageDesc = mission['package_description'] ?? 'Non précisé';
    final weight = mission['package_weight_kg'];
    final pickupAddr = mission['pickup_address'] ?? '';
    final deliveryAddr = mission['delivery_address'] ?? '';
    final notes = mission['driver_notes'] as String?;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fee banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: T.gradientPrimary,
                    borderRadius: BorderRadius.circular(DriverRadii.md),
                  ),
                  child: Column(children: [
                    const Text('Rémunération',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('$fee FCFA',
                        style: const TextStyle(color: Colors.white, fontSize: 32,
                            fontWeight: FontWeight.w800)),
                    if (dist != null)
                      Text('Distance estimée : $dist km',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 20),

                _SectionTitle('Adresses'),
                _AddressRow(icon: Icons.circle, color: Colors.green,
                    label: 'Enlèvement', address: pickupAddr),
                const SizedBox(height: 8),
                _AddressRow(icon: Icons.location_on, color: DriverPalette.primary,
                    label: 'Livraison', address: deliveryAddr),
                const SizedBox(height: 20),

                _SectionTitle('Colis'),
                _InfoTile(label: 'Description', value: packageDesc),
                if (weight != null) _InfoTile(label: 'Poids', value: '$weight kg'),
                if (notes != null && notes.isNotEmpty)
                  _InfoTile(label: 'Notes pour le livreur', value: notes),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: accepting ? null : onAccept,
              child: accepting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Accepter cette mission',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: DriverPalette.textMuted, letterSpacing: 0.5)),
  );
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, address;
  const _AddressRow({required this.icon, required this.color, required this.label, required this.address});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DriverPalette.border),
    ),
    child: Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: DriverPalette.textMuted,
            fontWeight: FontWeight.w600)),
        Text(address, style: const TextStyle(fontSize: 13, color: DriverPalette.textPrimary)),
      ])),
    ]),
  );
}

class _InfoTile extends StatelessWidget {
  final String label, value;
  const _InfoTile({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: DriverPalette.border),
    ),
    child: Row(children: [
      Text('$label : ', style: const TextStyle(fontSize: 13, color: DriverPalette.textSecondary,
          fontWeight: FontWeight.w600)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: DriverPalette.textPrimary))),
    ]),
  );
}

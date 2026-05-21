import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _activeDeliveriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/logistics/shipments/active/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

class ActiveDeliveryPage extends ConsumerWidget {
  const ActiveDeliveryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesAsync = ref.watch(_activeDeliveriesProvider);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: DriverPalette.primary,
            title: const Text('Livraisons en cours',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => ref.invalidate(_activeDeliveriesProvider),
              ),
            ],
          ),
          deliveriesAsync.when(
            loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(
              child: _EmptyState(
                icon: Icons.cloud_off_outlined,
                message: 'Erreur de chargement',
                action: FilledButton.tonal(
                  onPressed: () => ref.invalidate(_activeDeliveriesProvider),
                  child: const Text('Réessayer'),
                ),
              ),
            ),
            data: (deliveries) {
              if (deliveries.isEmpty) {
                return const SliverFillRemaining(
                  child: _EmptyState(
                    icon: Icons.local_shipping_outlined,
                    message: 'Aucune livraison en cours.\nAcceptez une mission pour commencer.',
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList.separated(
                  itemCount: deliveries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _DeliveryCard(shipment: deliveries[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  final Map<String, dynamic> shipment;
  const _DeliveryCard({required this.shipment});

  static const _statusLabels = {
    'PICKED_UP': ('Enlevé', Color(0xFF3B82F6)),
    'IN_TRANSIT': ('En transit', Color(0xFFF59E0B)),
    'ARRIVED': ('Arrivé', Color(0xFF10B981)),
    'PENDING_PICKUP': ('Prêt à enlever', Color(0xFF8B5CF6)),
  };

  @override
  Widget build(BuildContext context) {
    final id = shipment['id'].toString();
    final status = shipment['status'] as String? ?? '';
    final statusInfo = _statusLabels[status] ?? ('En cours', DriverPalette.primary);
    final pickupAddr = shipment['pickup_address'] ?? '';
    final deliveryAddr = shipment['delivery_address'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(DriverRadii.md),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text('Livraison #$id',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                            color: DriverPalette.textPrimary)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusInfo.$2.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(statusInfo.$1,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                            color: statusInfo.$2)),
                  ),
                ]),
                const SizedBox(height: 10),
                _AddrRow(icon: Icons.circle, color: Colors.green, text: pickupAddr),
                const SizedBox(height: 4),
                _AddrRow(icon: Icons.location_on, color: DriverPalette.primary, text: deliveryAddr),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              _ActionBtn(
                icon: Icons.map_outlined, label: 'Suivre',
                onTap: () => context.push('/active/tracking/$id'),
              ),
              const SizedBox(width: 8),
              if (status == 'PENDING_PICKUP')
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => context.push('/active/pickup/$id'),
                    child: const Text('Confirmer enlèvement', style: TextStyle(fontSize: 13)),
                  ),
                )
              else
                Expanded(
                  child: FilledButton(
                    onPressed: () => context.push('/active/otp/$id'),
                    child: const Text('Valider livraison', style: TextStyle(fontSize: 13)),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _AddrRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _AddrRow({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 12, color: color),
    const SizedBox(width: 6),
    Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: DriverPalette.textSecondary))),
  ]);
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: DriverPalette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: DriverPalette.primary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 13, color: DriverPalette.primary,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const _EmptyState({required this.icon, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: DriverPalette.textMuted),
      const SizedBox(height: 12),
      Text(message, textAlign: TextAlign.center,
          style: const TextStyle(color: DriverPalette.textSecondary, fontSize: 14, height: 1.5)),
      if (action != null) ...[const SizedBox(height: 16), action!],
    ]),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final _activeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res =
      await DriverDioClient.dio.get('/api/logistics/shipments/active/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

final _completedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio
      .get('/api/logistics/shipments/', queryParameters: {'status': 'DELIVERED'});
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

final _myBidsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/logistics/quotes/mine/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

// ── Page ──────────────────────────────────────────────────────────────────────

class ActiveDeliveryPage extends ConsumerWidget {
  const ActiveDeliveryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: T.bg,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(children: [
                  const Expanded(
                    child: Text('Mes courses',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: T.ink,
                            letterSpacing: -0.4)),
                  ),
                  _HeaderBtn(
                    icon: Icons.refresh,
                    onTap: () {
                      ref.invalidate(_activeProvider);
                      ref.invalidate(_completedProvider);
                      ref.invalidate(_myBidsProvider);
                    },
                  ),
                ]),
              ),
              // ── Tabs ─────────────────────────────────────────────────────
              Container(
                color: T.surface,
                child: TabBar(
                  labelColor: T.ink,
                  unselectedLabelColor: T.ink3,
                  labelStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w500),
                  indicatorColor: T.accent,
                  indicatorWeight: 2.5,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: T.line2,
                  tabs: const [
                    Tab(text: 'En cours'),
                    Tab(text: 'Livrées'),
                    Tab(text: 'Mes devis'),
                  ],
                ),
              ),
              // ── Tab views ────────────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  children: [
                    _ActiveTab(ref: ref),
                    _CompletedTab(ref: ref),
                    _BidsTab(ref: ref),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tabs ─────────────────────────────────────────────────────────────────────

class _ActiveTab extends ConsumerWidget {
  const _ActiveTab({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_activeProvider);
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: T.primary)),
      error: (_, __) => _ErrorView(
          onRetry: () => ref.invalidate(_activeProvider)),
      data: (items) => items.isEmpty
          ? const _EmptyView(
              icon: Icons.local_shipping_outlined,
              message: 'Aucune livraison en cours.\nAcceptez une mission pour commencer.',
            )
          : RefreshIndicator(
              color: T.primary,
              onRefresh: () => ref.refresh(_activeProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _DeliveryCard(shipment: items[i]),
              ),
            ),
    );
  }
}

class _CompletedTab extends ConsumerWidget {
  const _CompletedTab({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_completedProvider);
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: T.primary)),
      error: (_, __) => _ErrorView(
          onRetry: () => ref.invalidate(_completedProvider)),
      data: (items) => items.isEmpty
          ? const _EmptyView(
              icon: Icons.check_circle_outline,
              message: 'Aucune livraison complétée.',
            )
          : RefreshIndicator(
              color: T.primary,
              onRefresh: () => ref.refresh(_completedProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _CompletedCard(shipment: items[i]),
              ),
            ),
    );
  }
}

class _BidsTab extends ConsumerWidget {
  const _BidsTab({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_myBidsProvider);
    return async.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: T.primary)),
      error: (_, __) => _ErrorView(
          onRetry: () => ref.invalidate(_myBidsProvider)),
      data: (items) => items.isEmpty
          ? const _EmptyView(
              icon: Icons.balance_outlined,
              message: 'Vous n\'avez pas encore soumis de devis.',
            )
          : RefreshIndicator(
              color: T.primary,
              onRefresh: () => ref.refresh(_myBidsProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _BidCard(bid: items[i]),
              ),
            ),
    );
  }
}

// ── Cards ─────────────────────────────────────────────────────────────────────

class _DeliveryCard extends StatelessWidget {
  final Map<String, dynamic> shipment;
  const _DeliveryCard({required this.shipment});

  static const _statusMap = {
    'PENDING_PICKUP': ('Prêt à enlever', T.accentSoft, Color(0xFF8E5A00)),
    'PICKED_UP':      ('Enlevé', Color(0xFFE0E7FF), Color(0xFF3730A3)),
    'IN_TRANSIT':     ('En route', T.primarySoft, T.primaryDark),
    'ARRIVED':        ('Arrivé', Color(0xFFD1FAE5), T.success),
  };

  @override
  Widget build(BuildContext context) {
    final id = shipment['id'].toString();
    final status = (shipment['status'] as String?) ?? '';
    final (label, pillBg, pillFg) =
        _statusMap[status] ?? ('En cours', T.surface2, T.ink2);
    final from = shipment['pickup_city'] ?? shipment['pickup_address'] ?? '';
    final to = shipment['delivery_city'] ??
        shipment['delivery_address'] ?? '';

    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.line),
        boxShadow: T.shadowSm,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + ID
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(T.rFull),
                    ),
                    child: Row(children: [
                      Icon(Icons.local_shipping, size: 11, color: pillFg),
                      const SizedBox(width: 4),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: pillFg)),
                    ]),
                  ),
                  const Spacer(),
                  Text('#$id',
                      style: const TextStyle(
                          fontSize: 10,
                          color: T.ink4,
                          fontFamily: 'monospace')),
                ]),
                const SizedBox(height: 10),
                // Route
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
              ],
            ),
          ),
          Container(height: 1, color: T.line2),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              _ActionChip(
                icon: Icons.map_outlined,
                label: 'Carte',
                onTap: () => context.push('/active/tracking/$id'),
              ),
              const SizedBox(width: 8),
              if (status == 'PENDING_PICKUP')
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: T.accent,
                        foregroundColor: const Color(0xFF1a0f00),
                        minimumSize: const Size(0, 40),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    onPressed: () => context.push('/active/pickup/$id'),
                    child: const Text('Confirmer enlèvement'),
                  ),
                )
              else
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                    onPressed: () => context.push('/active/otp/$id'),
                    child: const Text('Valider livraison'),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _CompletedCard extends StatelessWidget {
  final Map<String, dynamic> shipment;
  const _CompletedCard({required this.shipment});

  @override
  Widget build(BuildContext context) {
    final id = shipment['id'].toString();
    final from = shipment['pickup_city'] ?? shipment['pickup_address'] ?? '';
    final to =
        shipment['delivery_city'] ?? shipment['delivery_address'] ?? '';
    final fee = (shipment['delivery_fee'] ?? 0).toString();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.line),
      ),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              color: T.primarySoft,
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.check, color: T.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$from → $to',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text('#$id',
                style: const TextStyle(fontSize: 11, color: T.ink3)),
          ]),
        ),
        Text('+$fee FCFA',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: T.success)),
      ]),
    );
  }
}

class _BidCard extends StatelessWidget {
  final Map<String, dynamic> bid;
  const _BidCard({required this.bid});

  @override
  Widget build(BuildContext context) {
    final amount = (bid['amount'] ?? bid['price'] ?? 0).toString();
    final status = (bid['status'] ?? 'PENDING') as String;
    final missionId = bid['mission'] ?? bid['mission_id'] ?? '';

    final (pillBg, pillFg) = switch (status) {
      'ACCEPTED' => (T.primarySoft, T.primaryDark),
      'REJECTED' => (T.coralSoft, T.coral),
      _ => (T.accentSoft, const Color(0xFF8E5A00)),
    };
    final label = switch (status) {
      'ACCEPTED' => 'Accepté',
      'REJECTED' => 'Refusé',
      _ => 'En attente',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(T.rLg),
        border: Border.all(color: T.line),
      ),
      child: Row(children: [
        const Icon(Icons.balance, size: 20, color: T.ink3),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Mission #$missionId',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.ink)),
            Text('Votre offre : $amount FCFA',
                style: const TextStyle(fontSize: 12, color: T.ink3)),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(T.rFull)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: pillFg)),
        ),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: T.line),
            borderRadius: BorderRadius.circular(T.r),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: T.ink2),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: T.ink2,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyView({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: T.ink4),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: T.ink3, fontSize: 14, height: 1.5)),
        ]),
      );
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, size: 48, color: T.ink4),
          const SizedBox(height: 12),
          const Text('Erreur de chargement',
              style: TextStyle(color: T.ink3, fontSize: 14)),
          const SizedBox(height: 8),
          FilledButton(
              onPressed: onRetry, child: const Text('Réessayer')),
        ]),
      );
}

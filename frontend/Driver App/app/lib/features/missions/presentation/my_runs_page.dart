import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

enum _RunsTab { quotes, active, delivered }

/// Mes courses — devis / en cours / historique (PDF 26).
final _runsProvider =
    FutureProvider.autoDispose<Map<String, List<Map<String, dynamic>>>>(
        (ref) async {
  final results = await Future.wait([
    DriverDioClient.dio.get("/api/transport-quotes/?mine=1&status=PENDING"),
    DriverDioClient.dio.get("/api/shipments/?driver_status=IN_PROGRESS"),
    DriverDioClient.dio.get("/api/shipments/?driver_status=DELIVERED"),
  ]);

  List<Map<String, dynamic>> _cast(dynamic data) {
    if (data is List) return data.cast<Map<String, dynamic>>();
    if (data is Map && data['results'] is List) {
      return (data['results'] as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  return {
    "quotes": _cast(results[0].data),
    "active": _cast(results[1].data),
    "delivered": _cast(results[2].data),
  };
});

class MyRunsPage extends ConsumerStatefulWidget {
  const MyRunsPage({super.key});

  @override
  ConsumerState<MyRunsPage> createState() => _MyRunsPageState();
}

class _MyRunsPageState extends ConsumerState<MyRunsPage> {
  _RunsTab _tab = _RunsTab.quotes;

  @override
  Widget build(BuildContext context) {
    final runs = ref.watch(_runsProvider);
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(onBack: () => context.canPop() ? context.pop() : null),
            runs.maybeWhen(
              data: (data) => _Tabs(
                quotes: data["quotes"]?.length ?? 0,
                active: data["active"]?.length ?? 0,
                delivered: data["delivered"]?.length ?? 0,
                tab: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
              orElse: () => _Tabs(
                quotes: 0,
                active: 0,
                delivered: 0,
                tab: _tab,
                onChanged: (t) => setState(() => _tab = t),
              ),
            ),
            Expanded(
              child: runs.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: T.primary)),
                error: (e, _) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined,
                          size: 48, color: T.ink4),
                      const SizedBox(height: 12),
                      const Text("Erreur de chargement",
                          style: TextStyle(color: T.ink3, fontSize: 14)),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: () => ref.invalidate(_runsProvider),
                        child: const Text("Réessayer"),
                      ),
                    ],
                  ),
                ),
                data: (data) {
                  final list = switch (_tab) {
                    _RunsTab.quotes => data["quotes"] ?? const [],
                    _RunsTab.active => data["active"] ?? const [],
                    _RunsTab.delivered => data["delivered"] ?? const [],
                  };
                  if (list.isEmpty) {
                    return _Empty(tab: _tab);
                  }
                  return RefreshIndicator(
                    color: T.primary,
                    onRefresh: () => ref.refresh(_runsProvider.future),
                    child: ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) => _RunCard(
                        run: list[i],
                        tab: _tab,
                        onTap: () {
                          final id = list[i]["id"];
                          if (id != null) {
                            context.push("/missions/$id");
                          }
                        },
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

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: const BoxDecoration(
        gradient: T.gradientDriverHeader,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(T.rXl),
            bottomRight: Radius.circular(T.rXl)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back, color: Colors.white))
          else
            const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Mes courses",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3)),
                Text("Devis · en cours · historique",
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

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.quotes,
    required this.active,
    required this.delivered,
    required this.tab,
    required this.onChanged,
  });
  final int quotes;
  final int active;
  final int delivered;
  final _RunsTab tab;
  final ValueChanged<_RunsTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Row(
        children: [
          _Tab(
              label: "Devis envoyés",
              count: quotes,
              selected: tab == _RunsTab.quotes,
              onTap: () => onChanged(_RunsTab.quotes)),
          const SizedBox(width: 6),
          _Tab(
              label: "En cours",
              count: active,
              selected: tab == _RunsTab.active,
              onTap: () => onChanged(_RunsTab.active)),
          const SizedBox(width: 6),
          _Tab(
              label: "Livrées",
              count: delivered,
              selected: tab == _RunsTab.delivered,
              onTap: () => onChanged(_RunsTab.delivered)),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rFull),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? T.primary : T.surface,
            borderRadius: BorderRadius.circular(T.rFull),
            border: Border.all(
                color: selected ? T.primary : T.line, width: selected ? 1.4 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : T.ink)),
              const SizedBox(width: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : T.surface2,
                  borderRadius: BorderRadius.circular(T.rFull),
                ),
                child: Text("$count",
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : T.ink3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard(
      {required this.run, required this.tab, required this.onTap});
  final Map<String, dynamic> run;
  final _RunsTab tab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final id = run["id"]?.toString() ?? "—";
    final from = (run["pickup_city"] ?? "Départ").toString();
    final to = (run["delivery_city"] ?? "Arrivée").toString();
    final cargo =
        (run["cargo_description"] ?? run["description"] ?? "").toString();
    final qty = run["quantity"]?.toString() ?? "—";
    final eta = run["estimated_delivery_date"]?.toString() ?? "—";
    final status = (run["status"] ?? "").toString().toUpperCase();

    late String badgeLabel;
    late Color badgeBg;
    late Color badgeFg;
    switch (tab) {
      case _RunsTab.quotes:
        badgeLabel = "En attente";
        badgeBg = T.accentSoft;
        badgeFg = T.accentDark;
        break;
      case _RunsTab.active:
        if (status == "PICKED_UP") {
          badgeLabel = "Pris en charge";
        } else if (status == "IN_TRANSIT" || status == "SHIPPED") {
          badgeLabel = "En route";
        } else {
          badgeLabel = "En cours";
        }
        badgeBg = T.primarySoft;
        badgeFg = T.primaryDark;
        break;
      case _RunsTab.delivered:
        badgeLabel = "Livrée";
        badgeBg = T.surface2;
        badgeFg = T.ink2;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(T.rLg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: T.surface,
            borderRadius: BorderRadius.circular(T.rLg),
            border: Border.all(color: T.line),
            boxShadow: T.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(T.rFull),
                    ),
                    child: Text(badgeLabel,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: badgeFg)),
                  ),
                  const Spacer(),
                  Text("#$id",
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: T.ink3,
                          letterSpacing: 0.3)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                          color: T.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(from,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: T.ink)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: T.ink)),
                  ),
                ],
              ),
              if (cargo.isNotEmpty || qty != "—") ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: T.surface2,
                    borderRadius: BorderRadius.circular(T.r),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined,
                          size: 13, color: T.ink3),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          [
                            if (cargo.isNotEmpty) cargo,
                            if (qty != "—") "$qty unités",
                          ].join(" · "),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: T.ink2,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (tab == _RunsTab.active && eta != "—") ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.schedule,
                            size: 12, color: T.ink3),
                        const SizedBox(width: 3),
                        Text("ETA $eta",
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: T.ink2)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab});
  final _RunsTab tab;

  @override
  Widget build(BuildContext context) {
    final label = switch (tab) {
      _RunsTab.quotes => "Pas de devis en attente.",
      _RunsTab.active => "Aucune course en cours.",
      _RunsTab.delivered => "Pas encore de livraison historisée.",
    };
    final icon = switch (tab) {
      _RunsTab.quotes => Icons.request_quote_outlined,
      _RunsTab.active => Icons.local_shipping_outlined,
      _RunsTab.delivered => Icons.history,
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: T.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 36, color: T.primaryDark),
            ),
            const SizedBox(height: 12),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: T.ink3)),
          ],
        ),
      ),
    );
  }
}

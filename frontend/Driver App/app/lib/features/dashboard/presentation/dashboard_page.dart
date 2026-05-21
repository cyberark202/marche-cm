import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';
import '../../../features/auth/application/auth_notifier.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/wallets/driver/earnings/');
  return res.data as Map<String, dynamic>;
});

// ── Page ─────────────────────────────────────────────────────────────────────

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  bool _isOnline = true;

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(authProvider).username ?? 'Livreur';
    final earnings = ref.watch(_dashboardProvider);

    return Scaffold(
      backgroundColor: T.bg,
      body: RefreshIndicator(
        color: T.primary,
        onRefresh: () => ref.refresh(_dashboardProvider.future),
        child: CustomScrollView(
          slivers: [
            // ── Header amber ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: T.gradientDriverHeader,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -30,
                      bottom: -40,
                      child: Icon(Icons.local_shipping,
                          size: 160,
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top row: avatar + name + bell
                            Row(children: [
                              _Avatar(name: name, size: 42),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Livreur indépendant',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Row(children: [
                                      Text(name,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white)),
                                      const SizedBox(width: 6),
                                      _Pill(label: '★ 4,8', dark: true),
                                    ]),
                                  ],
                                ),
                              ),
                              _IconBtn(
                                icon: Icons.notifications_outlined,
                                light: true,
                                onTap: () {},
                              ),
                            ]),
                            const SizedBox(height: 16),

                            // Online toggle
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18)),
                              ),
                              child: Row(children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _isOnline
                                        ? const Color(0xFF34D399)
                                        : Colors.white38,
                                    shape: BoxShape.circle,
                                    boxShadow: _isOnline
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF34D399)
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 0,
                                              spreadRadius: 4,
                                            )
                                          ]
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _isOnline
                                            ? 'En ligne · accepte les courses'
                                            : 'Hors ligne',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white),
                                      ),
                                      Text('Douala-centre',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white
                                                  .withValues(alpha: 0.8))),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _isOnline = !_isOnline),
                                  child: AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 200),
                                    width: 44,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: _isOnline
                                          ? T.success
                                          : Colors.white24,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: AnimatedAlign(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      alignment: _isOnline
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Padding(
                                        padding: const EdgeInsets.all(3),
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 16),

                            // Gains du jour
                            Text("Gains · aujourd'hui",
                                style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.08)),
                            earnings.when(
                              loading: () => const Text('…',
                                  style: TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (d) => Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      _fmt(d['this_month'] ?? '0'),
                                      style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.8),
                                    ),
                                    const SizedBox(width: 6),
                                    Text('FCFA',
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.white
                                                .withValues(alpha: 0.7),
                                            fontWeight: FontWeight.w600)),
                                  ]),
                            ),
                            Text('4 courses livrées · 2 en cours',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── KPI grid (overlaps header) ─────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, -18, 16, 0),
              sliver: SliverToBoxAdapter(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _KpiCard(
                      icon: Icons.balance,
                      tone: 'warn',
                      value: '12',
                      label: 'Devis ouverts',
                      sub: 'à proposer',
                      actionLabel: 'Voir',
                      onAction: () => context.go('/missions'),
                    ),
                    _KpiCard(
                      icon: Icons.local_shipping,
                      tone: 'info',
                      value: '2',
                      label: 'En cours',
                      sub: 'Edéa · Kribi',
                      actionLabel: 'Carte',
                      onAction: () => context.go('/active'),
                    ),
                    _KpiCard(
                      icon: Icons.inventory_2_outlined,
                      tone: 'success',
                      value: '148',
                      label: 'Livrées',
                      sub: 'ce mois',
                    ),
                    _KpiCard(
                      icon: Icons.emoji_events_outlined,
                      tone: 'coral',
                      value: '98 %',
                      label: "À l'heure",
                      sub: 'taux',
                    ),
                  ],
                ),
              ),
            ),

            // ── Demandes proches ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Demandes près de vous',
                actionLabel: 'Tout voir',
                onAction: () => context.go('/missions'),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 160,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  children: const [
                    _BidCard(
                        from: 'Douala',
                        to: 'Yaoundé',
                        dist: '245 km',
                        weight: '2,4 T',
                        kind: 'Huile palme × 200',
                        value: '2 320 000',
                        urgent: true,
                        bids: 3),
                    SizedBox(width: 10),
                    _BidCard(
                        from: 'Douala',
                        to: 'Bafoussam',
                        dist: '290 km',
                        weight: '0,8 T',
                        kind: 'Ciment × 100',
                        value: '648 000',
                        bids: 7),
                    SizedBox(width: 10),
                    _BidCard(
                        from: 'Douala',
                        to: 'Kribi',
                        dist: '170 km',
                        weight: '0,5 T',
                        kind: 'Carton huile',
                        value: '336 000',
                        bids: 2),
                  ],
                ),
              ),
            ),

            // ── Courses en cours ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Courses en cours',
                actionLabel: 'Toutes',
                onAction: () => context.go('/active'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _CourseCard(
                    id: '#84F2E1B',
                    from: 'Douala',
                    to: 'Yaoundé',
                    kind: 'Huile palme × 200',
                    step: 'En route',
                    stepPct: 0.65,
                    commission: '85 000',
                    tone: 'warn',
                    onTap: () => context.go('/active'),
                  ),
                  const SizedBox(height: 10),
                  _CourseCard(
                    id: '#5DC182A',
                    from: 'Douala',
                    to: 'Kribi',
                    kind: 'Carton huile × 30',
                    step: 'Pris en charge',
                    stepPct: 0.25,
                    commission: '38 000',
                    tone: 'info',
                    onTap: () => context.go('/active'),
                  ),
                ]),
              ),
            ),
          ],
        ),
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

// ── Widgets locaux ────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String name;
  final double size;
  const _Avatar({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().split(' ').take(2).map((s) => s[0]).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFFC940), T.accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(initials,
            style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1a0f00))),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final bool dark;
  const _Pill({required this.label, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: dark ? T.ink : T.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: dark ? Colors.white : T.primaryDark)),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final bool light;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap, this.light = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: light
              ? Colors.white.withValues(alpha: 0.15)
              : T.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: light
                  ? Colors.white.withValues(alpha: 0.2)
                  : T.line),
        ),
        child: Icon(icon,
            size: 20,
            color: light ? Colors.white : T.ink2),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String tone, value, label, sub;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _KpiCard({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
    required this.sub,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = {
      'success': (T.primarySoft, T.primaryDark),
      'info':    (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
      'warn':    (T.accentSoft, const Color(0xFF8E5A00)),
      'coral':   (T.coralSoft, T.coral),
    };
    final (bg, fg) = colors[tone] ?? (T.surface2, T.ink2);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: T.line),
        boxShadow: T.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: fg),
            ),
            const Spacer(),
            if (actionLabel != null)
              GestureDetector(
                onTap: onAction,
                child: Text(actionLabel!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: T.primary)),
              ),
          ]),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: T.ink,
                  letterSpacing: -0.4)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: T.ink2)),
          Text(sub,
              style: const TextStyle(fontSize: 10.5, color: T.ink3)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: T.ink,
                  letterSpacing: -0.2)),
        ),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text('$actionLabel →',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: T.primary)),
          ),
      ]),
    );
  }
}

class _BidCard extends StatelessWidget {
  final String from, to, dist, weight, kind, value;
  final bool urgent;
  final int bids;
  const _BidCard({
    required this.from,
    required this.to,
    required this.dist,
    required this.weight,
    required this.kind,
    required this.value,
    this.urgent = false,
    required this.bids,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/missions'),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: urgent ? T.accent : T.line, width: urgent ? 1.5 : 1),
          boxShadow: urgent
              ? [BoxShadow(color: T.accentSoft, blurRadius: 0, spreadRadius: 3)]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (urgent)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: T.accent, borderRadius: BorderRadius.circular(999)),
                child: const Text('URGENT',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1a0f00))),
              ),
            SizedBox(height: urgent ? 8 : 0),
            Row(children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: T.primary, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(from, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 14, color: T.ink3),
              ),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: T.accent, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(to, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: T.ink)),
            ]),
            const SizedBox(height: 6),
            Text('$dist · $weight · $bids devis',
                style: const TextStyle(fontSize: 11.5, color: T.ink3)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: T.surface2,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined, size: 12, color: T.ink3),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('$kind · ',
                      style: const TextStyle(fontSize: 11.5, color: T.ink2),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('$value F',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: T.ink)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final String id, from, to, kind, step, commission, tone;
  final double stepPct;
  final VoidCallback onTap;
  const _CourseCard({
    required this.id,
    required this.from,
    required this.to,
    required this.kind,
    required this.step,
    required this.stepPct,
    required this.commission,
    required this.tone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = {
      'warn': (T.accentSoft, const Color(0xFF8E5A00)),
      'info': (const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
    };
    final (pillBg, pillFg) = colors[tone] ?? (T.surface2, T.ink2);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: T.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: T.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: pillBg, borderRadius: BorderRadius.circular(999)),
                child: Row(children: [
                  Icon(Icons.local_shipping, size: 10, color: pillFg),
                  const SizedBox(width: 4),
                  Text(step,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: pillFg)),
                ]),
              ),
              const Spacer(),
              Text(id,
                  style: const TextStyle(
                      fontSize: 10,
                      color: T.ink3,
                      fontFamily: 'monospace')),
            ]),
            const SizedBox(height: 10),
            // Route progress
            Row(children: [
              Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: T.primary, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2))),
              const SizedBox(width: 6),
              Text(from, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(height: 2, color: T.line),
                    Align(
                      alignment: Alignment(-1 + stepPct * 2, 0),
                      child: Container(
                        width: 22, height: 22,
                        decoration: const BoxDecoration(
                            color: T.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.local_shipping,
                            size: 12, color: Color(0xFF1a0f00)),
                      ),
                    ),
                  ],
                ),
              ),
              Text(to, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: T.ink)),
              const SizedBox(width: 6),
              Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: T.line, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: Text('$kind',
                    style: const TextStyle(fontSize: 11.5, color: T.ink3),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('+ $commission FCFA',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: T.success)),
            ]),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../auth/session_store.dart';
import '../compliance/kyc_queue_page.dart';
import '../data/admin_repository.dart';
import '../disputes/arbitration_page.dart';

/// Screen 32 — Admin dashboard: GMV, KPIs, critical alerts.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
    super.key,
    required this.onNavigate,
    required this.onOpenAudit,
    required this.onOpenConfig,
  });

  /// Switch the shell's active tab (0 Accueil · 1 Comptes · 2 Litiges · 3 Wallet · 4 Profil).
  final void Function(int index) onNavigate;
  final VoidCallback onOpenAudit;
  final VoidCallback onOpenConfig;

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _repo = AdminRepository.instance;
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final dashboard = await _repo.dashboard();
    // Aggregates are best-effort: a failure here must not blank the dashboard.
    List<Map<String, dynamic>> orders = const [];
    List<Map<String, dynamic>> disputes = const [];
    List<Map<String, dynamic>> escrow = const [];
    List<Map<String, dynamic>> online = const [];
    try {
      final results = await Future.wait([
        _repo.orders(),
        _repo.shipmentDisputes(),
        _repo.escrowHolds(),
        _repo.onlineUsers(),
      ]);
      orders = results[0];
      disputes = results[1];
      escrow = results[2];
      online = results[3];
    } catch (_) {/* keep dashboard counters from /admin/dashboard/ */}

    num gmv = 0;
    for (final o in orders) {
      gmv += Fmt.amount(o['total_amount'] ?? o['total'] ?? o['amount'] ?? 0);
    }
    num escrowHeld = 0;
    int escrowActive = 0;
    for (final h in escrow) {
      final state = '${h['state']}';
      if (state == 'HELD' || state == 'FROZEN' || state == 'PARTIAL') {
        escrowHeld += Fmt.amount(h['remaining_amount'] ?? h['amount'] ?? 0);
        escrowActive++;
      }
    }
    final openDisputes =
        disputes.where((d) => '${d['status']}' == 'OPEN').toList();

    return _DashboardData(
      usersTotal: (dashboard['users_total'] as num?)?.toInt() ?? 0,
      usersVerified: (dashboard['users_verified'] as num?)?.toInt() ?? 0,
      openCompliance: (dashboard['open_compliance'] as num?)?.toInt() ?? 0,
      onlineCount: online.length,
      ordersCount: orders.length,
      gmv: gmv,
      escrowHeld: escrowHeld,
      escrowActive: escrowActive,
      openDisputes: openDisputes,
    );
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSessionStore>();
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(label: 'Chargement du tableau de bord…');
            }
            if (snap.hasError) {
              return AppErrorState(
                message: _repo.errorMessage(snap.error!),
                onRetry: _refresh,
              );
            }
            final d = snap.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(session),
                  const SizedBox(height: 16),
                  _gmvHero(d),
                  const SizedBox(height: 14),
                  _kpiGrid(d),
                  const SizedBox(height: 16),
                  _criticalAlerts(d),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header(AdminSessionStore session) {
    final name = session.username ?? 'Administrateur';
    return Row(
      children: [
        AvatarChip(Fmt.initials(name), color: AppPalette.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ADMINISTRATION · MARCHÉ CM',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: AppPalette.textMuted,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 8),
                  const StatusPill('SUPER ADMIN', color: AppPalette.secondary),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Rafraîchir',
          onPressed: _refresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _gmvHero(_DashboardData d) {
    return HeroPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('VOLUME TRAITÉ',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(Fmt.compactFcfa(d.gmv),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5)),
          const SizedBox(height: 6),
          Text('${Fmt.thousands(d.ordersCount)} commandes traitées',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => widget.onNavigate(1),
                  icon: const Icon(Icons.group_outlined, size: 18),
                  label: const Text('Comptes'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: widget.onOpenAudit,
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Audit'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(_DashboardData d) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        KpiCard(
          label: 'Utilisateurs',
          value: Fmt.thousands(d.usersTotal),
          sub: '${Fmt.thousands(d.usersVerified)} vérifiés',
          icon: Icons.group_outlined,
          onTap: () => widget.onNavigate(1),
        ),
        KpiCard(
          label: 'Séquestre actif',
          value: Fmt.compactFcfa(d.escrowHeld),
          sub: '${d.escrowActive} commandes',
          icon: Icons.lock_outline,
          accent: AppPalette.secondary,
          onTap: () => widget.onNavigate(3),
        ),
        KpiCard(
          label: 'Litiges ouverts',
          value: '${d.openDisputes.length}',
          sub: '${d.urgentDisputes} urgents',
          icon: Icons.gavel_outlined,
          accent: AppPalette.danger,
          onTap: () => widget.onNavigate(2),
        ),
        KpiCard(
          label: 'KYC à valider',
          value: '${d.openCompliance}',
          sub: 'en attente',
          icon: Icons.fact_check_outlined,
          accent: AppPalette.accent,
          onTap: _openKyc,
        ),
      ],
    );
  }

  Widget _criticalAlerts(_DashboardData d) {
    final alerts = <Widget>[];

    for (final dispute in d.openDisputes.take(3)) {
      final id = dispute['id'];
      final reason = (dispute['reason'] ?? dispute['dispute_type'] ?? 'Litige')
          .toString();
      final urgent = _isUrgent(dispute);
      alerts.add(_alertTile(
        color: AppPalette.danger,
        icon: Icons.warning_amber_rounded,
        badge: urgent ? 'URGENT' : 'OUVERT',
        title: reason,
        subtitle: 'Litige #${_short(id)} · décision en attente',
        actionLabel: 'Décider',
        onAction: () => _openArbitration(id is int ? id : int.tryParse('$id')),
      ));
    }

    if (d.openCompliance > 0) {
      alerts.add(_alertTile(
        color: AppPalette.accent,
        icon: Icons.fact_check_outlined,
        badge: 'KYC',
        title: '${d.openCompliance} documents KYC en attente',
        subtitle: 'File de conformité à traiter',
        actionLabel: 'Revue',
        onAction: _openKyc,
      ));
    }

    alerts.add(_alertTile(
      color: AppPalette.info,
      icon: Icons.account_balance_outlined,
      badge: 'FINOPS',
      title: 'Réconciliation wallet',
      subtitle: 'Rapprocher NotchPay vs système',
      actionLabel: 'Rapprocher',
      onAction: () => widget.onNavigate(3),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Alertes critiques'),
        SectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              for (int i = 0; i < alerts.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                alerts[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _alertTile({
    required Color color,
    required IconData icon,
    required String badge,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(badge, color: color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textMuted)),
              ],
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }

  void _openKyc() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const KycQueuePage()),
      );

  void _openArbitration(int? id) {
    if (id == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ArbitrationPage(disputeId: id)))
        .then((_) => _refresh());
  }

  static String _short(dynamic id) {
    final s = '$id';
    return s.length > 7 ? s.substring(0, 7).toUpperCase() : s.toUpperCase();
  }

  static bool _isUrgent(Map<String, dynamic> dispute) {
    final created = DateTime.tryParse('${dispute['created_at'] ?? ''}');
    if (created == null) return false;
    return DateTime.now().difference(created).inDays >= 2;
  }
}

class _DashboardData {
  _DashboardData({
    required this.usersTotal,
    required this.usersVerified,
    required this.openCompliance,
    required this.onlineCount,
    required this.ordersCount,
    required this.gmv,
    required this.escrowHeld,
    required this.escrowActive,
    required this.openDisputes,
  });

  final int usersTotal;
  final int usersVerified;
  final int openCompliance;
  final int onlineCount;
  final int ordersCount;
  final num gmv;
  final num escrowHeld;
  final int escrowActive;
  final List<Map<String, dynamic>> openDisputes;

  int get urgentDisputes =>
      openDisputes.where(_AdminDashboardPageState._isUrgent).length;
}

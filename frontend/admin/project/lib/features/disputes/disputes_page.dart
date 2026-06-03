import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';
import 'arbitration_page.dart';
import 'dispute_helpers.dart';
import 'dispute_multiview_page.dart';

/// Screen 37 — Disputes list with status filters.
class DisputesPage extends StatefulWidget {
  const DisputesPage({super.key});

  @override
  State<DisputesPage> createState() => _DisputesPageState();
}

class _DisputesPageState extends State<DisputesPage> {
  final _repo = AdminRepository.instance;
  late Future<List<Map<String, dynamic>>> _future;
  String _tab = 'Ouverts';

  static const _tabs = ['Ouverts', 'En arbitrage', 'Décidés', 'Tous'];

  @override
  void initState() {
    super.initState();
    _future = _repo.shipmentDisputes();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.shipmentDisputes());
    await _future;
  }

  bool _matchesTab(String status) {
    switch (_tab) {
      case 'Ouverts':
        return status == 'OPEN';
      case 'En arbitrage':
        return status == 'UNDER_REVIEW' ||
            status == 'INSPECTION_PENDING' ||
            status == 'APPEAL_REQUESTED';
      case 'Décidés':
        return status == 'RESOLVED' || status == 'CLOSED_NO_ACTION';
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(label: 'Chargement des litiges…');
            }
            if (snap.hasError) {
              return AppErrorState(
                message: _repo.errorMessage(snap.error!),
                onRetry: _refresh,
              );
            }
            final all = snap.data ?? const [];
            final open = all.where((d) => '${d['status']}' == 'OPEN').toList();
            final urgent = open.where(DisputeHelpers.isUrgent).length;
            final filtered =
                all.where((d) => _matchesTab('${d['status']}')).toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Litiges',
                          style: Theme.of(context).textTheme.headlineMedium),
                      Text('${open.length} ouverts · $urgent urgents',
                          style: const TextStyle(color: AppPalette.textMuted)),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final t in _tabs) ...[
                              ChoiceChip(
                                label: Text(t),
                                selected: _tab == t,
                                onSelected: (_) => setState(() => _tab = t),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const AppEmptyState(
                          title: 'Aucun litige',
                          subtitle: 'Rien à arbitrer pour ce filtre.',
                          icon: Icons.gavel_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _disputeCard(filtered[i]),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _disputeCard(Map<String, dynamic> d) {
    final id = d['id'];
    final status = '${d['status']}';
    final urgent = status == 'OPEN' && DisputeHelpers.isUrgent(d);
    final opener = DisputeHelpers.partyName(d['opened_by_display']);
    final accused = DisputeHelpers.partyName(d['accused_party_display']);
    final amount = DisputeHelpers.amount(d);
    return SectionCard(
      onTap: () => _open(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(urgent ? 'URGENT' : DisputeHelpers.statusLabel(status),
                  color: urgent
                      ? AppPalette.danger
                      : DisputeHelpers.statusColor(status)),
              const SizedBox(width: 8),
              Text('LIT #${DisputeHelpers.short(id)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5)),
              const Spacer(),
              Text(Fmt.relative(d['created_at']),
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.textMuted)),
              const SizedBox(width: 2),
              InkWell(
                onTap: () => _openMultiview(d, id),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.groups_outlined,
                      size: 18, color: AppPalette.secondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('${d['reason'] ?? 'Litige'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (amount > 0) ...[
                const SizedBox(width: 8),
                Text(Fmt.fcfa(amount),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: AppPalette.danger)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text('$opener vs $accused',
              style: const TextStyle(color: AppPalette.textMuted)),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 14, color: AppPalette.secondary),
              SizedBox(width: 6),
              Text('Séquestre concerné',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppPalette.secondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  void _open(dynamic id) {
    final intId = id is int ? id : int.tryParse('$id');
    if (intId == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => ArbitrationPage(disputeId: intId)))
        .then((_) => _refresh());
  }

  void _openMultiview(Map<String, dynamic> d, dynamic id) {
    final intId = id is int ? id : int.tryParse('$id');
    if (intId == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) =>
                DisputeMultiviewPage(disputeId: intId, dispute: d)))
        .then((_) => _refresh());
  }
}

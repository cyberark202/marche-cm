import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

/// Screen 40 — Audit & activity log with CSV export.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _repo = AdminRepository.instance;
  late Future<List<Map<String, dynamic>>> _future;
  String _filter = 'Tous';
  bool _exporting = false;

  static const _filters = ['Tous', 'WALLET', 'ORDER', 'COMPLIANCE', 'DISPUTE'];

  @override
  void initState() {
    super.initState();
    _future = _repo.auditEvents();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.auditEvents());
    await _future;
  }

  bool _matches(Map<String, dynamic> e) {
    if (_filter == 'Tous') return true;
    final cat = '${e['category'] ?? ''}'.toUpperCase();
    return cat.contains(_filter);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final csv = await _repo.exportAuditCsv();
      if (!mounted) return;
      final lines = csv.split('\n').where((l) => l.trim().isNotEmpty).toList();
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Audit CSV · ${lines.length} ligne(s)'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Text(
                lines.take(40).join('\n'),
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit & journaux'),
        actions: [
          IconButton(
            tooltip: 'Exporter CSV',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2))
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AppLoadingState(label: 'Chargement du journal…');
          }
          if (snap.hasError) {
            return AppErrorState(
              message: _repo.errorMessage(snap.error!),
              onRetry: _refresh,
            );
          }
          final events = (snap.data ?? const []).where(_matches).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _filters) ...[
                        ChoiceChip(
                          label: Text(f == 'Tous' ? 'Tous' : _label(f)),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: events.isEmpty
                    ? const AppEmptyState(
                        title: 'Journal vide',
                        subtitle: 'Aucun événement pour ce filtre.',
                        icon: Icons.receipt_long_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: events.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _eventCard(events[i]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _label(String cat) {
    switch (cat) {
      case 'WALLET':
        return 'Wallet';
      case 'ORDER':
        return 'Commandes';
      case 'COMPLIANCE':
        return 'KYC';
      case 'DISPUTE':
        return 'Litiges';
      default:
        return cat;
    }
  }

  Widget _eventCard(Map<String, dynamic> e) {
    final outcome = '${e['outcome'] ?? ''}'.toUpperCase();
    final ok = outcome.isEmpty || outcome == 'SUCCESS' || outcome == 'OK';
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: TileRow(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (ok ? AppPalette.primary : AppPalette.danger)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(_iconFor('${e['category']}'),
              size: 18, color: ok ? AppPalette.primary : AppPalette.danger),
        ),
        title: '${e['event_type'] ?? e['category'] ?? 'Événement'}',
        subtitle: [
          if ('${e['actor_role'] ?? ''}'.isNotEmpty) '${e['actor_role']}',
          if ('${e['entity_type'] ?? ''}'.isNotEmpty)
            '${e['entity_type']} #${e['entity_id'] ?? ''}',
          Fmt.dateTime(e['created_at']),
        ].where((s) => s.trim().isNotEmpty).join(' · '),
        trailing: outcome.isEmpty
            ? null
            : StatusPill(outcome,
                color: ok ? AppPalette.success : AppPalette.danger),
      ),
    );
  }

  IconData _iconFor(String category) {
    final c = category.toUpperCase();
    if (c.contains('WALLET')) return Icons.account_balance_wallet_outlined;
    if (c.contains('ORDER')) return Icons.shopping_bag_outlined;
    if (c.contains('COMPLIANCE')) return Icons.fact_check_outlined;
    if (c.contains('DISPUTE')) return Icons.gavel_outlined;
    if (c.contains('AUTH')) return Icons.lock_outline;
    return Icons.bolt_outlined;
  }
}

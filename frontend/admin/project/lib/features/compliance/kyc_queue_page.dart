import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';
import 'document_review_page.dart';

/// Screen 35 — KYC compliance queue, grouped by user.
class KycQueuePage extends StatefulWidget {
  const KycQueuePage({super.key});

  @override
  State<KycQueuePage> createState() => _KycQueuePageState();
}

class _KycQueuePageState extends State<KycQueuePage> {
  final _repo = AdminRepository.instance;
  late Future<_KycData> _future;
  String _tab = 'À traiter';

  static const _tabs = ['À traiter', 'Validés', 'Rejetés', 'Tous'];

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_KycData> _load() async {
    final results = await Future.wait([
      _repo.complianceDocuments(),
      _repo.users(),
    ]);
    final docs = results[0];
    final users = results[1];
    final names = <String, String>{};
    for (final u in users) {
      names['${u['id']}'] =
          '${u['username'] ?? u['name'] ?? 'Utilisateur #${u['id']}'}';
    }
    return _KycData(documents: docs, userNames: names);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  bool _matchesTab(String status) {
    switch (_tab) {
      case 'À traiter':
        return status == 'PENDING';
      case 'Validés':
        return status == 'APPROVED';
      case 'Rejetés':
        return status == 'REJECTED';
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conformité KYC')),
      body: FutureBuilder<_KycData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AppLoadingState(label: 'Chargement de la file KYC…');
          }
          if (snap.hasError) {
            return AppErrorState(
              message: _repo.errorMessage(snap.error!),
              onRetry: _refresh,
            );
          }
          final data = snap.data!;
          final docs =
              data.documents.where((d) => _matchesTab('${d['status']}')).toList();
          final groups = _groupByUser(docs);
          final pendingTotal = data.documents
              .where((d) => '${d['status']}' == 'PENDING')
              .length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$pendingTotal documents en attente',
                        style: const TextStyle(color: AppPalette.textMuted)),
                    const SizedBox(height: 10),
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
                child: groups.isEmpty
                    ? const AppEmptyState(
                        title: 'File vide',
                        subtitle: 'Aucun document pour ce filtre.',
                        icon: Icons.fact_check_outlined,
                      )
                    : RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: groups.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) =>
                              _groupCard(groups[i], data.userNames),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<_UserGroup> _groupByUser(List<Map<String, dynamic>> docs) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final d in docs) {
      final key = '${d['user'] ?? d['user_id'] ?? '?'}';
      map.putIfAbsent(key, () => []).add(d);
    }
    return map.entries
        .map((e) => _UserGroup(userId: e.key, documents: e.value))
        .toList();
  }

  Widget _groupCard(_UserGroup group, Map<String, String> names) {
    final name = names[group.userId] ?? 'Utilisateur #${group.userId}';
    final oldest = group.documents
        .map((d) => DateTime.tryParse('${d['created_at'] ?? ''}'))
        .whereType<DateTime>()
        .fold<DateTime?>(null, (acc, dt) => acc == null || dt.isBefore(acc) ? dt : acc);
    final urgent = oldest != null &&
        DateTime.now().difference(oldest).inDays >= 2 &&
        group.documents.any((d) => '${d['status']}' == 'PENDING');
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onTap: () => _openGroup(group, name),
      child: TileRow(
        leading: AvatarChip(Fmt.initials(name), color: AppPalette.accent),
        title: name,
        subtitle:
            '${group.documents.length} document(s) · soumis ${oldest != null ? Fmt.relative(oldest.toIso8601String()) : '—'}',
        trailing: urgent
            ? const StatusPill('URGENT', color: AppPalette.danger)
            : const Icon(Icons.chevron_right, color: AppPalette.textMuted),
      ),
    );
  }

  void _openGroup(_UserGroup group, String name) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
            for (final doc in group.documents)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text('${doc['doc_type'] ?? 'Document'}'),
                subtitle: Text('Statut : ${doc['status']}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  _openReview(doc, name);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _openReview(Map<String, dynamic> doc, String userName) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => DocumentReviewPage(document: doc, userName: userName),
        ))
        .then((reviewed) {
      if (reviewed == true) _refresh();
    });
  }
}

class _KycData {
  _KycData({required this.documents, required this.userNames});
  final List<Map<String, dynamic>> documents;
  final Map<String, String> userNames;
}

class _UserGroup {
  _UserGroup({required this.userId, required this.documents});
  final String userId;
  final List<Map<String, dynamic>> documents;
}

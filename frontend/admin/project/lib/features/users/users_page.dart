import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/roles.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';
import 'user_detail_page.dart';

/// Screen 33 — Users directory with search + role filters.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _repo = AdminRepository.instance;
  late Future<List<Map<String, dynamic>>> _future;
  final _search = TextEditingController();
  String _bucket = 'Tous';
  bool _kycPendingOnly = false;

  static const _buckets = ['Tous', 'Acheteur', 'Vendeur', 'Livreur'];

  @override
  void initState() {
    super.initState();
    _future = _repo.users();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.users());
    await _future;
  }

  List<Map<String, dynamic>> _filter(List<Map<String, dynamic>> users) {
    final q = _search.text.trim().toLowerCase();
    return users.where((u) {
      if (!Roles.matchesBucket(_bucket, '${u['role']}')) return false;
      if (_kycPendingOnly && (u['is_verified'] == true)) return false;
      if (q.isEmpty) return true;
      final hay = [
        u['username'],
        u['name'],
        u['email'],
        u['city'],
        u['reference_code'],
      ].map((e) => '$e'.toLowerCase()).join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(label: 'Chargement des comptes…');
            }
            if (snap.hasError) {
              return AppErrorState(
                message: _repo.errorMessage(snap.error!),
                onRetry: _refresh,
              );
            }
            final all = snap.data ?? const [];
            final filtered = _filter(all);
            return Column(
              children: [
                _topBar(all.length),
                Expanded(
                  child: filtered.isEmpty
                      ? const AppEmptyState(
                          title: 'Aucun compte',
                          subtitle: 'Aucun résultat pour ce filtre.',
                          icon: Icons.group_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _userCard(filtered[i]),
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

  Widget _topBar(int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Utilisateurs',
              style: Theme.of(context).textTheme.headlineMedium),
          Text('${Fmt.thousands(total)} comptes',
              style: const TextStyle(color: AppPalette.textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Nom, email, téléphone…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final b in _buckets) ...[
                  ChoiceChip(
                    label: Text(b),
                    selected: !_kycPendingOnly && _bucket == b,
                    onSelected: (_) =>
                        setState(() {
                      _bucket = b;
                      _kycPendingOnly = false;
                    }),
                  ),
                  const SizedBox(width: 8),
                ],
                ChoiceChip(
                  label: const Text('KYC en attente'),
                  selected: _kycPendingOnly,
                  onSelected: (_) =>
                      setState(() => _kycPendingOnly = !_kycPendingOnly),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _userCard(Map<String, dynamic> u) {
    final name = ('${u['username'] ?? ''}'.trim().isNotEmpty
        ? '${u['username']}'
        : '${u['name'] ?? 'Sans nom'}');
    final role = '${u['role']}';
    final city = '${u['city'] ?? ''}'.trim();
    final online = u['is_online'] == true;
    final verified = u['is_verified'] == true;
    final presence =
        online ? 'En ligne' : (Fmt.relative(u['last_seen_at']));
    final subtitle = [
      Roles.label(role),
      if (city.isNotEmpty) city,
      if (presence.isNotEmpty) presence,
    ].join(' · ');

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onTap: () {
        final id = u['id'];
        if (id is int) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserDetailPage(userId: id)),
          );
        }
      },
      child: TileRow(
        leading: Stack(
          children: [
            AvatarChip(Fmt.initials(name), color: Roles.color(role)),
            if (online)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppPalette.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: name,
        subtitle: subtitle,
        trailing: verified
            ? const StatusPill('KYC OK', color: AppPalette.success)
            : const StatusPill('KYC ?', color: AppPalette.warning),
      ),
    );
  }
}

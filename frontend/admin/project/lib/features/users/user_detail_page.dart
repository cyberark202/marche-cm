import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/roles.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

/// Screen 34 — User profile: identity, KYC, audit-relevant facts.
class UserDetailPage extends StatefulWidget {
  const UserDetailPage({super.key, required this.userId});
  final int userId;

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  final _repo = AdminRepository.instance;
  late Future<_UserBundle> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_UserBundle> _load() async {
    final user = await _repo.user(widget.userId);
    List<Map<String, dynamic>> docs = const [];
    try {
      final all = await _repo.complianceDocuments();
      docs = all
          .where((d) =>
              '${d['user'] ?? d['user_id'] ?? ''}' == '${widget.userId}')
          .toList();
    } catch (_) {/* compliance list is best-effort */}
    return _UserBundle(user: user, documents: docs);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  bool _busy = false;

  Future<void> _toggleSuspension(Map<String, dynamic> u) async {
    final suspended = u['is_suspended'] == true;
    final id = u['id'];
    if (id is! int) return;

    String reason = '';
    if (!suspended) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Suspendre le compte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Le compte sera déconnecté (login, jetons et websocket révoqués). '
                  'Indiquez le motif (journalisé).'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                    hintText: 'Motif de la suspension', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Suspendre')),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = controller.text.trim();
    }

    setState(() => _busy = true);
    try {
      if (suspended) {
        await _repo.unsuspendUser(id);
      } else {
        await _repo.suspendUser(id, reason: reason);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(suspended ? 'Compte réactivé.' : 'Compte suspendu.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_repo.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _moderation(Map<String, dynamic> u) {
    final role = '${u['role']}';
    final suspended = u['is_suspended'] == true;
    // The backend forbids suspending an admin; hide the control for those.
    final isAdmin = role == 'GENERAL_ADMIN';
    if (isAdmin) return const SizedBox.shrink();
    final reason = '${u['suspension_reason'] ?? ''}'.trim();
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(suspended ? Icons.lock_outline : Icons.verified_user_outlined,
                  size: 18,
                  color: suspended ? AppPalette.danger : AppPalette.success),
              const SizedBox(width: 8),
              Text(suspended ? 'Compte suspendu' : 'Compte actif',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (suspended && reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Motif : $reason',
                style: const TextStyle(
                    fontSize: 12.5, color: AppPalette.textMuted)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: suspended
                  ? null
                  : FilledButton.styleFrom(backgroundColor: AppPalette.danger),
              onPressed: _busy ? null : () => _toggleSuspension(u),
              icon: Icon(suspended ? Icons.lock_open : Icons.block),
              label: Text(suspended ? 'Réactiver le compte' : 'Suspendre le compte'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiche utilisateur')),
      body: FutureBuilder<_UserBundle>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          if (snap.hasError) {
            return AppErrorState(
              message: _repo.errorMessage(snap.error!),
              onRetry: _refresh,
            );
          }
          final u = snap.data!.user;
          final docs = snap.data!.documents;
          final name = '${u['username'] ?? u['name'] ?? 'Utilisateur'}';
          final role = '${u['role']}';
          final verified = u['is_verified'] == true;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _identity(u, name, role, verified),
              const SizedBox(height: 14),
              _moderation(u),
              const SizedBox(height: 14),
              _stats(u),
              const SizedBox(height: 16),
              const SectionLabel('Coordonnées'),
              _contact(u),
              const SizedBox(height: 16),
              SectionLabel('Conformité KYC',
                  trailing: Text('${docs.length} document(s)',
                      style: const TextStyle(
                          fontSize: 12, color: AppPalette.textMuted))),
              _kyc(docs),
            ],
          );
        },
      ),
    );
  }

  Widget _identity(
      Map<String, dynamic> u, String name, String role, bool verified) {
    final ref = '${u['reference_code'] ?? u['id']}';
    return SectionCard(
      child: Row(
        children: [
          AvatarChip(Fmt.initials(name), size: 56, color: Roles.color(role)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                    '${Roles.label(role)} · ${u['city'] ?? '—'} · #$ref',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppPalette.textMuted)),
                const SizedBox(height: 8),
                StatusPill(
                  verified ? 'KYC VALIDÉ' : 'KYC NON VÉRIFIÉ',
                  color: verified ? AppPalette.success : AppPalette.warning,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stats(Map<String, dynamic> u) {
    return Row(
      children: [
        Expanded(
          child: _statBox('Niveau KYC', '${u['kyc_level'] ?? 0}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox('Confiance',
              '${u['trust_score'] ?? '—'}'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statBox(
              'Présence', u['is_online'] == true ? 'En ligne' : 'Hors ligne'),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        children: [
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 11.5, color: AppPalette.textMuted)),
        ],
      ),
    );
  }

  Widget _contact(Map<String, dynamic> u) {
    return SectionCard(
      child: Column(
        children: [
          _kv(Icons.mail_outline, 'E-mail', '${u['email'] ?? '—'}'),
          const Divider(height: 18),
          _kv(Icons.badge_outlined, 'Rôle', Roles.label('${u['role']}')),
          const Divider(height: 18),
          _kv(Icons.place_outlined, 'Localisation',
              '${u['location_label'] ?? u['city'] ?? '—'}'),
          const Divider(height: 18),
          _kv(Icons.public, 'Pays', '${u['country_code'] ?? '—'}'),
        ],
      ),
    );
  }

  Widget _kv(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppPalette.textMuted),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppPalette.textMuted)),
        const Spacer(),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _kyc(List<Map<String, dynamic>> docs) {
    if (docs.isEmpty) {
      return const SectionCard(
        child: Text('Aucun document de conformité associé.',
            style: TextStyle(color: AppPalette.textMuted)),
      );
    }
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < docs.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _docRow(docs[i]),
          ],
        ],
      ),
    );
  }

  Widget _docRow(Map<String, dynamic> doc) {
    final status = '${doc['status']}';
    final (color, label) = switch (status) {
      'APPROVED' => (AppPalette.success, 'VALIDÉ'),
      'REJECTED' => (AppPalette.danger, 'REJETÉ'),
      _ => (AppPalette.warning, 'EN ATTENTE'),
    };
    return TileRow(
      leading: Icon(Icons.description_outlined,
          color: AppPalette.textMuted, size: 22),
      title: '${doc['doc_type'] ?? 'Document'}',
      subtitle: 'Soumis ${Fmt.relative(doc['created_at'])}',
      trailing: StatusPill(label, color: color),
    );
  }
}

class _UserBundle {
  _UserBundle({required this.user, required this.documents});
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> documents;
}

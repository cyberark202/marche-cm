import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';
import 'dispute_helpers.dart';

/// Screen 38 — Arbitration: parties, timeline, escrow decision.
class ArbitrationPage extends StatefulWidget {
  const ArbitrationPage({super.key, required this.disputeId});
  final int disputeId;

  @override
  State<ArbitrationPage> createState() => _ArbitrationPageState();
}

class _ArbitrationPageState extends State<ArbitrationPage> {
  final _repo = AdminRepository.instance;
  late Future<Map<String, dynamic>> _future;
  bool _submitting = false;

  static const _decisions = [
    ('REFUND_BUYER', 'Rembourser l\'acheteur', Icons.south_west),
    ('RELEASE_SELLER', 'Libérer le vendeur', Icons.north_east),
    ('SPLIT', 'Partage des fonds', Icons.call_split),
  ];

  @override
  void initState() {
    super.initState();
    _future = _repo.shipmentDispute(widget.disputeId);
  }

  Future<void> _refresh() async {
    setState(() => _future = _repo.shipmentDispute(widget.disputeId));
    await _future;
  }

  Future<void> _decide(String decision, String label) async {
    final note = await _askNote(label);
    if (note == null) return; // cancelled
    setState(() => _submitting = true);
    try {
      await _repo.decideDispute(
        widget.disputeId,
        decision: decision,
        resolutionNote: note.isEmpty ? 'Décision admin : $label' : note,
      );
      if (!mounted) return;
      showSnack(context, 'Litige résolu — $label.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
      setState(() => _submitting = false);
    }
  }

  Future<String?> _askNote(String label) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Motif de la décision (obligatoire pour la traçabilité)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arbitrage')),
      body: FutureBuilder<Map<String, dynamic>>(
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
          final d = snap.data!;
          final status = '${d['status']}';
          final decided = status == 'RESOLVED' || status == 'CLOSED_NO_ACTION';
          final amount = DisputeHelpers.amount(d);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _escrowHero(d, amount, status),
              const SizedBox(height: 14),
              _parties(d),
              const SizedBox(height: 16),
              const SectionLabel('Chronologie'),
              _timeline(d),
              const SizedBox(height: 16),
              const SectionLabel('Décision séquestre'),
              if (decided)
                _decidedCard(d)
              else
                _decisionButtons(),
            ],
          );
        },
      ),
    );
  }

  Widget _escrowHero(Map<String, dynamic> d, num amount, String status) {
    return HeroPanel(
      gradient: AppPalette.gradientRoyal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusPill('SÉQUESTRE GELÉ',
                  color: Colors.white, filled: false),
              const Spacer(),
              Text('LIT #${DisputeHelpers.short(d['id'])}',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9))),
            ],
          ),
          const SizedBox(height: 12),
          Text(amount > 0 ? Fmt.fcfa(amount) : 'Montant sous séquestre',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              '${d['reason'] ?? 'Litige'} · ouvert ${Fmt.relative(d['created_at'])}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _parties(Map<String, dynamic> d) {
    return Row(
      children: [
        Expanded(
          child: _partyCard('PLAIGNANT', d['opened_by_display'],
              AppPalette.danger),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _partyCard('MIS EN CAUSE', d['accused_party_display'],
              AppPalette.secondary),
        ),
      ],
    );
  }

  Widget _partyCard(String role, dynamic display, Color color) {
    final name = DisputeHelpers.partyName(display);
    final sub = display is Map ? '${display['role'] ?? ''}' : '';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(role,
              style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 10),
          AvatarChip(Fmt.initials(name), color: color),
          const SizedBox(height: 8),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty)
            Text(sub,
                style: const TextStyle(
                    fontSize: 11.5, color: AppPalette.textMuted)),
        ],
      ),
    );
  }

  Widget _timeline(Map<String, dynamic> d) {
    final events = <(String, String, String)>[];
    events.add((
      'Litige ouvert',
      Fmt.dateTime(d['created_at']),
      '${d['details'] ?? d['reason'] ?? ''}',
    ));
    final evidences = d['evidences'];
    if (evidences is List && evidences.isNotEmpty) {
      events.add(('Preuves jointes', '${evidences.length} pièce(s)', ''));
    }
    if ('${d['status']}' == 'RESOLVED') {
      events.add((
        'Décision rendue',
        Fmt.dateTime(d['decided_at']),
        '${d['resolution_note'] ?? ''}',
      ));
    }
    return SectionCard(
      child: Column(
        children: [
          for (int i = 0; i < events.length; i++)
            _timelineRow(events[i], isLast: i == events.length - 1),
        ],
      ),
    );
  }

  Widget _timelineRow((String, String, String) e, {required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: 3),
                decoration: const BoxDecoration(
                    color: AppPalette.primary, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: AppPalette.borderSoft),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.$1,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (e.$2.isNotEmpty)
                    Text(e.$2,
                        style: const TextStyle(
                            fontSize: 12, color: AppPalette.textMuted)),
                  if (e.$3.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(e.$3,
                        style: const TextStyle(
                            fontSize: 12.5, color: AppPalette.text)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _decisionButtons() {
    return Column(
      children: [
        for (final (value, label, icon) in _decisions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : () => _decide(value, label),
                icon: Icon(icon),
                label: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(label),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 16),
                ),
              ),
            ),
          ),
        if (_submitting)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _decidedCard(Map<String, dynamic> d) {
    final decision = '${d['admin_decision'] ?? ''}';
    final label = switch (decision) {
      'REFUND_BUYER' => 'Acheteur remboursé',
      'RELEASE_SELLER' => 'Vendeur libéré',
      'SPLIT' => 'Fonds partagés',
      _ => 'Décidé',
    };
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppPalette.success),
              const SizedBox(width: 10),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
            ],
          ),
          if ('${d['resolution_note'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${d['resolution_note']}',
                style: const TextStyle(color: AppPalette.textMuted)),
          ],
        ],
      ),
    );
  }
}

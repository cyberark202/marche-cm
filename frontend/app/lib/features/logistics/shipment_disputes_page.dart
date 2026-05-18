import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_ui.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import 'dispute_create_page.dart';
import 'dispute_detail_page.dart';

class ShipmentDisputesPage extends StatefulWidget {
  const ShipmentDisputesPage({super.key});

  @override
  State<ShipmentDisputesPage> createState() => _ShipmentDisputesPageState();
}

class _ShipmentDisputesPageState extends State<ShipmentDisputesPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<Map<String, dynamic>> _disputes = const [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'ALL';

  static const _statusOptions = [
    ('ALL', 'Tous'),
    ('OPEN', 'Ouverts'),
    ('UNDER_REVIEW', 'En cours'),
    ('INSPECTION_PENDING', 'Inspection'),
    ('APPEAL_REQUESTED', 'Appel'),
    ('RESOLVED', 'Resolus'),
    ('CLOSED_NO_ACTION', 'Fermes'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _sub = RealtimeEventsService.instance.events.listen((e) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(e, 'logistics')) _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      _disputes = await _api.getList('/api/shipment-disputes/', token: token);
      _error = null;
    } catch (e) {
      _error = _api.toUserMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openNewDispute() async {
    final ctrl = TextEditingController();
    final shipmentId = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau litige'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'ID de l\'expedition',
            hintText: 'Ex: 42',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final id = int.tryParse(ctrl.text.trim());
              if (id == null || id <= 0) return;
              Navigator.pop(context, id);
            },
            child: const Text('Continuer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (shipmentId == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DisputeCreatePage(shipmentId: shipmentId),
      ),
    );
    _load();
  }

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'ALL') return _disputes;
    return _disputes.where((d) => d['status'] == _statusFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Litiges'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final (value, label) in _statusOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _statusFilter == value,
                      onSelected: (_) => setState(() => _statusFilter = value),
                    ),
                  ),
                if (_statusFilter != 'ALL')
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: const Icon(Icons.close, size: 14),
                      label: const Text('Effacer', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.orange.shade50,
                      side: BorderSide(color: Colors.orange.shade300),
                      onPressed: () => setState(() => _statusFilter = 'ALL'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const AppSkeletonListView()
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _filtered.isEmpty
                  ? AppEmptyState(
                      title: 'Aucun litige',
                      subtitle: _statusFilter == 'ALL'
                          ? 'Aucun litige ouvert pour le moment.'
                          : 'Aucun litige avec ce statut.',
                      onRetry: _load,
                      icon: Icons.gavel_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _DisputeTile(
                        dispute: _filtered[i],
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DisputeDetailPage(
                                disputeId: _filtered[i]['id'] as int,
                              ),
                            ),
                          );
                          _load();
                        },
                      ),
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openNewDispute,
        icon: const Icon(Icons.add),
        label: const Text('Nouveau litige'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dispute tile
// ---------------------------------------------------------------------------
class _DisputeTile extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onTap;

  const _DisputeTile({required this.dispute, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = dispute['status'] as String? ?? '';
    final type = dispute['dispute_type'] as String? ?? '';
    final (statusLabel, statusColor, statusIcon) = _statusMeta(status);
    final slaAt = dispute['sla_due_at'] as String?;
    final due = slaAt != null ? DateTime.tryParse(slaAt) : null;
    final slaExpired = due != null && due.isBefore(DateTime.now());

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Litige #${dispute['id']} — Exp. #${dispute['shipment']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  _StatusPill(label: statusLabel, color: statusColor, icon: statusIcon),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _TypeChip(type: type),
                  if (dispute['is_multi_actor'] == true) ...[
                    const SizedBox(width: 6),
                    const _SmallBadge('Multi-acteurs', Colors.orange),
                  ],
                  if (dispute['guarantee_fund_activated'] == true) ...[
                    const SizedBox(width: 6),
                    const _SmallBadge('Fonds garantie', Colors.green),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Text(
                dispute['reason'] as String? ?? '',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (due != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 13, color: slaExpired ? Colors.red : Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      slaExpired ? 'SLA depasse' : 'SLA: ${_fmtDate(due)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: slaExpired ? Colors.red : Colors.blue.shade700,
                        fontWeight: slaExpired ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  (String, Color, IconData) _statusMeta(String s) {
    switch (s) {
      case 'OPEN':               return ('Ouvert', Colors.orange, Icons.gavel_outlined);
      case 'UNDER_REVIEW':       return ('En cours', Colors.blue, Icons.manage_search_outlined);
      case 'INSPECTION_PENDING': return ('Inspection', Colors.purple, Icons.search_outlined);
      case 'APPEAL_REQUESTED':   return ('Appel', Colors.deepOrange, Icons.balance_outlined);
      case 'RESOLVED':           return ('Resolu', Colors.green, Icons.check_circle_outline);
      case 'CLOSED_NO_ACTION':   return ('Ferme', Colors.grey, Icons.cancel_outlined);
      default:                   return (s, Colors.grey, Icons.info_outline);
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Shared display widgets
// ---------------------------------------------------------------------------
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatusPill({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  static const _labels = {
    'QUALITY_DEFECT': 'Mauvaise qualite',
    'WRONG_QUANTITY': 'Quantite incomplete',
    'COUNTERFEIT': 'Contrefacon',
    'FALSE_NON_RECEIPT': 'Fausse non-reception',
    'USED_THEN_DISPUTED': 'Utilise puis conteste',
    'DELIVERY_DELAY': 'Retard livraison',
    'LOST_PARCEL': 'Colis perdu',
    'WRONG_RECIPIENT': 'Mauvais destinataire',
    'ESCROW_BLOCKED': 'Fonds bloques',
    'PREMATURE_RELEASE': 'Liberation prematuree',
    'WALLET_FROZEN': 'Wallet gele',
    'DOUBLE_CHARGE': 'Double debit',
    'WITHDRAWAL_ERROR': 'Erreur retrait',
    'CHARGEBACK': 'Chargeback',
    'FAKE_DOCUMENTS': 'Faux documents',
    'UNJUST_SUSPENSION': 'Suspension injustifiee',
    'DAMAGED_GOODS': 'Marchandise endommagee',
    'INTERNAL_THEFT': 'Vol interne',
    'FALSE_TRACKING': 'Faux suivi',
    'MISLEADING_AD': 'Pub trompeuse',
    'FAKE_STATS': 'Faux stats boost',
    'DATA_BREACH': 'Fuite donnees',
    'UNAUTHORIZED_ACCESS': 'Acces non autorise',
    'CATALOG_COPY': 'Copie catalogue',
    'FAKE_REVIEWS': 'Faux avis',
    'MODERATION_BIAS': 'Biais moderation',
    'HISTORY_TAMPER': 'Historique modifie',
    'FINANCIAL_REGULATION': 'Reglementation',
    'TAX_COMPLIANCE': 'Conformite fiscale',
    'MULTI_ACTOR': 'Multi-acteurs',
    'OTHER': 'Autre',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Text(
        _labels[type] ?? type,
        style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SmallBadge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

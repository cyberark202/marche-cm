import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import 'dispute_detail_page.dart';

// ---------------------------------------------------------------------------
// Entry point for sellers (SUPPLIER / WHOLESALER)
// ---------------------------------------------------------------------------
class SellerDisputePage extends StatefulWidget {
  const SellerDisputePage({super.key});

  @override
  State<SellerDisputePage> createState() => _SellerDisputePageState();
}

class _SellerDisputePageState extends State<SellerDisputePage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _sub;
  List<Map<String, dynamic>> _disputes = const [];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  static const _filters = [
    ('ALL', 'Tous'),
    ('OPEN', 'Ouverts'),
    ('UNDER_REVIEW', 'En cours'),
    ('RESOLVED', 'Resolus'),
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

  List<Map<String, dynamic>> get _filtered =>
      _filter == 'ALL' ? _disputes : _disputes.where((d) => d['status'] == _filter).toList();

  Future<void> _openCreate() async {
    final ctrl = TextEditingController();
    final shipmentId = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ouvrir un litige'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Numero d\'expedition',
            hintText: 'Ex: 42',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
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
        builder: (_) => _SellerDisputeCreatePage(shipmentId: shipmentId),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes litiges'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final (value, label) in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label, style: const TextStyle(fontSize: 12)),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _filtered.isEmpty
                  ? AppEmptyState(
                      title: 'Aucun litige',
                      subtitle: 'Aucun litige ouvert.',
                      onRetry: _load,
                      icon: Icons.gavel_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _SellerDisputeTile(
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
        onPressed: _openCreate,
        icon: const Icon(Icons.add),
        label: const Text('Signaler un litige'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dispute tile — shows accused party label
// ---------------------------------------------------------------------------
class _SellerDisputeTile extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onTap;
  const _SellerDisputeTile({required this.dispute, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = dispute['status'] as String? ?? '';
    final (statusLabel, statusColor, statusIcon) = _statusMeta(status);
    final accused = dispute['accused_party_display'] as Map?;
    final accusedName = accused?['username'] as String?;
    final accusedRole = accused?['role'] as String?;
    final slaAt = dispute['sla_due_at'] as String?;
    final due = slaAt != null ? DateTime.tryParse(slaAt) : null;
    final slaExpired = due != null && due.isBefore(DateTime.now());

    return Card(
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
              // Accused party badge
              if (accusedName != null)
                Row(
                  children: [
                    Icon(
                      _roleIcon(accusedRole),
                      size: 14,
                      color: _roleColor(accusedRole),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Contre : $accusedName (${_roleLabel(accusedRole)})',
                      style: TextStyle(
                        fontSize: 12,
                        color: _roleColor(accusedRole),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                dispute['reason'] as String? ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (due != null) ...[
                const SizedBox(height: 4),
                Text(
                  slaExpired ? 'SLA depasse' : 'SLA: ${_fmtDate(due)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: slaExpired ? Colors.red : Colors.blue.shade600,
                  ),
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

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'BUYER':         return Icons.person_outline;
      case 'TRANSIT_AGENT': return Icons.local_shipping_outlined;
      default:              return Icons.store_outlined;
    }
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'BUYER':         return Colors.blue.shade700;
      case 'TRANSIT_AGENT': return Colors.orange.shade700;
      default:              return Colors.grey.shade700;
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'BUYER':         return 'Acheteur';
      case 'TRANSIT_AGENT': return 'Transitaire';
      case 'SUPPLIER':      return 'Fournisseur';
      case 'WHOLESALER':    return 'Grossiste';
      default:              return role ?? '—';
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Seller-specific dispute creation — grouped by accused party
// ---------------------------------------------------------------------------
class _SellerDisputeCreatePage extends StatefulWidget {
  final int shipmentId;
  const _SellerDisputeCreatePage({required this.shipmentId});

  @override
  State<_SellerDisputeCreatePage> createState() => _SellerDisputeCreatePageState();
}

class _SellerDisputeCreatePageState extends State<_SellerDisputeCreatePage> {
  final ApiService _api = ApiService();
  final _reasonCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String? _selectedType;
  PlatformFile? _evidenceFile;
  bool _loading = false;
  int _step = 0;

  // Grouped dispute types for sellers
  static const _groupsVsBuyer = [
    ('FALSE_NON_RECEIPT',  'Fausse non-reception', Icons.gpp_bad_outlined),
    ('USED_THEN_DISPUTED', 'Produit utilise puis conteste', Icons.swap_horiz_outlined),
    ('CHARGEBACK',         'Chargeback / Contestation bancaire', Icons.money_off_outlined),
    ('FAKE_REVIEWS',       'Faux avis negatifs', Icons.thumb_down_outlined),
  ];

  static const _groupsVsTransit = [
    ('INTERNAL_THEFT',  'Vol interne par le transitaire', Icons.no_backpack_outlined),
    ('FALSE_TRACKING',  'Fausse mise a jour de suivi', Icons.location_off_outlined),
    ('DAMAGED_GOODS',   'Marchandise endommagee en transit', Icons.broken_image_outlined),
    ('LOST_PARCEL',     'Colis perdu', Icons.search_off_outlined),
    ('WRONG_RECIPIENT', 'Livre au mauvais destinataire', Icons.person_off_outlined),
  ];

  static const _groupsPlatform = [
    ('UNJUST_SUSPENSION',   'Suspension injustifiee de mon compte', Icons.block_outlined),
    ('MODERATION_BIAS',     'Biais dans la moderation', Icons.balance_outlined),
    ('ESCROW_BLOCKED',      'Fonds en escrow bloques trop longtemps', Icons.lock_outlined),
    ('WALLET_FROZEN',       'Gel de wallet injustifie', Icons.account_balance_wallet_outlined),
    ('PREMATURE_RELEASE',   'Liberation prematuree des fonds escrow', Icons.lock_open_outlined),
    ('WITHDRAWAL_ERROR',    'Erreur de retrait wallet', Icons.money_off_outlined),
    ('CATALOG_COPY',        'Copie de mon catalogue par un concurrent', Icons.content_copy_outlined),
    ('FAKE_STATS',          'Faux chiffres de boost / campagne', Icons.bar_chart_outlined),
    ('FINANCIAL_REGULATION','Activite financiere non autorisee', Icons.account_balance_outlined),
    ('TAX_COMPLIANCE',      'Non-conformite fiscale', Icons.receipt_long_outlined),
    ('OTHER',               'Autre probleme (a preciser)', Icons.help_outline),
  ];

  static const _groupsSecurity = [
    ('DATA_BREACH',        'Fuite de donnees KYC / personnelles', Icons.shield_outlined),
    ('UNAUTHORIZED_ACCESS','Acces non autorise a mon compte', Icons.no_accounts_outlined),
    ('HISTORY_TAMPER',     'Modification de mon historique', Icons.history_edu_outlined),
    ('MULTI_ACTOR',        'Responsabilite multi-acteurs indeterminee', Icons.group_work_outlined),
  ];

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _evidenceFile = result.files.first);
    }
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    final details = _detailsCtrl.text.trim();
    if (reason.length < 3) {
      _showSnack('Motif trop court', error: true);
      return;
    }
    if (details.length < 10) {
      _showSnack('Details insuffisants (min 10 car.)', error: true);
      return;
    }
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final resp = await _api.post(
        '/api/shipments/${widget.shipmentId}/open_dispute/',
        {
          'dispute_type': _selectedType!,
          'reason': reason,
          'details': details,
        },
        token: token,
      );
      final disputeId = resp['id'] as int?;
      if (_evidenceFile != null && disputeId != null) {
        await _api.postMultipart(
          '/api/shipment-disputes/$disputeId/add-evidence/',
          fields: {'evidence_type': 'DOCUMENT', 'description': ''},
          file: _evidenceFile,
          fileFieldName: 'file',
          token: token,
        );
      }
      if (!mounted) return;
      _showSnack('Litige ouvert avec succes');
      Navigator.pop(context);
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? 'Quel est le probleme ?' : 'Details du litige'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 2,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ),
      body: _step == 0 ? _buildTypeStep() : _buildDetailsStep(),
    );
  }

  Widget _buildTypeStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Expedition #${widget.shipmentId}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _GroupSection(
                title: 'Probleme avec l\'acheteur',
                icon: Icons.person_outline,
                color: Colors.blue,
                types: _groupsVsBuyer,
                selected: _selectedType,
                onSelect: (v) => setState(() => _selectedType = v),
              ),
              const SizedBox(height: 16),
              _GroupSection(
                title: 'Probleme avec le transitaire',
                icon: Icons.local_shipping_outlined,
                color: Colors.orange,
                types: _groupsVsTransit,
                selected: _selectedType,
                onSelect: (v) => setState(() => _selectedType = v),
              ),
              const SizedBox(height: 16),
              _GroupSection(
                title: 'Probleme plateforme & finances',
                icon: Icons.apps_outlined,
                color: Colors.purple,
                types: _groupsPlatform,
                selected: _selectedType,
                onSelect: (v) => setState(() => _selectedType = v),
              ),
              const SizedBox(height: 16),
              _GroupSection(
                title: 'Securite & Donnees',
                icon: Icons.shield_outlined,
                color: Colors.red,
                types: _groupsSecurity,
                selected: _selectedType,
                onSelect: (v) => setState(() => _selectedType = v),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _selectedType == null ? null : () => setState(() => _step = 1),
              child: const Text('Continuer'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsStep() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Decrivez le probleme',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motif (resume)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Details complets (min 10 car.)',
                  hintText: 'Decrivez les faits, dates, montants…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file_outlined),
                label: Text(_evidenceFile == null
                    ? 'Joindre une preuve (photo, PDF…)'
                    : _evidenceFile!.name),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'La partie accusee sera notifiee et pourra repondre. '
                        'Un admin examinera le dossier sous 72h. '
                        'Les fonds en escrow restent bloques jusqu\'a resolution.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() => _step = 0),
                child: const Text('Retour'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_loading ? 'Envoi...' : 'Soumettre le litige'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group section widget
// ---------------------------------------------------------------------------
class _GroupSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<(String, String, IconData)> types;
  final String? selected;
  final ValueChanged<String> onSelect;

  const _GroupSection({
    required this.title,
    required this.icon,
    required this.color,
    required this.types,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13, color: color)),
          ],
        ),
        const SizedBox(height: 8),
        ...types.map(
          (t) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: selected == t.$1 ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected == t.$1 ? color : Colors.grey.shade200,
                    width: selected == t.$1 ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(t.$3,
                        size: 18,
                        color: selected == t.$1 ? color : Colors.grey.shade500),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        t.$2,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected == t.$1 ? color : Colors.black87,
                          fontWeight: selected == t.$1 ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (selected == t.$1)
                      Icon(Icons.check_circle, color: color, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared status pill
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
          Text(label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

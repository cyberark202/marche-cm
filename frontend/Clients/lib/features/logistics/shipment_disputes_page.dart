import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_ui.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';

// ---------------------------------------------------------------------------
// List page
// ---------------------------------------------------------------------------
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

  List<Map<String, dynamic>> get _filtered {
    if (_statusFilter == 'ALL') return _disputes;
    return _disputes.where((d) => d['status'] == _statusFilter).toList();
  }

  Future<void> _openCreate() async {
    final token = context.read<SessionStore>().token;
    final shipmentId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ShipmentPickerSheet(token: token, api: _api),
    );
    if (shipmentId == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DisputeCreatePage(shipmentId: shipmentId),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes réclamations'),
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
                      title: 'Aucune réclamation',
                      subtitle: 'Vous n\'avez aucune réclamation ouverte.',
                      onRetry: _load,
                      icon: Icons.gavel_outlined,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _DisputeListTile(
                        dispute: _filtered[i],
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _DisputeDetailPage(
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
        label: const Text('Signaler un probleme'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List tile
// ---------------------------------------------------------------------------
class _DisputeListTile extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final VoidCallback onTap;
  const _DisputeListTile({required this.dispute, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = dispute['status'] as String? ?? '';
    final (label, color, icon) = _statusMeta(status);
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
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Réclamation #${dispute['id']} — Commande #${dispute['shipment']}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dispute['reason'] as String? ?? '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (due != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        slaExpired ? 'Délai dépassé' : 'Traité avant le ${_fmtDate(due)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: slaExpired ? Colors.red : Colors.blue.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 10, color: color, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
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
// Create page (buyer-focused, 2 steps)
// ---------------------------------------------------------------------------
class _DisputeCreatePage extends StatefulWidget {
  final int shipmentId;
  const _DisputeCreatePage({required this.shipmentId});

  @override
  State<_DisputeCreatePage> createState() => _DisputeCreatePageState();
}

class _DisputeCreatePageState extends State<_DisputeCreatePage> {
  final ApiService _api = ApiService();
  final _reasonCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  String? _selectedType;
  PlatformFile? _evidenceFile;
  bool _loading = false;
  int _step = 0;

  // Dispute types available to buyers — grouped by category for clarity.
  // Seller-against-buyer types (FALSE_NON_RECEIPT, USED_THEN_DISPUTED) are excluded.
  static const _disputeTypes = [
    // --- Probleme avec le vendeur ---
    ('QUALITY_DEFECT',    'Mauvaise qualite',           Icons.star_half_outlined,                  Color(0xFFE65100)),
    ('WRONG_QUANTITY',    'Quantite incomplete',         Icons.production_quantity_limits_outlined,  Color(0xFF6A1B9A)),
    ('COUNTERFEIT',       'Produit contrefait',          Icons.warning_amber_outlined,               Color(0xFFB71C1C)),
    ('MISLEADING_AD',     'Publicite trompeuse',         Icons.campaign_outlined,                    Color(0xFF6A1B9A)),
    ('FAKE_DOCUMENTS',    'Faux documents vendeur',      Icons.description_outlined,                 Color(0xFF880E4F)),
    // --- Livraison ---
    ('DELIVERY_DELAY',    'Retard de livraison',         Icons.access_time_outlined,                 Color(0xFF283593)),
    ('LOST_PARCEL',       'Colis perdu',                 Icons.search_off_outlined,                  Color(0xFF37474F)),
    ('DAMAGED_GOODS',     'Marchandise endommagee',      Icons.broken_image_outlined,                Color(0xFF4E342E)),
    ('WRONG_RECIPIENT',   'Livre au mauvais destinataire',Icons.person_off_outlined,                 Color(0xFF1565C0)),
    // --- Paiement & Plateforme ---
    ('DOUBLE_CHARGE',     'Double debit Mobile Money',   Icons.money_off_outlined,                   Color(0xFF00695C)),
    ('ESCROW_BLOCKED',    'Fonds bloques trop longtemps',Icons.lock_outlined,                        Color(0xFF558B2F)),
    ('WALLET_FROZEN',     'Gel de wallet injustifie',    Icons.account_balance_wallet_outlined,      Color(0xFF0277BD)),
    ('WITHDRAWAL_ERROR',  'Erreur de retrait wallet',    Icons.currency_exchange_outlined,            Color(0xFF00838F)),
    ('PREMATURE_RELEASE', 'Liberation prematuree des fonds', Icons.lock_open_outlined,               Color(0xFFE65100)),
    ('UNJUST_SUSPENSION', 'Suspension injustifiee de mon compte', Icons.block_outlined,              Color(0xFF6A1B9A)),
    // --- Securite ---
    ('DATA_BREACH',       'Fuite de mes donnees personnelles', Icons.shield_outlined,                Color(0xFFB71C1C)),
    ('UNAUTHORIZED_ACCESS','Acces non autorise a mon compte',  Icons.no_accounts_outlined,           Color(0xFFC62828)),
    // --- Autre ---
    ('OTHER',             'Autre probleme',              Icons.help_outline,                         Color(0xFF455A64)),
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
      _showSnack('Details insuffisants (min 10 caracteres)', error: true);
      return;
    }
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final body = <String, dynamic>{
        'dispute_type': _selectedType ?? 'QUALITY_DEFECT',
        'reason': reason,
        'details': details,
      };
      final resp = await _api.post(
        '/api/shipments/${widget.shipmentId}/open_dispute/',
        body,
        token: token,
      );
      final disputeId = resp['id'] as int?;
      if (_evidenceFile != null && disputeId != null) {
        await _api.postMultipart(
          '/api/shipment-disputes/$disputeId/add-evidence/',
          fields: {'evidence_type': 'PHOTO', 'description': ''},
          file: _evidenceFile,
          fileFieldName: 'file',
          token: token,
        );
      }
      if (!mounted) return;
      _showSnack('Réclamation ouverte avec succès');
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
        title: Text(_step == 0 ? 'Type de réclamation' : 'Détails'),
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
              const Text(
                'Quel est le probleme ?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Expedition #${widget.shipmentId}',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              for (final (value, label, icon, color) in _disputeTypes)
                _TypeOption(
                  value: value,
                  label: label,
                  icon: icon,
                  color: color,
                  selected: _selectedType == value,
                  onTap: () => setState(() => _selectedType = value),
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
              onPressed: _selectedType == null
                  ? null
                  : () => setState(() => _step = 1),
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
                'Decrivez votre probleme',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Motif (resume)',
                  hintText: 'Ex: Produit recu endomage',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsCtrl,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Details (min 10 car.)',
                  hintText: 'Decrivez precisément la situation…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.attach_file_outlined),
                label: Text(_evidenceFile == null
                    ? 'Joindre une photo / PDF (optionnel)'
                    : _evidenceFile!.name),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Votre réclamation sera examinée sous 72h. '
                        'Les fonds restent sécurisés jusqu\'à résolution. '
                        'Vous disposez de 48h après la décision pour faire appel.',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
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
                          child:
                              CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(_loading ? 'Envoi...' : 'Soumettre la réclamation'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TypeOption extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _TypeOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.1) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.grey.shade200,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? color : Colors.grey.shade500, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: selected ? color : Colors.black87,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (selected) Icon(Icons.check_circle, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail page (buyer view — no admin panel)
// ---------------------------------------------------------------------------
class _DisputeDetailPage extends StatefulWidget {
  final int disputeId;
  const _DisputeDetailPage({required this.disputeId});

  @override
  State<_DisputeDetailPage> createState() => _DisputeDetailPageState();
}

class _DisputeDetailPageState extends State<_DisputeDetailPage> {
  final ApiService _api = ApiService();
  final _appealCtrl = TextEditingController();
  Map<String, dynamic>? _dispute;
  bool _loading = true;
  String? _error;
  bool _appealing = false;
  bool _uploadingEvidence = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _appealCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      _dispute = await _api.getObject(
        '/api/shipment-disputes/${widget.disputeId}/',
        token: token,
      );
      _error = null;
    } catch (e) {
      _error = _api.toUserMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addEvidence() async {
    final token = context.read<SessionStore>().token;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    setState(() => _uploadingEvidence = true);
    try {
      await _api.postMultipart(
        '/api/shipment-disputes/${widget.disputeId}/add-evidence/',
        fields: {'evidence_type': 'PHOTO', 'description': ''},
        file: result.files.first,
        fileFieldName: 'file',
        token: token,
      );
      await _load();
      _showSnack('Preuve ajoutee');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _uploadingEvidence = false);
  }

  Future<void> _submitAppeal() async {
    final reason = _appealCtrl.text.trim();
    if (reason.length < 10) {
      _showSnack('Motif trop court (min 10 car.)', error: true);
      return;
    }
    setState(() => _appealing = true);
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        '/api/shipment-disputes/${widget.disputeId}/appeal/',
        {'reason': reason},
        token: token,
      );
      _appealCtrl.clear();
      await _load();
      _showSnack('Appel soumis — un admin va reexaminer votre dossier');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _appealing = false);
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
        title: Text('Réclamation #${widget.disputeId}'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _dispute == null
                  ? const SizedBox()
                  : _buildBody(),
    );
  }

  Widget _buildBody() {
    final d = _dispute!;
    final status = d['status'] as String? ?? '';
    final resolved = status == 'RESOLVED' || status == 'CLOSED_NO_ACTION';
    final evidences = (d['evidences'] as List?) ?? [];
    final (statusLabel, statusColor, statusIcon) = _statusMeta(status);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: statusColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor),
              const SizedBox(width: 10),
              Text(statusLabel,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: statusColor, fontSize: 15)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Info
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Motif', d['reason'] as String? ?? ''),
                _row('Details', d['details'] as String? ?? ''),
                _row('Expedition', '#${d['shipment']}'),
                if (d['sla_due_at'] != null)
                  _row('Délai de traitement', _fmtDate(DateTime.tryParse(d['sla_due_at'] as String))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Evidence
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: Text('Preuves (${evidences.length})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: !resolved
                    ? IconButton(
                        icon: _uploadingEvidence
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_circle_outline),
                        onPressed: _uploadingEvidence ? null : _addEvidence,
                      )
                    : null,
              ),
              if (evidences.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Text('Aucune preuve jointe.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              for (final e in evidences)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(
                    e['description']?.toString().isNotEmpty == true
                        ? e['description'] as String
                        : 'Preuve',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    'Par ${(e['uploaded_by'] ?? {})['username'] ?? '—'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Resolution
        if (resolved && d['resolution_note'] != null) ...[
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.check_circle_outline, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Decision',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  if ((d['admin_decision'] as String?) != null)
                    Chip(
                      label: Text(_decisionLabel(d['admin_decision'] as String)),
                      backgroundColor: Colors.green.shade600,
                      labelStyle:
                          const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  const SizedBox(height: 6),
                  Text(d['resolution_note'] as String? ?? '',
                      style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Appeal
        if (resolved && d['appeal_requested'] != true) ...[
          Card(
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Icon(Icons.balance_outlined, color: Colors.deepOrange),
                    SizedBox(width: 8),
                    Text('Contester la decision',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Vous avez 48h pour faire appel. Un admin different examinera votre dossier.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _appealCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Motif (min 10 car.)',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 3,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _appealing ? null : _submitAppeal,
                      icon: _appealing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_outlined),
                      label: const Text('Soumettre l\'appel'),
                      style:
                          FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (d['appeal_requested'] == true)
          Card(
            color: d['appeal_resolved_at'] != null
                ? Colors.green.shade50
                : Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(
                d['appeal_resolved_at'] != null
                    ? Icons.check_circle_outline
                    : Icons.hourglass_empty_outlined,
                color: d['appeal_resolved_at'] != null ? Colors.green : Colors.orange,
              ),
              title: Text(d['appeal_resolved_at'] != null
                  ? 'Appel tranche'
                  : 'Appel en attente d\'examen'),
              subtitle: d['appeal_decision'] != null
                  ? Text(d['appeal_decision'] as String,
                      style: const TextStyle(fontSize: 12))
                  : null,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _row(String k, String? v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(k,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Colors.grey)),
            ),
            Expanded(
              child: Text(v ?? '—', style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

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

  String _decisionLabel(String d) {
    switch (d) {
      case 'REFUND_BUYER':   return 'Rembourse';
      case 'RELEASE_SELLER': return 'Fonds liberes au vendeur';
      case 'SPLIT':          return 'Partage (Split)';
      default:               return d;
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Shipment picker bottom sheet
// ---------------------------------------------------------------------------
class _ShipmentPickerSheet extends StatefulWidget {
  final String? token;
  final ApiService api;
  const _ShipmentPickerSheet({required this.token, required this.api});

  @override
  State<_ShipmentPickerSheet> createState() => _ShipmentPickerSheetState();
}

class _ShipmentPickerSheetState extends State<_ShipmentPickerSheet> {
  List<Map<String, dynamic>> _shipments = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _shipments = await widget.api.getList('/api/shipments/', token: widget.token);
    } catch (e) {
      _error = widget.api.toUserMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  String _shipmentStatus(String s) {
    switch (s) {
      case 'PENDING':   return 'En attente';
      case 'CONFIRMED': return 'Confirmée';
      case 'SHIPPED':   return 'Expédiée';
      case 'DELIVERED': return 'Livrée';
      case 'CANCELLED': return 'Annulée';
      default:          return s;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                const Icon(Icons.local_shipping_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Sélectionnez une commande',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_outlined,
                                  color: Colors.grey, size: 40),
                              const SizedBox(height: 8),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _shipments.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      color: Colors.grey, size: 40),
                                  SizedBox(height: 8),
                                  Text('Aucune commande trouvée',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  SizedBox(height: 4),
                                  Text(
                                    'Vous n\'avez pas encore de commandes.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: _shipments.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1, indent: 16),
                            itemBuilder: (_, i) {
                              final s = _shipments[i];
                              final id = s['id'] as int? ?? 0;
                              final ref =
                                  (s['tracking_number'] as String?)?.isNotEmpty == true
                                      ? s['tracking_number'] as String
                                      : '#$id';
                              final status =
                                  _shipmentStatus(s['status'] as String? ?? '');
                              final createdAt = s['created_at'] as String?;
                              final date = createdAt != null
                                  ? DateTime.tryParse(createdAt)
                                  : null;
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFE8F5EE),
                                  child: Icon(Icons.local_shipping_outlined,
                                      color: Color(0xFF1E8E4B), size: 20),
                                ),
                                title: Text(
                                  'Commande $ref',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                ),
                                subtitle: Text(
                                  date != null
                                      ? '$status  •  ${date.day}/${date.month}/${date.year}'
                                      : status,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: const Icon(Icons.chevron_right,
                                    size: 18, color: Colors.grey),
                                onTap: () => Navigator.pop(context, id),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

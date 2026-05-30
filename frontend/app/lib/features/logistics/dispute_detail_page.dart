import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';

class DisputeDetailPage extends StatefulWidget {
  final int disputeId;
  const DisputeDetailPage({super.key, required this.disputeId});

  @override
  State<DisputeDetailPage> createState() => _DisputeDetailPageState();
}

class _DisputeDetailPageState extends State<DisputeDetailPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _sub;

  Map<String, dynamic>? _dispute;
  bool _loading = true;
  String? _error;

  // Admin decision panel
  String _adminDecision = 'REFUND_BUYER';
  final _noteCtrl = TextEditingController();
  bool _deciding = false;

  // Appeal panel
  final _appealCtrl = TextEditingController();
  bool _appealing = false;

  // Resolve appeal (admin)
  bool _resolvingAppeal = false;

  // Evidence upload
  bool _uploadingEvidence = false;

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
    _noteCtrl.dispose();
    _appealCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      _dispute = await _api.getObject('/api/shipment-disputes/${widget.disputeId}/', token: token);
      _error = null;
    } catch (e) {
      _error = _api.toUserMessage(e);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _decide(String newStatus) async {
    if (_noteCtrl.text.trim().length < 5 && newStatus == 'RESOLVED') {
      _showSnack('Note de resolution obligatoire', error: true);
      return;
    }
    setState(() => _deciding = true);
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        '/api/shipment-disputes/${widget.disputeId}/decide/',
        {
          'status': newStatus,
          'admin_decision': _adminDecision,
          'resolution_note': _noteCtrl.text.trim(),
        },
        token: token,
      );
      _noteCtrl.clear();
      await _load();
      _showSnack('Decision enregistree');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _deciding = false);
  }

  Future<void> _requestInspection() async {
    final token = context.read<SessionStore>().token;
    final note = await _promptText(
      context, 'Demande d\'inspection', 'Motif (optionnel)',
    );
    if (!mounted) return;
    try {
      await _api.post(
        '/api/shipment-disputes/${widget.disputeId}/request-inspection/',
        {'note': note ?? ''},
        token: token,
      );
      await _load();
      _showSnack('Inspection demandée — traitement prolongé de 5 jours');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
  }

  Future<void> _activateGuaranteeFund() async {
    final token = context.read<SessionStore>().token;
    final note = await _promptText(
      context, 'Fonds de garantie', 'Motif d\'activation', required: true,
    );
    if (!mounted) return;
    if (note == null || note.trim().length < 5) return;
    try {
      await _api.post(
        '/api/shipment-disputes/${widget.disputeId}/guarantee-fund/',
        {'note': note.trim()},
        token: token,
      );
      await _load();
      _showSnack('Fonds de garantie active — acheteur rembourse');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
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
      _showSnack('Appel soumis — un autre admin va examiner');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _appealing = false);
  }

  Future<void> _resolveAppeal() async {
    final token = context.read<SessionStore>().token;
    final appealDecision = await _promptText(
      context, 'Resoudre l\'appel', 'Decision sur l\'appel (obligatoire)', required: true,
    );
    if (!mounted) return;
    if (appealDecision == null || appealDecision.trim().length < 5) return;
    setState(() => _resolvingAppeal = true);
    try {
      await _api.post(
        '/api/shipment-disputes/${widget.disputeId}/resolve-appeal/',
        {
          'appeal_decision': appealDecision.trim(),
          'admin_decision': _adminDecision,
        },
        token: token,
      );
      await _load();
      _showSnack('Appel resolu');
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _resolvingAppeal = false);
  }

  Future<void> _addEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'mp4', 'mov'],
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    setState(() => _uploadingEvidence = true);
    final token = context.read<SessionStore>().token;
    try {
      await _api.postMultipart(
        '/api/shipment-disputes/${widget.disputeId}/add-evidence/',
        fields: {'evidence_type': 'DOCUMENT', 'description': ''},
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

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  Widget? _buildBottomBar(bool isAdmin) {
    if (_dispute == null || _loading || _error != null) return null;
    final status = _dispute!['status'] as String? ?? '';
    final resolved = status == 'RESOLVED' || status == 'CLOSED_NO_ACTION';
    final appealRequested = _dispute!['appeal_requested'] == true;

    if (isAdmin && (status == 'OPEN' || status == 'UNDER_REVIEW')) {
      return _StickyBar(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _deciding ? null : () => _decide('UNDER_REVIEW'),
            icon: const Icon(Icons.manage_search_outlined, size: 18),
            label: const Text('En cours'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _deciding ? null : () => _decide('RESOLVED'),
            icon: _deciding
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: const Text('Résoudre'),
          ),
        ),
      ]);
    }

    if (isAdmin && status == 'APPEAL_REQUESTED') {
      return _StickyBar(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _resolvingAppeal ? null : _resolveAppeal,
            icon: _resolvingAppeal
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.balance_outlined, size: 18),
            label: const Text("Résoudre l'appel"),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
          ),
        ),
      ]);
    }

    if (!isAdmin && resolved && !appealRequested) {
      return _StickyBar(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _appealing ? null : _submitAppeal,
            icon: _appealing
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.balance_outlined, size: 18),
            label: const Text('Faire appel'),
            style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
          ),
        ),
      ]);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final isAdmin = session.role == UserRole.generalAdmin;

    return Scaffold(
      appBar: AppBar(
        title: Text('Dossier #${widget.disputeId}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(isAdmin),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : _dispute == null
                  ? const SizedBox()
                  : _Body(
                      dispute: _dispute!,
                      isAdmin: isAdmin,
                      adminDecision: _adminDecision,
                      noteCtrl: _noteCtrl,
                      appealCtrl: _appealCtrl,
                      deciding: _deciding,
                      appealing: _appealing,
                      resolvingAppeal: _resolvingAppeal,
                      uploadingEvidence: _uploadingEvidence,
                      onDecisionChanged: (v) => setState(() => _adminDecision = v),
                      onDecide: _decide,
                      onRequestInspection: _requestInspection,
                      onActivateGuaranteeFund: _activateGuaranteeFund,
                      onSubmitAppeal: _submitAppeal,
                      onResolveAppeal: _resolveAppeal,
                      onAddEvidence: _addEvidence,
                    ),
    );
  }
}

class _StickyBar extends StatelessWidget {
  const _StickyBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(children: children),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------
class _Body extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final bool isAdmin;
  final String adminDecision;
  final TextEditingController noteCtrl;
  final TextEditingController appealCtrl;
  final bool deciding, appealing, resolvingAppeal, uploadingEvidence;
  final ValueChanged<String> onDecisionChanged;
  final ValueChanged<String> onDecide;
  final VoidCallback onRequestInspection;
  final VoidCallback onActivateGuaranteeFund;
  final VoidCallback onSubmitAppeal;
  final VoidCallback onResolveAppeal;
  final VoidCallback onAddEvidence;

  const _Body({
    required this.dispute,
    required this.isAdmin,
    required this.adminDecision,
    required this.noteCtrl,
    required this.appealCtrl,
    required this.deciding,
    required this.appealing,
    required this.resolvingAppeal,
    required this.uploadingEvidence,
    required this.onDecisionChanged,
    required this.onDecide,
    required this.onRequestInspection,
    required this.onActivateGuaranteeFund,
    required this.onSubmitAppeal,
    required this.onResolveAppeal,
    required this.onAddEvidence,
  });

  @override
  Widget build(BuildContext context) {
    final dispStatus = dispute['status'] as String? ?? '';
    final resolved = dispStatus == 'RESOLVED' || dispStatus == 'CLOSED_NO_ACTION';
    final evidences = (dispute['evidences'] as List?) ?? [];
    final guaranteeFund = dispute['guarantee_fund_activated'] == true;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // --- Status banner ---
        _StatusBanner(status: dispStatus, guaranteeFund: guaranteeFund),
        const SizedBox(height: 16),

        // --- Main info ---
        _InfoCard(dispute: dispute),
        const SizedBox(height: 12),

        // --- SLA ---
        if (dispute['sla_due_at'] != null)
          _SlaCard(slaAt: dispute['sla_due_at'] as String),
        const SizedBox(height: 12),

        // --- Custody chain (always shown) ---
        _CustodySection(shipmentId: dispute['shipment'] as int?),
        const SizedBox(height: 12),

        // --- Evidence gallery ---
        _EvidenceSection(
          evidences: evidences,
          resolved: resolved,
          uploading: uploadingEvidence,
          onAdd: onAddEvidence,
        ),
        const SizedBox(height: 12),

        // --- Appeal section (shown when resolved) ---
        if (resolved && dispute['appeal_requested'] != true)
          _AppealSection(
            ctrl: appealCtrl,
            loading: appealing,
            onSubmit: onSubmitAppeal,
          ),
        if (dispute['appeal_requested'] == true)
          _AppealStatusCard(dispute: dispute),

        const SizedBox(height: 12),

        // --- Admin panel ---
        if (isAdmin && !resolved) ...[
          _AdminPanel(
            dispute: dispute,
            adminDecision: adminDecision,
            noteCtrl: noteCtrl,
            deciding: deciding,
            resolvingAppeal: resolvingAppeal,
            onDecisionChanged: onDecisionChanged,
            onDecide: onDecide,
            onRequestInspection: onRequestInspection,
            onActivateGuaranteeFund: onActivateGuaranteeFund,
            onResolveAppeal: onResolveAppeal,
          ),
        ],
        if (resolved && dispute['resolution_note'] != null)
          _ResolutionCard(dispute: dispute),

        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status banner
// ---------------------------------------------------------------------------
class _StatusBanner extends StatelessWidget {
  final String status;
  final bool guaranteeFund;
  const _StatusBanner({required this.status, required this.guaranteeFund});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _statusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 15,
                )),
                if (guaranteeFund)
                  const Text(
                    'Fonds de garantie plateforme active',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (String, Color, IconData) _statusMeta(String s) {
    switch (s) {
      case 'OPEN':            return ('Ouvert', Colors.orange, Icons.gavel_outlined);
      case 'UNDER_REVIEW':    return ('En traitement', Colors.blue, Icons.manage_search_outlined);
      case 'INSPECTION_PENDING': return ('Inspection en cours', Colors.purple, Icons.search_outlined);
      case 'APPEAL_REQUESTED': return ('Appel en cours', Colors.deepOrange, Icons.balance_outlined);
      case 'RESOLVED':        return ('Resolu', Colors.green, Icons.check_circle_outline);
      case 'CLOSED_NO_ACTION': return ('Ferme sans action', Colors.grey, Icons.cancel_outlined);
      default:                return (s, Colors.grey, Icons.info_outline);
    }
  }
}

// ---------------------------------------------------------------------------
// Info card
// ---------------------------------------------------------------------------
class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> dispute;
  const _InfoCard({required this.dispute});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Type', _typeLabel(dispute['dispute_type'] as String? ?? '')),
            _row('Motif', dispute['reason'] as String? ?? ''),
            _row('Details', dispute['details'] as String? ?? ''),
            _row('Ouvert par', (dispute['opened_by_display'] as Map?)?['username'] as String? ?? '—'),
            _row('Expedition', '#${dispute['shipment']}'),
            if (dispute['is_multi_actor'] == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Chip(
                  label: Text('Multi-acteurs', style: TextStyle(fontSize: 12)),
                  backgroundColor: Colors.orange,
                  labelStyle: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(k, style: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey,
          )),
        ),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  String _typeLabel(String t) {
    const labels = {
      'QUALITY_DEFECT': 'Mauvaise qualite', 'WRONG_QUANTITY': 'Quantite incomplete',
      'COUNTERFEIT': 'Produit contrefait', 'FALSE_NON_RECEIPT': 'Fausse non-reception',
      'USED_THEN_DISPUTED': 'Produit utilise puis conteste', 'DELIVERY_DELAY': 'Retard livraison',
      'LOST_PARCEL': 'Colis perdu', 'WRONG_RECIPIENT': 'Mauvais destinataire',
      'ESCROW_BLOCKED': 'Fonds bloques', 'PREMATURE_RELEASE': 'Liberation prematuree',
      'WALLET_FROZEN': 'Wallet gele', 'DOUBLE_CHARGE': 'Double debit',
      'WITHDRAWAL_ERROR': 'Erreur retrait', 'CHARGEBACK': 'Chargeback',
      'FAKE_DOCUMENTS': 'Faux documents', 'UNJUST_SUSPENSION': 'Suspension injustifiee',
      'DAMAGED_GOODS': 'Marchandise endommagee', 'INTERNAL_THEFT': 'Vol interne',
      'FALSE_TRACKING': 'Fausse mise a jour suivi', 'MISLEADING_AD': 'Publicite trompeuse',
      'FAKE_STATS': 'Faux chiffres boost', 'DATA_BREACH': 'Fuite donnees KYC',
      'UNAUTHORIZED_ACCESS': 'Acces non autorise', 'CATALOG_COPY': 'Copie catalogue',
      'FAKE_REVIEWS': 'Faux avis', 'MODERATION_BIAS': 'Favoritisme moderation',
      'HISTORY_TAMPER': 'Historique modifie', 'FINANCIAL_REGULATION': 'Reglementation financiere',
      'TAX_COMPLIANCE': 'Non-conformite fiscale', 'MULTI_ACTOR': 'Multi-acteurs',
    };
    return labels[t] ?? t;
  }
}

// ---------------------------------------------------------------------------
// SLA card
// ---------------------------------------------------------------------------
class _SlaCard extends StatelessWidget {
  final String slaAt;
  const _SlaCard({required this.slaAt});

  @override
  Widget build(BuildContext context) {
    final due = DateTime.tryParse(slaAt);
    final remaining = due?.difference(DateTime.now());
    final expired = remaining != null && remaining.isNegative;
    return Card(
      color: expired ? Colors.red.shade50 : Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: Icon(
          Icons.timer_outlined,
          color: expired ? Colors.red : Colors.blue,
        ),
        title: Text(
          expired ? 'Délai de traitement dépassé' : 'Réponse dans ${_formatRemaining(remaining!)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: expired ? Colors.red : Colors.blue.shade800,
          ),
        ),
        subtitle: Text('Avant le ${_formatDate(due)}'),
      ),
    );
  }

  String _formatRemaining(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}min';
    return '${d.inMinutes}min';
  }

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    return '${d.day}/${d.month}/${d.year} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Custody chain section
// ---------------------------------------------------------------------------
class _CustodySection extends StatefulWidget {
  final int? shipmentId;
  const _CustodySection({this.shipmentId});

  @override
  State<_CustodySection> createState() => _CustodySectionState();
}

class _CustodySectionState extends State<_CustodySection> {
  // Loaded via parent dispute's custody-chain endpoint
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: const Icon(Icons.route_outlined),
        title: const Text('Chaine de garde', style: TextStyle(fontWeight: FontWeight.w600)),
        onExpansionChanged: (v) => setState(() => _expanded = v),
        children: [
          if (_expanded) _CustodyChainLoader(shipmentId: widget.shipmentId),
        ],
      ),
    );
  }
}

class _CustodyChainLoader extends StatefulWidget {
  final int? shipmentId;
  const _CustodyChainLoader({this.shipmentId});

  @override
  State<_CustodyChainLoader> createState() => _CustodyChainLoaderState();
}

class _CustodyChainLoaderState extends State<_CustodyChainLoader> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Use dispute custody-chain endpoint (passed via parent's dispute context)
    // We search for events matching the shipment
    final token = context.read<SessionStore>().token;
    try {
      final resp = await _api.getList(
        '/api/shipments/${widget.shipmentId}/log-custody/',
        token: token,
      );
      _events = resp;
    } catch (_) {
      _events = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
      padding: EdgeInsets.all(16),
      child: CircularProgressIndicator(),
    );
    }
    if (_events.isEmpty) {
      return const Padding(
      padding: EdgeInsets.all(16),
      child: Text('Aucun evenement de garde enregistre.',
          style: TextStyle(color: Colors.grey)),
    );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _events.length,
      itemBuilder: (_, i) {
        final e = _events[i];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.circle, size: 10, color: Colors.blue),
          title: Text(_eventLabel(e['event_type'] as String? ?? ''),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${(e['actor_display'] as Map?)?['username'] ?? '—'} — ${e['location'] ?? ''}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Text(_shortDate(e['scanned_at'] as String?),
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        );
      },
    );
  }

  String _eventLabel(String t) {
    const m = {
      'PICKUP': 'Prise en charge', 'WAREHOUSE_IN': 'Entree entrepot',
      'WAREHOUSE_OUT': 'Sortie entrepot', 'HANDOVER': 'Transfert de garde',
      'OUT_FOR_DELIVERY': 'Depart livraison', 'DELIVERED': 'Livre',
    };
    return m[t] ?? t;
  }

  String _shortDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '—';
    return '${d.day}/${d.month} ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Evidence section
// ---------------------------------------------------------------------------
class _EvidenceSection extends StatelessWidget {
  final List evidences;
  final bool resolved, uploading;
  final VoidCallback onAdd;

  const _EvidenceSection({
    required this.evidences,
    required this.resolved,
    required this.uploading,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.attach_file_outlined),
            title: Text('Preuves (${evidences.length})',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: !resolved
                ? IconButton(
                    icon: uploading
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                    onPressed: uploading ? null : onAdd,
                    tooltip: 'Ajouter une preuve',
                  )
                : null,
          ),
          if (evidences.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Aucune preuve jointe.', style: TextStyle(color: Colors.grey)),
            ),
          for (final e in evidences)
            ListTile(
              dense: true,
              leading: _typeIcon(e['evidence_type'] as String? ?? ''),
              title: Text(
                e['description']?.toString().isNotEmpty == true
                    ? e['description'] as String
                    : _typeLabel(e['evidence_type'] as String? ?? ''),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                'Par ${(e['uploaded_by'] ?? {})['username'] ?? '—'} — '
                '${_formatBytes(e['file_size_bytes'] as int? ?? 0)}',
                style: const TextStyle(fontSize: 11),
              ),
              trailing: Text(
                e['file_integrity_hash'] != null
                    ? 'SHA256: ${(e['file_integrity_hash'] as String).substring(0, 8)}…'
                    : '',
                style: const TextStyle(fontSize: 9, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeIcon(String t) {
    switch (t) {
      case 'PHOTO': return const Icon(Icons.image_outlined, color: Colors.blue);
      case 'VIDEO': return const Icon(Icons.videocam_outlined, color: Colors.purple);
      case 'INSPECTION_REPORT': return const Icon(Icons.fact_check_outlined, color: Colors.green);
      default: return const Icon(Icons.insert_drive_file_outlined);
    }
  }

  String _typeLabel(String t) {
    const m = {
      'PHOTO': 'Photo', 'VIDEO': 'Video', 'DOCUMENT': 'Document',
      'SCREENSHOT': "Capture d'ecran", 'INSPECTION_REPORT': "Rapport d'inspection",
    };
    return m[t] ?? t;
  }

  String _formatBytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} Ko';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

// ---------------------------------------------------------------------------
// Appeal section
// ---------------------------------------------------------------------------
class _AppealSection extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onSubmit;

  const _AppealSection({required this.ctrl, required this.loading, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.balance_outlined, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text('Contester la decision',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Vous avez 48h apres la decision pour faire appel. '
              'Un admin different de celui ayant statue examinera votre demande.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'Motif de l\'appel (min 10 car.)',
                border: OutlineInputBorder(),
              ),
              minLines: 3,
              maxLines: 5,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: loading ? null : onSubmit,
                icon: loading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_outlined),
                label: const Text('Soumettre l\'appel'),
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appeal status
// ---------------------------------------------------------------------------
class _AppealStatusCard extends StatelessWidget {
  final Map<String, dynamic> dispute;
  const _AppealStatusCard({required this.dispute});

  @override
  Widget build(BuildContext context) {
    final resolved = dispute['appeal_resolved_at'] != null;
    return Card(
      color: resolved ? Colors.green.shade50 : Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          resolved ? Icons.check_circle_outline : Icons.hourglass_empty_outlined,
          color: resolved ? Colors.green : Colors.orange,
        ),
        title: Text(resolved ? 'Appel tranche' : 'Appel en attente d\'examen'),
        subtitle: resolved && dispute['appeal_decision'] != null
            ? Text(dispute['appeal_decision'] as String, style: const TextStyle(fontSize: 12))
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin panel
// ---------------------------------------------------------------------------
class _AdminPanel extends StatelessWidget {
  final Map<String, dynamic> dispute;
  final String adminDecision;
  final TextEditingController noteCtrl;
  final bool deciding;
  final bool resolvingAppeal;
  final ValueChanged<String> onDecisionChanged;
  final ValueChanged<String> onDecide;
  final VoidCallback onRequestInspection;
  final VoidCallback onActivateGuaranteeFund;
  final VoidCallback onResolveAppeal;

  const _AdminPanel({
    required this.dispute,
    required this.adminDecision,
    required this.noteCtrl,
    required this.deciding,
    required this.resolvingAppeal,
    required this.onDecisionChanged,
    required this.onDecide,
    required this.onRequestInspection,
    required this.onActivateGuaranteeFund,
    required this.onResolveAppeal,
  });

  @override
  Widget build(BuildContext context) {
    final status = dispute['status'] as String? ?? '';
    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.admin_panel_settings_outlined, color: Colors.blue),
                SizedBox(width: 8),
                Text('Panneau administrateur',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 16),
            // Decision selector
            DropdownButtonFormField<String>(
              initialValue: adminDecision,
              decoration: const InputDecoration(
                labelText: 'Decision',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'REFUND_BUYER', child: Text('Rembourser l\'acheteur')),
                DropdownMenuItem(value: 'RELEASE_SELLER', child: Text('Liberer les fonds au vendeur')),
                DropdownMenuItem(value: 'SPLIT', child: Text('Partage (Split)')),
              ],
              onChanged: (v) { if (v != null) onDecisionChanged(v); },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note de resolution (obligatoire)',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: deciding ? null : () => onDecide('UNDER_REVIEW'),
                    icon: const Icon(Icons.manage_search_outlined, size: 18),
                    label: const Text('En cours'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: deciding ? null : () => onDecide('RESOLVED'),
                    icon: deciding
                        ? const SizedBox(width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Resoudre'),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            // Inspection & Guarantee fund
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: dispute['inspection_required'] == true
                        ? null : onRequestInspection,
                    icon: const Icon(Icons.search_outlined, size: 18),
                    label: const Text('Inspection', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: dispute['guarantee_fund_activated'] == true
                        ? null : onActivateGuaranteeFund,
                    icon: const Icon(Icons.shield_outlined, size: 18),
                    label: const Text('Fonds garantie', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
                  ),
                ),
              ],
            ),
            if (status == 'INSPECTION_PENDING')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Inspection demandée — traitement prolongé de 5 jours',
                  style: TextStyle(fontSize: 12, color: Colors.purple),
                ),
              ),
            if (status == 'APPEAL_REQUESTED') ...[
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: resolvingAppeal ? null : onResolveAppeal,
                  icon: resolvingAppeal
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.balance_outlined, size: 18),
                  label: const Text('Resoudre l\'appel'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Resolution card
// ---------------------------------------------------------------------------
class _ResolutionCard extends StatelessWidget {
  final Map<String, dynamic> dispute;
  const _ResolutionCard({required this.dispute});

  @override
  Widget build(BuildContext context) {
    final dec = dispute['admin_decision'] as String? ?? '';
    return Card(
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green),
                SizedBox(width: 8),
                Text('Resolution', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            if (dec.isNotEmpty) Chip(
              label: Text(_decisionLabel(dec)),
              backgroundColor: _decisionColor(dec),
              labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(dispute['resolution_note'] as String? ?? '',
                style: const TextStyle(fontSize: 13)),
            if (dispute['decided_by_display'] != null) ...[
              const SizedBox(height: 6),
              Text(
                'Tranche par: ${(dispute['decided_by_display'] as Map?)?['username'] ?? '—'}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _decisionLabel(String d) {
    switch (d) {
      case 'REFUND_BUYER': return 'Acheteur rembourse';
      case 'RELEASE_SELLER': return 'Fonds liberes au vendeur';
      case 'SPLIT': return 'Partage (Split)';
      default: return d;
    }
  }

  Color _decisionColor(String d) {
    switch (d) {
      case 'REFUND_BUYER': return Colors.blue.shade600;
      case 'RELEASE_SELLER': return Colors.green.shade600;
      default: return Colors.orange.shade600;
    }
  }
}

// ---------------------------------------------------------------------------
// Helper: prompt text dialog
// ---------------------------------------------------------------------------
Future<String?> _promptText(
  BuildContext context,
  String title,
  String hint, {
  bool required = false,
}) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: hint, border: const OutlineInputBorder()),
        minLines: 2,
        maxLines: 4,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(
          onPressed: () {
            if (required && ctrl.text.trim().length < 5) return;
            Navigator.pop(context, ctrl.text.trim());
          },
          child: const Text('Confirmer'),
        ),
      ],
    ),
  );
}

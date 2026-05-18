import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

// ---------------------------------------------------------------------------
// Dispute type catalog — mirrors backend DisputeType
// ---------------------------------------------------------------------------
class DisputeTypeInfo {
  final String value;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const DisputeTypeInfo({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

const _disputeTypes = [
  // Qualite produit
  DisputeTypeInfo(
    value: 'QUALITY_DEFECT',
    label: 'Mauvaise qualite',
    description: 'Marchandise non conforme aux photos ou specifications annoncees',
    icon: Icons.warning_amber_rounded,
    color: Color(0xFFE67E22),
  ),
  DisputeTypeInfo(
    value: 'WRONG_QUANTITY',
    label: 'Quantite incomplete',
    description: 'Moins de produits recus que commandes',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF8E44AD),
  ),
  DisputeTypeInfo(
    value: 'COUNTERFEIT',
    label: 'Produit contrefait',
    description: 'Article presenté comme original mais identifie comme une copie',
    icon: Icons.gpp_bad_outlined,
    color: Color(0xFFC0392B),
  ),
  // Mauvaise foi
  DisputeTypeInfo(
    value: 'FALSE_NON_RECEIPT',
    label: 'Fausse non-reception',
    description: 'Le colis a ete livre mais l\'acheteur nie l\'avoir recu',
    icon: Icons.block_outlined,
    color: Color(0xFFE74C3C),
  ),
  DisputeTypeInfo(
    value: 'USED_THEN_DISPUTED',
    label: 'Produit utilise puis conteste',
    description: 'Utilisation du produit avant d\'ouvrir un litige',
    icon: Icons.history_outlined,
    color: Color(0xFF7F8C8D),
  ),
  // Livraison
  DisputeTypeInfo(
    value: 'DELIVERY_DELAY',
    label: 'Retard de livraison',
    description: 'Livraison apres la date convenue causant une perte financiere',
    icon: Icons.schedule_outlined,
    color: Color(0xFF2980B9),
  ),
  DisputeTypeInfo(
    value: 'LOST_PARCEL',
    label: 'Colis perdu',
    description: 'La marchandise a disparu pendant le transport',
    icon: Icons.search_off_outlined,
    color: Color(0xFF2C3E50),
  ),
  DisputeTypeInfo(
    value: 'WRONG_RECIPIENT',
    label: 'Mauvais destinataire',
    description: 'La commande a ete remise a une autre personne',
    icon: Icons.person_off_outlined,
    color: Color(0xFF16A085),
  ),
  // Escrow
  DisputeTypeInfo(
    value: 'ESCROW_BLOCKED',
    label: 'Fonds bloques',
    description: 'Fonds en escrow bloques depuis plus de 14 jours sans raison',
    icon: Icons.lock_clock_outlined,
    color: Color(0xFF1ABC9C),
  ),
  DisputeTypeInfo(
    value: 'PREMATURE_RELEASE',
    label: 'Liberation prematuree',
    description: 'Les fonds ont ete liberes avant la confirmation de livraison',
    icon: Icons.lock_open_outlined,
    color: Color(0xFFD35400),
  ),
  DisputeTypeInfo(
    value: 'WALLET_FROZEN',
    label: 'Wallet gele',
    description: 'Compte wallet suspendu sans notification ni motif clair',
    icon: Icons.account_balance_wallet_outlined,
    color: Color(0xFF2980B9),
  ),
  // Financiers
  DisputeTypeInfo(
    value: 'DOUBLE_CHARGE',
    label: 'Double debit Mobile Money',
    description: 'Compte debite deux fois pour un seul paiement',
    icon: Icons.money_off_outlined,
    color: Color(0xFFE74C3C),
  ),
  DisputeTypeInfo(
    value: 'WITHDRAWAL_ERROR',
    label: 'Erreur de retrait',
    description: 'Retrait marque reussi mais aucun montant recu',
    icon: Icons.sync_problem_outlined,
    color: Color(0xFFF39C12),
  ),
  DisputeTypeInfo(
    value: 'CHARGEBACK',
    label: 'Chargeback bancaire',
    description: 'Annulation bancaire Visa apres livraison effective',
    icon: Icons.credit_card_off_outlined,
    color: Color(0xFF8E44AD),
  ),
  // KYC
  DisputeTypeInfo(
    value: 'FAKE_DOCUMENTS',
    label: 'Faux documents',
    description: 'Vendeur utilisant une fausse identite ou un faux RCCM',
    icon: Icons.badge_outlined,
    color: Color(0xFFC0392B),
  ),
  DisputeTypeInfo(
    value: 'UNJUST_SUSPENSION',
    label: 'Suspension injustifiee',
    description: 'Compte desactive sans explication ni procedure',
    icon: Icons.person_remove_outlined,
    color: Color(0xFF7F8C8D),
  ),
  // Logistique
  DisputeTypeInfo(
    value: 'DAMAGED_GOODS',
    label: 'Marchandise endommagee',
    description: 'Produits endommages durant le transport',
    icon: Icons.broken_image_outlined,
    color: Color(0xFFE67E22),
  ),
  DisputeTypeInfo(
    value: 'INTERNAL_THEFT',
    label: 'Vol interne',
    description: 'Disparition de marchandise avec scelles forces',
    icon: Icons.security_outlined,
    color: Color(0xFF922B21),
  ),
  DisputeTypeInfo(
    value: 'FALSE_TRACKING',
    label: 'Fausse mise a jour suivi',
    description: 'Statut "arrive" mais colis introuvable physiquement',
    icon: Icons.location_off_outlined,
    color: Color(0xFF2C3E50),
  ),
  // Publicite
  DisputeTypeInfo(
    value: 'MISLEADING_AD',
    label: 'Publicite trompeuse',
    description: 'Produits livres differents des images sponsorisees',
    icon: Icons.ads_click_outlined,
    color: Color(0xFFE67E22),
  ),
  DisputeTypeInfo(
    value: 'FAKE_STATS',
    label: 'Faux chiffres boost',
    description: 'Statistiques de campagne incoherentes avec le trafic reel',
    icon: Icons.bar_chart_outlined,
    color: Color(0xFF7F8C8D),
  ),
  // Donnees
  DisputeTypeInfo(
    value: 'DATA_BREACH',
    label: 'Fuite de donnees KYC',
    description: 'Informations personnelles KYC utilisees de maniere suspecte',
    icon: Icons.privacy_tip_outlined,
    color: Color(0xFFC0392B),
  ),
  DisputeTypeInfo(
    value: 'UNAUTHORIZED_ACCESS',
    label: 'Acces non autorise',
    description: 'Acces au compte par une personne non autorisee',
    icon: Icons.no_accounts_outlined,
    color: Color(0xFF922B21),
  ),
  // Entre vendeurs
  DisputeTypeInfo(
    value: 'CATALOG_COPY',
    label: 'Copie de catalogue',
    description: 'Photos et descriptions copiees sans autorisation',
    icon: Icons.copy_outlined,
    color: Color(0xFF1ABC9C),
  ),
  DisputeTypeInfo(
    value: 'FAKE_REVIEWS',
    label: 'Faux avis negatifs',
    description: 'Avis frauduleux pour nuire a la reputation',
    icon: Icons.thumb_down_outlined,
    color: Color(0xFF7F8C8D),
  ),
  // Internes
  DisputeTypeInfo(
    value: 'MODERATION_BIAS',
    label: 'Favoritisme moderation',
    description: 'Decision admin suspected de traitement preferentiel',
    icon: Icons.balance_outlined,
    color: Color(0xFF8E44AD),
  ),
  DisputeTypeInfo(
    value: 'HISTORY_TAMPER',
    label: 'Historique modifie',
    description: 'Messages du chat disparus apres l\'ouverture du litige',
    icon: Icons.history_edu_outlined,
    color: Color(0xFF922B21),
  ),
  // Reglementaires
  DisputeTypeInfo(
    value: 'FINANCIAL_REGULATION',
    label: 'Activite non autorisee',
    description: 'Contestation reglementaire sur le systeme wallet/escrow',
    icon: Icons.account_balance_outlined,
    color: Color(0xFF2C3E50),
  ),
  DisputeTypeInfo(
    value: 'TAX_COMPLIANCE',
    label: 'Non-conformite fiscale',
    description: 'Contestation sur la declaration des commissions et transactions',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFF7F8C8D),
  ),
  // Multi-acteurs
  DisputeTypeInfo(
    value: 'MULTI_ACTOR',
    label: 'Multi-acteurs',
    description: 'Aucun acteur n\'accepte la responsabilite — arbitrage necessaire',
    icon: Icons.group_outlined,
    color: Color(0xFF2C3E50),
  ),
  // Autre
  DisputeTypeInfo(
    value: 'OTHER',
    label: 'Autre',
    description: 'Probleme non liste ci-dessus — a preciser dans les details',
    icon: Icons.help_outline,
    color: Color(0xFF607D8B),
  ),
];

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
class DisputeCreatePage extends StatefulWidget {
  final int shipmentId;
  final String? defaultReason;

  const DisputeCreatePage({
    super.key,
    required this.shipmentId,
    this.defaultReason,
  });

  @override
  State<DisputeCreatePage> createState() => _DisputeCreatePageState();
}

class _DisputeCreatePageState extends State<DisputeCreatePage> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();

  int _step = 0; // 0=type, 1=details, 2=evidence
  DisputeTypeInfo? _selectedType;
  final List<PlatformFile> _evidenceFiles = [];
  String? _evidenceDescription;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.defaultReason != null) {
      _reasonCtrl.text = widget.defaultReason!;
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _detailsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'mp4', 'mov'],
    );
    if (result != null) {
      setState(() => _evidenceFiles.addAll(result.files));
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final token = context.read<SessionStore>().token;
    try {
      final resp = await _api.post(
        '/api/shipments/${widget.shipmentId}/open_dispute/',
        {
          'dispute_type': _selectedType!.value,
          'reason': _reasonCtrl.text.trim(),
          'details': _detailsCtrl.text.trim(),
        },
        token: token,
      );
      final disputeId = resp['id'] as int?;

      // Upload evidence files if any
      if (disputeId != null && _evidenceFiles.isNotEmpty) {
        for (final f in _evidenceFiles) {
          try {
            await _api.postMultipart(
              '/api/shipment-disputes/$disputeId/add-evidence/',
              fields: {
                'evidence_type': _inferEvidenceType(f.extension ?? ''),
                'description': _evidenceDescription ?? '',
              },
              file: f,
              fileFieldName: 'file',
              token: token,
            );
          } catch (_) {}
        }
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _submitting = false;
      });
    }
  }

  String _inferEvidenceType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
        return 'PHOTO';
      case 'mp4':
      case 'mov':
        return 'VIDEO';
      default:
        return 'DOCUMENT';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ouvrir un litige'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_step + 1) / 3,
            backgroundColor: Colors.grey.shade200,
          ),
        ),
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _step == 0
              ? _TypeStep(
                  key: const ValueKey(0),
                  onSelected: (t) => setState(() {
                    _selectedType = t;
                    _step = 1;
                  }),
                )
              : _step == 1
                  ? _DetailsStep(
                      key: const ValueKey(1),
                      type: _selectedType!,
                      formKey: _formKey,
                      reasonCtrl: _reasonCtrl,
                      detailsCtrl: _detailsCtrl,
                      error: _error,
                      onBack: () => setState(() => _step = 0),
                      onNext: () {
                        if (_formKey.currentState!.validate()) {
                          setState(() => _step = 2);
                        }
                      },
                    )
                  : _EvidenceStep(
                      key: const ValueKey(2),
                      type: _selectedType!,
                      files: _evidenceFiles,
                      submitting: _submitting,
                      error: _error,
                      onPickFiles: _pickEvidence,
                      onRemoveFile: (i) => setState(() => _evidenceFiles.removeAt(i)),
                      onDescriptionChanged: (v) => _evidenceDescription = v,
                      onBack: () => setState(() => _step = 1),
                      onSubmit: _submit,
                    ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 0: Type selector
// ---------------------------------------------------------------------------
class _TypeStep extends StatelessWidget {
  final ValueChanged<DisputeTypeInfo> onSelected;
  const _TypeStep({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Quel est le probleme ?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: _disputeTypes.length,
            itemBuilder: (context, i) {
              final t = _disputeTypes[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: t.color.withValues(alpha:0.12),
                    child: Icon(t.icon, color: t.color, size: 22),
                  ),
                  title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(t.description, style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onSelected(t),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Details form
// ---------------------------------------------------------------------------
class _DetailsStep extends StatelessWidget {
  final DisputeTypeInfo type;
  final GlobalKey<FormState> formKey;
  final TextEditingController reasonCtrl;
  final TextEditingController detailsCtrl;
  final String? error;
  final VoidCallback onBack;
  final VoidCallback onNext;

  const _DetailsStep({
    super.key,
    required this.type,
    required this.formKey,
    required this.reasonCtrl,
    required this.detailsCtrl,
    this.error,
    required this.onBack,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Type badge
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: type.color.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: type.color.withValues(alpha:0.3)),
            ),
            child: Row(
              children: [
                Icon(type.icon, color: type.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(type.label, style: TextStyle(
                        fontWeight: FontWeight.bold, color: type.color,
                      )),
                      Text(type.description, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: reasonCtrl,
            decoration: const InputDecoration(
              labelText: 'Motif (resume)',
              hintText: 'Ex: Sacs de riz humides, qualite grade B recu',
              border: OutlineInputBorder(),
            ),
            maxLength: 200,
            validator: (v) => (v ?? '').trim().length < 3 ? 'Motif trop court' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: detailsCtrl,
            decoration: const InputDecoration(
              labelText: 'Details complets',
              hintText: 'Decrivez precisement la situation, les quantites, les dates...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            validator: (v) => (v ?? '').trim().length < 10 ? 'Ajoutez plus de details' : null,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Retour'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continuer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Evidence upload
// ---------------------------------------------------------------------------
class _EvidenceStep extends StatelessWidget {
  final DisputeTypeInfo type;
  final List<PlatformFile> files;
  final bool submitting;
  final String? error;
  final VoidCallback onPickFiles;
  final ValueChanged<int> onRemoveFile;
  final ValueChanged<String> onDescriptionChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;

  const _EvidenceStep({
    super.key,
    required this.type,
    required this.files,
    required this.submitting,
    this.error,
    required this.onPickFiles,
    required this.onRemoveFile,
    required this.onDescriptionChanged,
    required this.onBack,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Preuves (optionnel)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Photos, videos, documents ou captures d\'ecran supportant votre litige. Formats: JPG, PNG, PDF, MP4 (max 50 Mo)',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: onPickFiles,
          icon: const Icon(Icons.attach_file),
          label: const Text('Ajouter des fichiers'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        if (files.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (int i = 0; i < files.length; i++)
            Card(
              child: ListTile(
                leading: _fileIcon(files[i].extension ?? ''),
                title: Text(files[i].name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(_formatSize(files[i].size)),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => onRemoveFile(i),
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Description des preuves (optionnel)',
              border: OutlineInputBorder(),
            ),
            maxLength: 300,
            onChanged: onDescriptionChanged,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: submitting ? null : onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour'),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: submitting ? null : onSubmit,
              icon: submitting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.gavel),
              label: Text(submitting ? 'Envoi...' : 'Soumettre le litige'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: const Text(
            'Les fonds en escrow seront immediatement geles a l\'ouverture du litige. '
            'L\'historique des messages sera verrouille pour eviter toute modification.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _fileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Icon(Icons.image_outlined, color: Colors.blue);
      case 'pdf':
        return const Icon(Icons.picture_as_pdf_outlined, color: Colors.red);
      case 'mp4':
      case 'mov':
        return const Icon(Icons.videocam_outlined, color: Colors.purple);
      default:
        return const Icon(Icons.insert_drive_file_outlined);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

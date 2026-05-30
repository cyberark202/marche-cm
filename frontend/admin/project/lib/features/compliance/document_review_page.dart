import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

/// Screen 36 — Document review: preview, verification checklist, decision.
class DocumentReviewPage extends StatefulWidget {
  const DocumentReviewPage({
    super.key,
    required this.document,
    required this.userName,
  });
  final Map<String, dynamic> document;
  final String userName;

  @override
  State<DocumentReviewPage> createState() => _DocumentReviewPageState();
}

class _DocumentReviewPageState extends State<DocumentReviewPage> {
  final _repo = AdminRepository.instance;
  final _comment = TextEditingController();
  bool _submitting = false;

  final Map<String, bool> _checks = {
    'Document lisible': false,
    'Tampons officiels visibles': false,
    'Date de validité OK': false,
    'Identité concorde avec le compte': false,
    'Adresse cohérente': false,
  };

  bool get _allChecked => _checks.values.every((v) => v);

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _decide(String status) async {
    final id = widget.document['id'];
    if (id is! int || _submitting) return;
    if (status == 'APPROVED' && !_allChecked) {
      showSnack(context,
          'Cochez toutes les vérifications avant de valider le document.');
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.reviewDocument(id, status);
      if (!mounted) return;
      showSnack(context,
          status == 'APPROVED' ? 'Document validé.' : 'Document rejeté.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final previewUrl =
        '${doc['preview_url'] ?? doc['file_url'] ?? ''}'.trim();
    final status = '${doc['status']}';
    return Scaffold(
      appBar: AppBar(title: const Text('Revue KYC')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          Text(widget.userName,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${doc['doc_type'] ?? 'Document'}',
                  style: const TextStyle(color: AppPalette.textMuted)),
              const Spacer(),
              StatusPill(
                status == 'PENDING' ? 'EN ATTENTE' : status,
                color: status == 'APPROVED'
                    ? AppPalette.success
                    : status == 'REJECTED'
                        ? AppPalette.danger
                        : AppPalette.warning,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _preview(previewUrl),
          const SizedBox(height: 16),
          const SectionLabel('Vérifications'),
          SectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                for (final entry in _checks.entries)
                  CheckboxListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8),
                    controlAffinity: ListTileControlAffinity.leading,
                    value: entry.value,
                    title: Text(entry.key,
                        style: const TextStyle(fontSize: 13.5)),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() => _checks[entry.key] = v ?? false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionLabel('Commentaire interne'),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'Ex : adresse fournie diffère du registre, demander une preuve…',
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _submitting ? null : () => _decide('REJECTED'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.danger,
                  side: const BorderSide(color: AppPalette.danger),
                ),
                icon: const Icon(Icons.close),
                label: const Text('Rejeter'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _submitting ? null : () => _decide('APPROVED'),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.check),
                label: const Text('Valider'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(String url) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: url.isEmpty
              ? _previewPlaceholder('Aperçu indisponible')
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      _previewPlaceholder('Document non affichable'),
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
    );
  }

  Widget _previewPlaceholder(String label) {
    return Container(
      color: AppPalette.bgSoft,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_outlined, size: 40, color: Colors.black26),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppPalette.textMuted)),
        ],
      ),
    );
  }
}

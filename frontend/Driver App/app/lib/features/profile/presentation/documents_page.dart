import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

// Audit ref: [Front-Driver] backend exposes /api/compliance-documents/
// (config/urls.py:65). The /api/accounts/compliance-documents/ path does
// not exist server-side.
final _docsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/compliance-documents/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

class DocumentsPage extends ConsumerStatefulWidget {
  const DocumentsPage({super.key});

  @override
  ConsumerState<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends ConsumerState<DocumentsPage> {
  bool _uploading = false;

  Future<void> _upload(String docType) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.path == null) return;

    setState(() => _uploading = true);
    try {
      final form = FormData.fromMap({
        'doc_type': docType,
        'file': await MultipartFile.fromFile(file.path!, filename: file.name),
      });
      await DriverDioClient.dio.post('/api/compliance-documents/', data: form);
      ref.invalidate(_docsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document envoyé pour vérification.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiError.friendly(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(_docsProvider);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Mes documents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_docsProvider),
          ),
        ],
      ),
      body: docsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(_docsProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (docs) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_uploading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              const Text(
                'Vos documents sont vérifiés par notre équipe. Un document valide est requis pour recevoir des missions.',
                style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 20),
              if (docs.isEmpty) ...[
                const _EmptyDocs(),
                const SizedBox(height: 24),
              ] else
                ...docs.map((d) => _DocCard(doc: d)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _uploading ? null : () => _upload('CNI'),
                icon: const Icon(Icons.add_card),
                label: const Text('Ajouter un document'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final Map<String, dynamic> doc;
  const _DocCard({required this.doc});

  static const _statusInfo = {
    'PENDING': ('En attente', Color(0xFFF59E0B), Icons.hourglass_empty),
    'APPROVED': ('Approuvé', Color(0xFF10B981), Icons.check_circle_outline),
    'REJECTED': ('Rejeté', Color(0xFFDC2626), Icons.cancel_outlined),
  };

  @override
  Widget build(BuildContext context) {
    final type = doc['doc_type'] as String? ?? '';
    final status = doc['status'] as String? ?? 'PENDING';
    final info = _statusInfo[status] ?? ('Inconnu', DriverPalette.textMuted, Icons.help_outline);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriverPalette.border),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: info.$2.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(info.$3, color: info.$2, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(type, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                color: DriverPalette.textPrimary)),
            Text(info.$1, style: TextStyle(fontSize: 12, color: info.$2,
                fontWeight: FontWeight.w500)),
          ]),
        ),
        if (doc['rejection_reason'] != null && status == 'REJECTED')
          Tooltip(
            message: doc['rejection_reason'].toString(),
            child: const Icon(Icons.info_outline, size: 18, color: Color(0xFFDC2626)),
          ),
      ]),
    );
  }
}

class _EmptyDocs extends StatelessWidget {
  const _EmptyDocs();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: DriverPalette.primary.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: DriverPalette.primary.withValues(alpha: 0.2)),
    ),
    child: const Row(children: [
      Icon(Icons.badge_outlined, color: DriverPalette.primary, size: 28),
      SizedBox(width: 12),
      Expanded(
        child: Text('Aucun document soumis. Ajoutez votre CNI ou Passeport pour débloquer les missions.',
            style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary, height: 1.4)),
      ),
    ]),
  );
}

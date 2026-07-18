import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

class RentalListingEditPage extends StatefulWidget {
  const RentalListingEditPage({super.key, this.listing});

  final Map<String, dynamic>? listing;

  @override
  State<RentalListingEditPage> createState() => _RentalListingEditPageState();
}

class _RentalListingEditPageState extends State<RentalListingEditPage> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _city;
  late final TextEditingController _price;
  late final TextEditingController _deposit;
  String _period = 'DAY';
  PlatformFile? _proofFile;
  PlatformFile? _imageFile;
  bool _saving = false;

  bool get _isEdit => widget.listing != null;

  static const _periods = {
    'HOUR': 'Par heure',
    'DAY': 'Par jour',
    'WEEK': 'Par semaine',
    'MONTH': 'Par mois',
  };

  @override
  void initState() {
    super.initState();
    final l = widget.listing ?? const <String, dynamic>{};
    _title = TextEditingController(text: (l['title'] ?? '').toString());
    _description =
        TextEditingController(text: (l['description'] ?? '').toString());
    _category = TextEditingController(text: (l['category'] ?? '').toString());
    _city = TextEditingController(text: (l['city'] ?? '').toString());
    _price = TextEditingController(
        text: l['price_per_period'] == null ? '' : '${l['price_per_period']}');
    _deposit = TextEditingController(
        text: l['deposit_amount'] == null ? '' : '${l['deposit_amount']}');
    _period = (l['price_period'] ?? 'DAY').toString();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _category.dispose();
    _city.dispose();
    _price.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _pickFile({required bool proof}) async {
    final result = await FilePicker.platform.pickFiles(
      type: proof ? FileType.custom : FileType.image,
      allowedExtensions: proof ? ['pdf', 'png', 'jpg', 'jpeg', 'webp'] : null,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      if (proof) {
        _proofFile = result.files.first;
      } else {
        _imageFile = result.files.first;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_isEdit && _proofFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('La preuve de propriété est obligatoire pour publier.')));
      return;
    }
    setState(() => _saving = true);
    final token = context.read<SessionStore>().token;
    final fields = <String, String>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'category': _category.text.trim(),
      'city': _city.text.trim(),
      'price_period': _period,
      'price_per_period': _price.text.trim(),
      'deposit_amount':
          _deposit.text.trim().isEmpty ? '0' : _deposit.text.trim(),
    };
    try {
      Map<String, dynamic> saved;
      if (_isEdit) {
        final id = widget.listing!['id'];
        saved = await _api.patch('/api/rental-listings/$id/',
            fields.map((k, v) => MapEntry(k, v as dynamic)),
            token: token);
      } else {
        saved = await _api.postMultipart('/api/rental-listings/',
            fields: fields,
            file: _proofFile,
            fileFieldName: 'ownership_proof',
            token: token);
      }
      if (_imageFile != null) {
        saved = await _api.sendMultipartFiles(
          '/api/rental-listings/${saved['id']}/',
          fields: const {},
          files: [_imageFile!],
          fileFieldName: 'image',
          method: 'PATCH',
          token: token,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isEdit ? 'Annonce mise à jour.' : 'Annonce publiée.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_api.toUserMessage(e,
              fallback: 'Impossible d\'enregistrer l\'annonce.'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title:
              Text(_isEdit ? 'Modifier l\'annonce' : 'Nouvelle location')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Titre du bien'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Titre requis' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Description requise' : null,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _category,
                  decoration:
                      const InputDecoration(labelText: 'Catégorie'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(labelText: 'Ville'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _period,
              decoration:
                  const InputDecoration(labelText: 'Période de tarification'),
              items: _periods.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() => _period = v ?? 'DAY'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Prix par période (FCFA)'),
                  validator: (v) {
                    final n = num.tryParse((v ?? '').trim());
                    return (n == null || n <= 0) ? 'Prix invalide' : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _deposit,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Caution (FCFA)'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = num.tryParse(t);
                    return (n == null || n < 0) ? 'Caution invalide' : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 20),
            if (!_isEdit)
              OutlinedButton.icon(
                onPressed: () => _pickFile(proof: true),
                icon: const Icon(LucideIcons.fileCheck),
                label: Text(_proofFile == null
                    ? 'Preuve de propriété (obligatoire)'
                    : 'Preuve : ${_proofFile!.name}'),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _pickFile(proof: false),
              icon: const Icon(LucideIcons.image),
              label: Text(_imageFile == null
                  ? 'Photo du bien (optionnel)'
                  : 'Photo : ${_imageFile!.name}'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.check),
              label: Text(_isEdit ? 'Enregistrer' : 'Publier l\'annonce'),
            ),
            const SizedBox(height: 8),
            const Text(
              'La publication exige un compte vérifié KYC niveau 2. La caution '
              'est séquestrée pendant la location et restituée au retour conforme.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

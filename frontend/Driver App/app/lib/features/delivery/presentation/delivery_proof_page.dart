import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

class DeliveryProofPage extends StatefulWidget {
  final String shipmentId;
  const DeliveryProofPage({super.key, required this.shipmentId});

  @override
  State<DeliveryProofPage> createState() => _DeliveryProofPageState();
}

class _DeliveryProofPageState extends State<DeliveryProofPage> {
  XFile? _photo;
  final _noteCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 75);
    if (img != null) setState(() => _photo = img);
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Prenez une photo comme preuve de livraison.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(_photo!.path, filename: 'proof.jpg'),
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
      });
      // Audit ref: [Front-Driver] backend exposes
      // ShipmentViewSet.submit_proof (logistics/views.py:422). The previous
      // /upload-proof/ path was a 404.
      await DriverDioClient.dio.post(
          '/api/shipments/${widget.shipmentId}/submit_proof/', data: form);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preuve envoyée. Validez avec l\'OTP.')),
      );
      context.pushReplacement('/active/otp/${widget.shipmentId}');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Preuve de livraison'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 16),
          ],
          const Text('Photo de livraison',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: DriverPalette.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: _photo != null ? DriverPalette.primary.withValues(alpha: 0.05) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _photo != null ? DriverPalette.primary : DriverPalette.border,
                    width: _photo != null ? 2 : 1),
              ),
              child: _photo != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.network(_photo!.path, fit: BoxFit.cover),
                    )
                  : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_a_photo_outlined, size: 36, color: DriverPalette.textMuted),
                      SizedBox(height: 8),
                      Text('Photo de la livraison',
                          style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary,
                              fontWeight: FontWeight.w600)),
                      Text('Appuyez pour ouvrir la caméra',
                          style: TextStyle(fontSize: 12, color: DriverPalette.textMuted)),
                    ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Note (optionnel)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: DriverPalette.textMuted, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Ex: Laissé au gardien, boîte aux lettres…',
              prefixIcon: Icon(Icons.note_outlined),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Text('Envoyer la preuve',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFFCA5A5)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
          style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
    ]),
  );
}

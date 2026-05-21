import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

class PickupConfirmationPage extends StatefulWidget {
  final String shipmentId;
  const PickupConfirmationPage({super.key, required this.shipmentId});

  @override
  State<PickupConfirmationPage> createState() => _PickupConfirmationPageState();
}

class _PickupConfirmationPageState extends State<PickupConfirmationPage> {
  XFile? _photo;
  bool _busy = false;
  String? _error;

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 75);
    if (img != null) setState(() => _photo = img);
  }

  Future<void> _confirm() async {
    if (_photo == null) {
      setState(() => _error = 'Prenez une photo du colis avant de confirmer.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(_photo!.path, filename: 'pickup.jpg'),
      });
      await DriverDioClient.dio.post(
          '/api/logistics/shipments/${widget.shipmentId}/confirm-pickup/', data: form);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enlèvement confirmé !')),
      );
      context.go('/active');
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
        title: const Text('Confirmer l\'enlèvement'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline, color: Color(0xFF16A34A), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Photographiez le colis avant de partir. Cette photo sert de preuve d\'enlèvement.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF15803D), height: 1.4),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: _photo != null
                      ? DriverPalette.primary.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _photo != null ? DriverPalette.primary : DriverPalette.border,
                      width: _photo != null ? 2 : 1),
                ),
                child: _photo != null
                    ? Stack(alignment: Alignment.topRight, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.network(_photo!.path, width: double.infinity,
                              height: 200, fit: BoxFit.cover),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: DriverPalette.primary,
                            child: const Icon(Icons.check, color: Colors.white, size: 16),
                          ),
                        ),
                      ])
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.camera_alt_outlined, size: 40, color: DriverPalette.textMuted),
                        SizedBox(height: 10),
                        Text('Photographier le colis',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                                color: DriverPalette.textSecondary)),
                        Text('Appuyez pour ouvrir la caméra',
                            style: TextStyle(fontSize: 12, color: DriverPalette.textMuted)),
                      ]),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Confirmer l\'enlèvement',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

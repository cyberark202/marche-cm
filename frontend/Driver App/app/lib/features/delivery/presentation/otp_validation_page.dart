import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

class OtpValidationPage extends StatefulWidget {
  final String shipmentId;
  const OtpValidationPage({super.key, required this.shipmentId});

  @override
  State<OtpValidationPage> createState() => _OtpValidationPageState();
}

class _OtpValidationPageState extends State<OtpValidationPage> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _focusNodes = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) { c.dispose(); }
    for (final f in _focusNodes) { f.dispose(); }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _validate() async {
    if (_otp.length < 4) {
      setState(() => _error = 'Entrez le code à 4 chiffres fourni par le client.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await DriverDioClient.dio.post(
        '/api/logistics/shipments/${widget.shipmentId}/validate-otp/',
        data: {'otp': _otp},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Livraison confirmée ! Bravo !')),
      );
      context.go('/active');
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Code invalide. Vérifiez avec le client.';
          _busy = false;
          for (final c in _controllers) { c.clear(); }
          _focusNodes.first.requestFocus();
        });
      }
    }
  }

  void _onChanged(int index, String val) {
    if (val.length == 1 && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }
    if (val.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Code de validation'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: DriverPalette.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.pin_outlined, color: DriverPalette.primary, size: 36),
            ),
            const SizedBox(height: 20),
            const Text('Entrez le code OTP', style: TextStyle(fontSize: 20,
                fontWeight: FontWeight.w700, color: DriverPalette.textPrimary)),
            const SizedBox(height: 8),
            const Text(
              'Demandez au client le code à 4 chiffres reçu par SMS pour confirmer la livraison.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
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
              const SizedBox(height: 20),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (i) => SizedBox(
                width: 46,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _focusNodes[i],
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) => _onChanged(i, v),
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: _controllers[i].text.isNotEmpty
                              ? DriverPalette.primary
                              : DriverPalette.border,
                          width: _controllers[i].text.isNotEmpty ? 2 : 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: DriverPalette.primary, width: 2),
                    ),
                  ),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                      color: DriverPalette.primary),
                ),
              )),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity, height: 52,
              child: FilledButton(
                onPressed: (_otp.length == 4 && !_busy) ? _validate : null,
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Valider la livraison',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => context.push('/active/proof/${widget.shipmentId}'),
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: const Text('Problème ? Uploader une preuve photo'),
            ),
          ],
        ),
      ),
    );
  }
}

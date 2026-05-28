import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

/// Preuve de livraison — photo + code OTP 4 chiffres (PDF 28).
class DeliveryProofPage extends StatefulWidget {
  final String shipmentId;
  const DeliveryProofPage({super.key, required this.shipmentId});

  @override
  State<DeliveryProofPage> createState() => _DeliveryProofPageState();
}

class _DeliveryProofPageState extends State<DeliveryProofPage> {
  XFile? _photo;
  final List<TextEditingController> _otp =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(4, (_) => FocusNode());
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _otp) c.dispose();
    for (final f in _otpFocus) f.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final img = await ImagePicker()
        .pickImage(source: ImageSource.camera, imageQuality: 75);
    if (img != null) setState(() => _photo = img);
  }

  String get _otpValue => _otp.map((c) => c.text.trim()).join();

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = "Prenez d'abord la photo du colis livré.");
      return;
    }
    if (_otpValue.length != 4) {
      setState(() => _error = "Saisissez le code 4 chiffres de l'acheteur.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final form = FormData.fromMap({
        "photo":
            await MultipartFile.fromFile(_photo!.path, filename: "proof.jpg"),
        "otp": _otpValue,
      });
      await DriverDioClient.dio.post(
          "/api/shipments/${widget.shipmentId}/submit_proof/",
          data: form);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Livraison validée — séquestre libéré.")),
      );
      context.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst("Exception: ", "");
          _busy = false;
        });
      }
    }
  }

  Future<void> _resendCode() async {
    try {
      await DriverDioClient.dio.post(
          "/api/shipments/${widget.shipmentId}/resend_otp/",
          data: const {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Code renvoyé à l'acheteur par SMS.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Envoi impossible : ${e.toString()}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
                shipmentId: widget.shipmentId,
                onBack: () => context.pop()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const SizedBox(height: 12),
                  ],
                  _StepLabel(num: 1, text: "PHOTO DU COLIS LIVRÉ"),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: _pickPhoto,
                    borderRadius: BorderRadius.circular(T.rLg),
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: _photo != null
                            ? T.primarySoft
                            : T.surface,
                        borderRadius: BorderRadius.circular(T.rLg),
                        border: Border.all(
                          color: _photo != null ? T.primary : T.line,
                          width: _photo != null ? 1.6 : 1,
                        ),
                        boxShadow: T.shadowSm,
                      ),
                      child: _photo != null
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(T.rLg),
                                  child: Image.network(
                                    _photo!.path,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.check_circle,
                                          size: 48, color: T.primary),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: T.primary,
                                      borderRadius:
                                          BorderRadius.circular(T.rFull),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check,
                                            color: Colors.white, size: 11),
                                        SizedBox(width: 3),
                                        Text("OK",
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w800)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: T.accentSoft,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt,
                                      color: T.accentDark, size: 26),
                                ),
                                const SizedBox(height: 10),
                                const Text("Prendre la photo",
                                    style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: T.ink)),
                                const SizedBox(height: 2),
                                const Text(
                                  "Colis devant la porte du destinataire",
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: T.ink3,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _StepLabel(num: 2, text: "CODE DE CONFIRMATION ACHETEUR"),
                  const SizedBox(height: 8),
                  const Text(
                    "Demandez à l'acheteur son code à 4 chiffres reçu par SMS.",
                    style: TextStyle(
                        fontSize: 12, color: T.ink3, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        _OtpBox(
                          ctrl: _otp[i],
                          focus: _otpFocus[i],
                          onChanged: (v) {
                            if (v.length == 1 && i < 3) {
                              _otpFocus[i + 1].requestFocus();
                            } else if (v.isEmpty && i > 0) {
                              _otpFocus[i - 1].requestFocus();
                            }
                            setState(() {});
                          },
                        ),
                        if (i < 3) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      onPressed: _resendCode,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text("Renvoyer le code à l'acheteur"),
                      style: TextButton.styleFrom(
                        foregroundColor: T.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: T.primarySoft,
                      borderRadius: BorderRadius.circular(T.r),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.location_on,
                            size: 16, color: T.primaryDark),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Position GPS confirmée à l'adresse de livraison (< 50 m).",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: T.primaryDark,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _Footer(busy: _busy, onSubmit: _submit),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shipmentId, required this.onBack});
  final String shipmentId;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: const BoxDecoration(
        gradient: T.gradientDriverHeader,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(T.rXl),
            bottomRight: Radius.circular(T.rXl)),
      ),
      child: Row(
        children: [
          IconButton(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const Expanded(
            child: Text("Preuve de livraison",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(T.rFull),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Text("#$shipmentId",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.num, required this.text});
  final int num;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: T.primary,
            shape: BoxShape.circle,
          ),
          child: Text("$num",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: T.ink,
                letterSpacing: 1.0)),
      ],
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox(
      {required this.ctrl, required this.focus, required this.onChanged});
  final TextEditingController ctrl;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final filled = ctrl.text.isNotEmpty;
    return SizedBox(
      width: 60,
      height: 68,
      child: TextField(
        controller: ctrl,
        focusNode: focus,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: T.primaryDeep),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: filled ? T.primarySoft : T.surface,
          contentPadding: EdgeInsets.zero,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(T.r),
              borderSide:
                  BorderSide(color: filled ? T.primary : T.line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(T.r),
              borderSide:
                  const BorderSide(color: T.primary, width: 1.6)),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.busy, required this.onSubmit});
  final bool busy;
  final VoidCallback onSubmit;
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: T.surface,
          boxShadow: T.shadowMd,
          border:
              const Border(top: BorderSide(color: T.line2, width: 1)),
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: busy ? null : onSubmit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: Text(busy ? "Envoi..." : "Valider la livraison",
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(
              backgroundColor: T.primary,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
            ),
          ),
        ),
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
          color: T.coralSoft,
          borderRadius: BorderRadius.circular(T.r),
          border: Border.all(color: T.coral.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 16, color: T.coral),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: T.coral, fontSize: 12.5))),
        ]),
      );
}

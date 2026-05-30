import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:dio/dio.dart';

import '../../core/app_theme.dart';
import '../../core/security/secure_dio_client.dart';

enum _DocType { cni, passport }

class BuyerKycPage extends StatefulWidget {
  const BuyerKycPage({super.key});

  @override
  State<BuyerKycPage> createState() => _BuyerKycPageState();
}

class _BuyerKycPageState extends State<BuyerKycPage> {
  int _step = 0;
  _DocType _docType = _DocType.cni;
  PlatformFile? _frontFile;
  PlatformFile? _backFile;
  bool _uploading = false;
  String? _errorMessage;

  // Catalogue screen 46 — handwritten signature + legal consent.
  final GlobalKey _signatureBoundaryKey = GlobalKey();
  final GlobalKey<_SignaturePadState> _signaturePadKey =
      GlobalKey<_SignaturePadState>();
  bool _hasSignature = false;
  bool _consentAccepted = false;
  Uint8List? _signatureBytes;

  // Step order is dynamic: the CNI flow has an extra "verso" step.
  List<String> get _stepOrder => _docType == _DocType.cni
      ? const ['type', 'front', 'back', 'signature', 'review']
      : const ['type', 'front', 'signature', 'review'];

  int get _totalSteps => _stepOrder.length;
  String get _currentKind => _stepOrder[_step];

  Future<void> _pickFile(bool isFront) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    setState(() {
      if (isFront) {
        _frontFile = result.files.first;
      } else {
        _backFile = result.files.first;
      }
      _errorMessage = null;
    });
  }

  /// Rasterise the signature pad to PNG bytes for review + upload.
  Future<Uint8List?> _captureSignature() async {
    try {
      final boundary = _signatureBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_frontFile?.path == null) {
      setState(() => _errorMessage = 'Veuillez sélectionner la photo recto.');
      return;
    }
    if (_docType == _DocType.cni && _backFile?.path == null) {
      setState(() => _errorMessage = 'Veuillez sélectionner la photo verso.');
      return;
    }
    if (!_consentAccepted || _signatureBytes == null) {
      setState(() => _errorMessage =
          'Signature et acceptation des CGU obligatoires.');
      return;
    }
    setState(() {
      _uploading = true;
      _errorMessage = null;
    });
    try {
      // Backend contract (ComplianceDocumentSerializer): writable fields are
      // `doc_type` (∈ CNI | CNI_VERSO | PASSPORT | …) and `file`. The recto is
      // the primary document; the CNI verso is a SECOND document (CNI_VERSO).
      final frontType = _docType == _DocType.cni ? 'CNI' : 'PASSPORT';
      final frontData = FormData();
      frontData.fields.add(MapEntry('doc_type', frontType));
      frontData.fields.add(const MapEntry('consent_accepted', 'true'));
      frontData.files.add(MapEntry(
        'file',
        await MultipartFile.fromFile(_frontFile!.path!,
            filename: _frontFile!.name),
      ));
      // Handwritten signature (catalogue 46) — sent best-effort. The compliance
      // model has no signature field yet, so it currently enforces client-side
      // legal consent. See docs/INCOHERENCES_BACKEND_FRONTEND.md.
      frontData.files.add(MapEntry(
        'signature',
        MultipartFile.fromBytes(_signatureBytes!, filename: 'signature.png'),
      ));
      // Dedicated buyer-KYC endpoint: any authenticated user may submit an
      // identity document here (the generic /compliance-documents/ is reserved
      // to compliance actors). See backend BuyerKycSubmitView.
      await SecureDioClient.dio
          .post('/api/auth/kyc/submit/', data: frontData);

      if (_docType == _DocType.cni && _backFile?.path != null) {
        final backData = FormData();
        backData.fields.add(const MapEntry('doc_type', 'CNI_VERSO'));
        backData.files.add(MapEntry(
          'file',
          await MultipartFile.fromFile(_backFile!.path!,
              filename: _backFile!.name),
        ));
        await SecureDioClient.dio
            .post('/api/auth/kyc/submit/', data: backData);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Documents soumis. Vérification en cours (24-48h).'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _errorMessage = 'Erreur lors de l\'envoi. Réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Vérification d\'identité',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF334155)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepContent(),
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Étape ${_step + 1} sur $_totalSteps',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('${((_step + 1) / _totalSteps * 100).round()}%',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.primary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_step + 1) / _totalSteps,
              backgroundColor: const Color(0xFFE2E8F0),
              color: AppPalette.primary,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentKind) {
      case 'type':
        return _stepChooseDocType();
      case 'front':
        return _stepUploadFront();
      case 'back':
        return _stepUploadBack();
      case 'signature':
        return _stepSignature();
      default:
        return _stepReview();
    }
  }

  Widget _stepChooseDocType() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            icon: Icons.badge_outlined,
            title: 'Type de document',
            subtitle:
                'Choisissez le document d\'identité que vous souhaitez utiliser.',
          ),
          const SizedBox(height: 24),
          _DocTypeCard(
            title: 'Carte Nationale d\'Identité',
            subtitle: 'CNI camerounaise ou étrangère en cours de validité',
            icon: Icons.credit_card,
            selected: _docType == _DocType.cni,
            onTap: () => setState(() => _docType = _DocType.cni),
          ),
          const SizedBox(height: 12),
          _DocTypeCard(
            title: 'Passeport',
            subtitle: 'Passeport biométrique en cours de validité',
            icon: Icons.book_outlined,
            selected: _docType == _DocType.passport,
            onTap: () => setState(() => _docType = _DocType.passport),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vos données sont chiffrées et utilisées uniquement pour la vérification légale. Elles ne sont jamais partagées.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _stepUploadFront() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(
            icon: Icons.camera_front_outlined,
            title: _docType == _DocType.cni
                ? 'Recto de votre CNI'
                : 'Page photo du passeport',
            subtitle: 'Prenez une photo claire, bien éclairée, sans reflet.',
          ),
          const SizedBox(height: 24),
          _PhotoUploadArea(
            file: _frontFile,
            label: _docType == _DocType.cni ? 'RECTO' : 'PAGE PHOTO',
            onPick: () => _pickFile(true),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      );

  Widget _stepUploadBack() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            icon: Icons.camera_rear_outlined,
            title: 'Verso de votre CNI',
            subtitle:
                'Prenez une photo du verso, assurez-vous que le texte est lisible.',
          ),
          const SizedBox(height: 24),
          _PhotoUploadArea(
            file: _backFile,
            label: 'VERSO',
            onPick: () => _pickFile(false),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      );

  // Catalogue screen 46 — handwritten signature + legal engagement.
  Widget _stepSignature() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            icon: Icons.draw_outlined,
            title: 'Signature manuscrite',
            subtitle:
                'Signez avec votre doigt. Cette signature numérique vous engage légalement.',
          ),
          const SizedBox(height: 20),
          RepaintBoundary(
            key: _signatureBoundaryKey,
            child: _SignaturePad(
              key: _signaturePadKey,
              onChanged: (isEmpty) {
                final has = !isEmpty;
                if (has != _hasSignature) {
                  setState(() => _hasSignature = has);
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _signaturePadKey.currentState?.clear();
                setState(() {
                  _hasSignature = false;
                  _signatureBytes = null;
                });
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Recommencer'),
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => setState(() => _consentAccepted = !_consentAccepted),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _consentAccepted,
                  onChanged: (v) =>
                      setState(() => _consentAccepted = v ?? false),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'En signant, je reconnais avoir lu et accepté les CGU et la Politique de confidentialité de Marché CM.',
                      style:
                          TextStyle(fontSize: 13, color: Color(0xFF334155)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      );

  Widget _stepReview() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepHeader(
            icon: Icons.check_circle_outline,
            title: 'Vérification finale',
            subtitle: 'Relisez vos documents avant de soumettre.',
          ),
          const SizedBox(height: 24),
          _ReviewItem(
            label: 'Type de document',
            value: _docType == _DocType.cni
                ? 'Carte Nationale d\'Identité'
                : 'Passeport',
            icon: _docType == _DocType.cni
                ? Icons.credit_card
                : Icons.book_outlined,
          ),
          const SizedBox(height: 10),
          if (_frontFile != null)
            _ReviewItem(
              label: _docType == _DocType.cni ? 'Recto' : 'Page photo',
              value: _frontFile!.name,
              icon: Icons.image_outlined,
            ),
          if (_backFile != null) ...[
            const SizedBox(height: 10),
            _ReviewItem(
              label: 'Verso',
              value: _backFile!.name,
              icon: Icons.image_outlined,
            ),
          ],
          const SizedBox(height: 10),
          _ReviewItem(
            label: 'Signature',
            value: _signatureBytes != null ? 'Capturée ✓' : 'Manquante',
            icon: Icons.draw_outlined,
          ),
          if (_signatureBytes != null) ...[
            const SizedBox(height: 12),
            Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.memory(_signatureBytes!, fit: BoxFit.contain),
              ),
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _errorMessage!),
          ],
        ],
      );

  Widget _buildBottomBar() {
    final isLastStep = (_step == _totalSteps - 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _uploading ? null : () => setState(() => _step--),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Précédent'),
              ),
            ),
          if (_step > 0) const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _uploading ? null : _onPrimaryPressed,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _uploading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLastStep ? 'Soumettre' : 'Continuer',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onPrimaryPressed() async {
    final kind = _currentKind;
    if (kind == 'review') {
      await _submit();
      return;
    }
    // Per-step validation before advancing.
    if (kind == 'front' && _frontFile == null) {
      setState(() => _errorMessage = 'Veuillez sélectionner une photo.');
      return;
    }
    if (kind == 'back' && _backFile == null) {
      setState(() => _errorMessage = 'Veuillez sélectionner une photo.');
      return;
    }
    if (kind == 'signature') {
      if (!_hasSignature) {
        setState(() => _errorMessage = 'Veuillez signer avant de continuer.');
        return;
      }
      if (!_consentAccepted) {
        setState(() => _errorMessage = 'Vous devez accepter les CGU.');
        return;
      }
      final bytes = await _captureSignature();
      if (bytes == null) {
        setState(() => _errorMessage =
            'Impossible de capturer la signature. Réessayez.');
        return;
      }
      _signatureBytes = bytes;
    }
    setState(() {
      _step++;
      _errorMessage = null;
    });
  }
}

// ── Signature pad ─────────────────────────────────────────────────────────────

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key, required this.onChanged});

  /// Reports `true` when the pad is empty, `false` once strokes exist.
  final ValueChanged<bool> onChanged;

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];

  void clear() {
    setState(() => _strokes.clear());
    widget.onChanged(true);
  }

  void _start(Offset p) {
    setState(() => _strokes.add([p]));
    widget.onChanged(false);
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.last.add(p));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onPanStart: (d) => _start(d.localPosition),
        onPanUpdate: (d) => _extend(d.localPosition),
        child: CustomPaint(
          painter: _SignaturePainter(_strokes),
          size: Size.infinite,
          child: _strokes.isEmpty
              ? const Center(
                  child: Text('Signez ici',
                      style: TextStyle(color: Color(0xFF94A3B8))),
                )
              : null,
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.length == 1) {
          canvas.drawPoints(ui.PointMode.points, stroke, paint);
        }
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _StepHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppPalette.primary, size: 26),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF64748B), height: 1.4)),
        ],
      );
}

class _DocTypeCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _DocTypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? AppPalette.primary.withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppPalette.primary : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? AppPalette.primary.withValues(alpha: 0.1)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    color:
                        selected ? AppPalette.primary : const Color(0xFF94A3B8)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: selected
                                ? AppPalette.primary
                                : const Color(0xFF0F172A))),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: AppPalette.primary, size: 20),
            ],
          ),
        ),
      );
}

class _PhotoUploadArea extends StatelessWidget {
  final PlatformFile? file;
  final String label;
  final VoidCallback onPick;
  const _PhotoUploadArea(
      {required this.file, required this.label, required this.onPick});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onPick,
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            color: file != null
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: file != null
                  ? const Color(0xFF86EFAC)
                  : const Color(0xFFCBD5E1),
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: file != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(File(file!.path!), fit: BoxFit.cover),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, size: 13, color: Colors.white),
                            SizedBox(width: 4),
                            Text('Modifier',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12)),
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
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: AppPalette.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.add_photo_alternate_outlined,
                          color: AppPalette.primary, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text('Photo $label',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF334155))),
                    const SizedBox(height: 4),
                    const Text('Appuyez pour sélectionner',
                        style:
                            TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                  ],
                ),
        ),
      );
}

class _ReviewItem extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ReviewItem(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppPalette.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF94A3B8))),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF0F172A))),
              ],
            ),
          ],
        ),
      );
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
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style:
                        const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
          ],
        ),
      );
}

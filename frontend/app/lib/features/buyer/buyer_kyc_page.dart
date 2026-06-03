import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:dio/dio.dart';

import '../../core/app_theme.dart';
import '../../core/security/secure_dio_client.dart';

/// KYC onboarding — wizard fidèle au design `screens-kyc.jsx` (6 écrans) :
/// intro → type de compte → documents → signature → récapitulatif → succès.
///
/// Backend : `POST /api/auth/kyc/submit/` (multipart) par document, avec la
/// signature manuscrite + `consent_accepted` (horodaté serveur) sur le premier
/// envoi. doc_type ∈ {CNI, PROOF_ADDRESS, SELFIE}.
enum _KycStage { intro, type, docs, signature, review, success }

enum _AccountType { individual, company, pro }

class BuyerKycPage extends StatefulWidget {
  const BuyerKycPage({super.key});

  @override
  State<BuyerKycPage> createState() => _BuyerKycPageState();
}

class _BuyerKycPageState extends State<BuyerKycPage> {
  _KycStage _stage = _KycStage.intro;
  _AccountType _accountType = _AccountType.individual;

  // 3 documents requis par le design : CNI, justificatif domicile, selfie.
  final Map<String, PlatformFile?> _docs = {
    'cni': null,
    'address': null,
    'selfie': null,
  };

  bool _uploading = false;
  String? _errorMessage;

  // Signature manuscrite + consentement légal (design écran 04 / catalogue 46).
  final GlobalKey _signatureBoundaryKey = GlobalKey();
  final GlobalKey<_SignaturePadState> _signaturePadKey =
      GlobalKey<_SignaturePadState>();
  bool _hasSignature = false;
  bool _consentAccepted = false;
  Uint8List? _signatureBytes;

  static const _primaryDeep = Color(0xFF063D27);

  int get _docsDone => _docs.values.where((f) => f != null).length;
  bool get _allDocsDone => _docsDone == _docs.length;

  // ── Step index for the 4-segment progress bar (type→docs→signature→review)
  int get _stepIndex {
    switch (_stage) {
      case _KycStage.type:
        return 1;
      case _KycStage.docs:
        return 2;
      case _KycStage.signature:
        return 3;
      case _KycStage.review:
        return 4;
      default:
        return 0;
    }
  }

  Future<void> _pickDoc(String key) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _docs[key] = result.files.first;
      _errorMessage = null;
    });
  }

  Future<Uint8List?> _captureSignature() async {
    try {
      final boundary = _signatureBoundaryKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (!_allDocsDone) {
      setState(() => _errorMessage = 'Les 3 documents sont requis.');
      return;
    }
    if (!_consentAccepted || _signatureBytes == null) {
      setState(() =>
          _errorMessage = 'Signature et acceptation des CGU obligatoires.');
      return;
    }
    setState(() {
      _uploading = true;
      _errorMessage = null;
    });
    try {
      // 1) CNI (document d'identité primaire) — porte la signature + consentement.
      final cniData = FormData();
      cniData.fields.add(const MapEntry('doc_type', 'CNI'));
      cniData.fields.add(const MapEntry('consent_accepted', 'true'));
      cniData.files.add(MapEntry(
        'file',
        await MultipartFile.fromFile(_docs['cni']!.path!,
            filename: _docs['cni']!.name),
      ));
      cniData.files.add(MapEntry(
        'signature',
        MultipartFile.fromBytes(_signatureBytes!, filename: 'signature.png'),
      ));
      await SecureDioClient.dio.post('/api/auth/kyc/submit/', data: cniData);

      // 2) Justificatif de domicile.
      await _postDoc('PROOF_ADDRESS', _docs['address']!);
      // 3) Selfie avec CNI.
      await _postDoc('SELFIE', _docs['selfie']!);

      if (!mounted) return;
      setState(() {
        _uploading = false;
        _stage = _KycStage.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _errorMessage = 'Erreur lors de l\'envoi. Réessayez.';
      });
    }
  }

  Future<void> _postDoc(String docType, PlatformFile file) async {
    final data = FormData();
    data.fields.add(MapEntry('doc_type', docType));
    data.files.add(MapEntry(
      'file',
      await MultipartFile.fromFile(file.path!, filename: file.name),
    ));
    await SecureDioClient.dio.post('/api/auth/kyc/submit/', data: data);
  }

  @override
  Widget build(BuildContext context) {
    if (_stage == _KycStage.success) return _SuccessScreen(onClose: _close);

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (_stepIndex > 0) _KycProgress(step: _stepIndex),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _stageContent(),
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  void _back() {
    setState(() {
      _errorMessage = null;
      switch (_stage) {
        case _KycStage.type:
          _stage = _KycStage.intro;
          break;
        case _KycStage.docs:
          _stage = _KycStage.type;
          break;
        case _KycStage.signature:
          _stage = _KycStage.docs;
          break;
        case _KycStage.review:
          _stage = _KycStage.signature;
          break;
        case _KycStage.intro:
          _close();
          break;
        default:
          break;
      }
    });
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header() {
    final (title, subtitle) = switch (_stage) {
      _KycStage.intro => ('Vérification KYC', 'Étape obligatoire > 50 k F'),
      _KycStage.type => ('Étape 1 / 4', 'Type de compte'),
      _KycStage.docs => ('Étape 2 / 4', 'Téléverser les documents'),
      _KycStage.signature => ('Étape 3 / 4', 'Signature manuscrite'),
      _KycStage.review => ('Étape 4 / 4', 'Récapitulatif'),
      _KycStage.success => ('', ''),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Row(
        children: [
          _RoundIconButton(icon: Icons.arrow_back, onTap: _back),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.text)),
                if (subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle,
                        style: const TextStyle(
                            fontSize: 12, color: AppPalette.textMuted)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageContent() {
    switch (_stage) {
      case _KycStage.intro:
        return _introContent();
      case _KycStage.type:
        return _typeContent();
      case _KycStage.docs:
        return _docsContent();
      case _KycStage.signature:
        return _signatureContent();
      case _KycStage.review:
        return _reviewContent();
      case _KycStage.success:
        return const SizedBox.shrink();
    }
  }

  // ── Écran 1 : Intro ─────────────────────────────────────────────────────
  Widget _introContent() {
    const needs = [
      (Icons.verified_user_outlined, "Pièce d'identité", 'CNI, passeport ou récépissé'),
      (Icons.location_on_outlined, 'Justificatif de domicile', 'Facture ENEO/CAMWATER < 3 mois'),
      (Icons.phone_iphone, 'Numéro Mobile Money', 'MTN MoMo ou Orange Money actif'),
      (Icons.edit_outlined, 'Signature manuscrite', 'Capturée à l\'étape finale'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppPalette.primary, _primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppPalette.shadowStrong,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('SÉCURISÉ · CHIFFRÉ AES-256',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A0F00))),
              ),
              const SizedBox(height: 12),
              const Text('Validez votre identité\nen moins de 3 minutes',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.4)),
              const SizedBox(height: 6),
              const Text(
                  'Conforme aux exigences GIMAC et BEAC pour le paiement Mobile Money.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12.5, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('Ce dont vous aurez besoin'),
        const SizedBox(height: 10),
        for (final n in needs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(n.$1, size: 17, color: AppPalette.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.$2,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(n.$3,
                            style: const TextStyle(
                                fontSize: 11, color: AppPalette.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.check, size: 15, color: AppPalette.primary),
                ],
              ),
            ),
          ),
        const SizedBox(height: 4),
        const _AccentNote(
          icon: Icons.lock_outline,
          text:
              'Vos documents ne sont jamais partagés avec les autres utilisateurs. Stockés chiffrés.',
        ),
      ],
    );
  }

  // ── Écran 2 : Type de compte ────────────────────────────────────────────
  Widget _typeContent() {
    const options = [
      (_AccountType.individual, Icons.person_outline, 'Particulier',
          'CNI · justificatif domicile'),
      (_AccountType.company, Icons.inventory_2_outlined, 'Entreprise / SARL',
          'RC · NIU · CNI dirigeant'),
      (_AccountType.pro, Icons.local_shipping_outlined, 'Profession libérale',
          'Patente · CNI · attestation'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageTitle('Qui êtes-vous ?',
            'Les documents demandés dépendent de votre profil.'),
        const SizedBox(height: 18),
        for (final o in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SelectableCard(
              active: _accountType == o.$1,
              onTap: () => setState(() => _accountType = o.$1),
              icon: o.$2,
              title: o.$3,
              subtitle: o.$4,
            ),
          ),
      ],
    );
  }

  // ── Écran 3 : Documents ─────────────────────────────────────────────────
  Widget _docsContent() {
    const docMeta = [
      ('cni', "Carte nationale d'identité", 'Recto-verso, bonne lumière',
          Icons.badge_outlined),
      ('address', 'Justificatif de domicile', 'Facture ENEO < 3 mois',
          Icons.location_on_outlined),
      ('selfie', 'Selfie avec CNI', 'Pour confirmer l\'identité',
          Icons.camera_alt_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageTitle('3 documents requis',
            'Touchez chaque case pour sélectionner la photo.'),
        const SizedBox(height: 18),
        for (final d in docMeta)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DocUploadCard(
              file: _docs[d.$1],
              label: d.$2,
              subtitle: d.$3,
              icon: d.$4,
              onTap: () => _pickDoc(d.$1),
            ),
          ),
        if (_errorMessage != null) _ErrorBanner(message: _errorMessage!),
      ],
    );
  }

  // ── Écran 4 : Signature ─────────────────────────────────────────────────
  Widget _signatureContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageTitle('Signez avec votre doigt',
            'Cette signature numérique vous engage légalement.'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hasSignature ? AppPalette.primary : AppPalette.border,
              width: 2,
            ),
          ),
          child: Column(
            children: [
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
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Recommencer'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _consentAccepted = !_consentAccepted),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: _consentAccepted,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) =>
                        setState(() => _consentAccepted = v ?? false),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'En signant, je reconnais avoir lu et accepté les CGU et la Politique de confidentialité de Marché CM.',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: AppPalette.primaryDark,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }

  // ── Écran 5 : Récapitulatif ─────────────────────────────────────────────
  Widget _reviewContent() {
    final typeLabel = switch (_accountType) {
      _AccountType.individual => 'Particulier',
      _AccountType.company => 'Entreprise / SARL',
      _AccountType.pro => 'Profession libérale',
    };
    final rows = [
      ('Type de compte', typeLabel),
      ('CNI', _docs['cni'] != null ? 'Capturée ✓' : 'Manquante'),
      ('Justificatif domicile',
          _docs['address'] != null ? 'Capturé ✓' : 'Manquant'),
      ('Selfie avec CNI', _docs['selfie'] != null ? 'Capturé ✓' : 'Manquant'),
      ('Signature numérique', _signatureBytes != null ? 'Validée ✓' : 'Manquante'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StageTitle('Tout est prêt',
            'Vérifiez avant l\'envoi à notre équipe de conformité.'),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppPalette.border),
          ),
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: i < rows.length - 1
                          ? const BorderSide(color: AppPalette.borderSoft)
                          : BorderSide.none,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(rows[i].$1,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppPalette.textMuted,
                              fontWeight: FontWeight.w600)),
                      Text(rows[i].$2,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppPalette.text,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _AccentNote(
          icon: Icons.schedule,
          text:
              'Délai de traitement : 24 h ouvrées. Vous recevrez un email à validation.',
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          _ErrorBanner(message: _errorMessage!),
        ],
      ],
    );
  }

  // ── Bottom bar ──────────────────────────────────────────────────────────
  Widget _bottomBar() {
    final (label, icon, enabled, onPressed) = switch (_stage) {
      _KycStage.intro => (
          'Commencer la vérification',
          Icons.arrow_forward,
          true,
          () => setState(() => _stage = _KycStage.type),
        ),
      _KycStage.type => (
          'Continuer',
          Icons.arrow_forward,
          true,
          () => setState(() => _stage = _KycStage.docs),
        ),
      _KycStage.docs => (
          'Continuer ($_docsDone/3)',
          Icons.arrow_forward,
          _allDocsDone,
          () {
            if (!_allDocsDone) {
              setState(() => _errorMessage = 'Les 3 documents sont requis.');
              return;
            }
            setState(() {
              _errorMessage = null;
              _stage = _KycStage.signature;
            });
          },
        ),
      _KycStage.signature => (
          'Valider ma signature',
          Icons.arrow_forward,
          _hasSignature && _consentAccepted,
          _validateSignature,
        ),
      _KycStage.review => (
          'Envoyer pour vérification',
          Icons.send,
          true,
          _submit,
        ),
      _KycStage.success => ('', Icons.check, false, () {}),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppPalette.card,
        border: Border(top: BorderSide(color: AppPalette.borderSoft)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: (_uploading || !enabled) ? null : onPressed,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md)),
          ),
          icon: _uploading
              ? const SizedBox.shrink()
              : Icon(icon, size: 18),
          label: _uploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 14.5)),
        ),
      ),
    );
  }

  Future<void> _validateSignature() async {
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
      setState(() =>
          _errorMessage = 'Impossible de capturer la signature. Réessayez.');
      return;
    }
    setState(() {
      _signatureBytes = bytes;
      _errorMessage = null;
      _stage = _KycStage.review;
    });
  }
}

// ── Sous-widgets ──────────────────────────────────────────────────────────

class _KycProgress extends StatelessWidget {
  final int step; // 1..4
  const _KycProgress({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          for (int i = 1; i <= 4; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? AppPalette.primary : AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i < 4) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _StageTitle extends StatelessWidget {
  final String title, subtitle;
  const _StageTitle(this.title, this.subtitle);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: AppPalette.text)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 13, color: AppPalette.textMuted, height: 1.5)),
        ],
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppPalette.textMuted,
            letterSpacing: 0.8),
      );
}

class _SelectableCard extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  final IconData icon;
  final String title, subtitle;
  const _SelectableCard({
    required this.active,
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: active ? AppPalette.primarySoft : AppPalette.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: active ? AppPalette.primary : AppPalette.border,
                width: 1.5),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: AppPalette.primary.withValues(alpha: 0.12),
                        blurRadius: 0,
                        spreadRadius: 4)
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: active ? AppPalette.primary : AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon,
                    size: 22, color: active ? Colors.white : AppPalette.text),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: active
                                ? AppPalette.primaryDark
                                : AppPalette.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppPalette.textMuted)),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppPalette.primary : AppPalette.card,
                  border: Border.all(
                      color: active ? AppPalette.primary : AppPalette.border,
                      width: 2),
                ),
                child: active
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      );
}

class _DocUploadCard extends StatelessWidget {
  final PlatformFile? file;
  final String label, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _DocUploadCard({
    required this.file,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final done = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: done ? AppPalette.primary : AppPalette.border,
              width: 1.5),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 120,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (done && file!.path != null)
                    Image.file(File(file!.path!), fit: BoxFit.cover)
                  else
                    Container(
                      color: AppPalette.bgSoft,
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 30, color: AppPalette.textMuted),
                          SizedBox(height: 6),
                          Text('TOUCHER POUR SÉLECTIONNER',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textMuted)),
                        ],
                      ),
                    ),
                  if (done)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppPalette.primary),
                        child: const Icon(Icons.check,
                            size: 15, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppPalette.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 1),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 11, color: AppPalette.textMuted)),
                      ],
                    ),
                  ),
                  if (done)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppPalette.primarySoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text('OK',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppPalette.primaryDark)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccentNote extends StatelessWidget {
  final IconData icon;
  final String text;
  const _AccentNote({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.accentSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: const Color(0xFF8E5A00)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 11.5, color: Color(0xFF8E5A00), height: 1.5)),
            ),
          ],
        ),
      );
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border),
          ),
          child: Icon(icon, size: 20, color: AppPalette.text),
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
          color: AppPalette.dangerSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppPalette.danger.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppPalette.danger),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: const TextStyle(
                        color: AppPalette.danger, fontSize: 13))),
          ],
        ),
      );
}

// ── Écran 6 : Succès ──────────────────────────────────────────────────────
class _SuccessScreen extends StatelessWidget {
  final VoidCallback onClose;
  const _SuccessScreen({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppPalette.primary, Color(0xFF063D27)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppPalette.accent,
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x80F59E0B),
                            blurRadius: 40,
                            offset: Offset(0, 20)),
                      ],
                    ),
                    child: const Icon(Icons.check,
                        size: 64, color: Color(0xFF1A0F00)),
                  ),
                ),
                const SizedBox(height: 28),
                const Text('Dossier envoyé !',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4)),
                const SizedBox(height: 10),
                const Text('Notre équipe vérifiera vos documents sous 24 h.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white70, fontSize: 14, height: 1.5)),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onClose,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.accent,
                      foregroundColor: const Color(0xFF1A0F00),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Retour à l\'accueil',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Signature pad (réutilisé, éprouvé) ────────────────────────────────────

class _SignaturePad extends StatefulWidget {
  const _SignaturePad({super.key, required this.onChanged});
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
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBF7),
        borderRadius: BorderRadius.circular(12),
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
                      style: TextStyle(color: AppPalette.textFaint)),
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
      ..color = AppPalette.text
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

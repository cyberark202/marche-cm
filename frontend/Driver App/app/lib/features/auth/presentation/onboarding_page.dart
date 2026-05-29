import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';
import '../application/auth_notifier.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _step = 0;
  String _docType = 'CNI';
  PlatformFile? _frontFile;
  PlatformFile? _backFile;
  PlatformFile? _licenseFile;
  bool _busy = false;
  String? _error;

  static const _docTypes = [
    ('CNI', "Carte nationale d'identité", Icons.credit_card),
    ('PASSPORT', 'Passeport', Icons.book_outlined),
  ];

  Future<void> _pick(String field) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
      withReadStream: true,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      if (field == 'front') _frontFile = result.files.first;
      if (field == 'back') _backFile = result.files.first;
      if (field == 'license') _licenseFile = result.files.first;
    });
  }

  Future<void> _submit() async {
    if (_frontFile == null) {
      setState(() => _error = 'Veuillez fournir une photo recto du document.');
      return;
    }
    if (_docType == 'CNI' && _backFile == null) {
      setState(() => _error = 'Veuillez fournir une photo verso de la CNI.');
      return;
    }
    if (_licenseFile == null) {
      setState(() => _error = 'Veuillez fournir une photo de votre permis.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      // Audit ref: [Front-Driver] no /api/accounts/driver-kyc/ exists.
      // Driver KYC documents (ID, license) are uploaded as regular
      // compliance documents — the admin reviews them and grants the
      // TRANSIT_AGENT role on approval. The backend stores one file per
      // document, so each photo is posted as its own compliance document.
      Future<void> upload(String docType, PlatformFile file) async {
        final form = FormData.fromMap({
          'doc_type': docType,
          'file': await MultipartFile.fromFile(file.path!, filename: file.name),
        });
        await DriverDioClient.dio.post('/api/compliance-documents/', data: form);
      }

      await upload(_docType, _frontFile!);
      if (_backFile != null) await upload('CNI_VERSO', _backFile!);
      await upload('DRIVER_LICENSE', _licenseFile!);
      await ref.read(authProvider.notifier).completeKyc();
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
      body: SafeArea(
        child: Column(
          children: [
            _Header(step: _step),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],
                    if (_step == 0) _StepWelcome(onNext: () => setState(() => _step = 1)),
                    if (_step == 1) _StepDocType(
                      selected: _docType,
                      docTypes: _docTypes,
                      onSelect: (t) => setState(() => _docType = t),
                      onNext: () => setState(() => _step = 2),
                    ),
                    if (_step == 2) _StepDocPhotos(
                      docType: _docType,
                      frontFile: _frontFile,
                      backFile: _backFile,
                      onPickFront: () => _pick('front'),
                      onPickBack: () => _pick('back'),
                      onNext: () => setState(() => _step = 3),
                    ),
                    if (_step == 3) _StepLicense(
                      licenseFile: _licenseFile,
                      onPick: () => _pick('license'),
                      busy: _busy,
                      onSubmit: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int step;
  const _Header({required this.step});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: T.gradientDriverHeader,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.local_shipping, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Market CM Driver',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: 12),
          const Text('Vérification d\'identité',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
          const SizedBox(height: 4),
          Text('Étape ${step + 1} sur 4',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (step + 1) / 4,
              backgroundColor: Colors.white.withValues(alpha: 0.3),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepWelcome extends StatelessWidget {
  final VoidCallback onNext;
  const _StepWelcome({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Bienvenue chez Market CM Driver !',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: DriverPalette.textPrimary)),
        const SizedBox(height: 12),
        Text(
          'Pour commencer à accepter des missions, nous devons vérifier votre identité. '
          'Cette vérification est obligatoire pour assurer la sécurité de la plateforme.',
          style: TextStyle(fontSize: 14, color: DriverPalette.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        _InfoCard(icon: Icons.credit_card, title: "Pièce d'identité",
            desc: "CNI ou Passeport valide"),
        const SizedBox(height: 10),
        const _InfoCard(icon: Icons.drive_eta, title: "Permis de conduire",
            desc: "Permis valide pour votre véhicule"),
        const SizedBox(height: 10),
        const _InfoCard(icon: Icons.timer_outlined, title: "Délai de vérification",
            desc: "24 à 48 heures ouvrables"),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton(
            onPressed: onNext,
            child: const Text('Commencer la vérification',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  const _InfoCard({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DriverPalette.border),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: DriverPalette.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: DriverPalette.primary, size: 20),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600,
              color: DriverPalette.textPrimary, fontSize: 14)),
          Text(desc, style: const TextStyle(fontSize: 12, color: DriverPalette.textSecondary)),
        ]),
      ]),
    );
  }
}

class _StepDocType extends StatelessWidget {
  final String selected;
  final List<(String, String, IconData)> docTypes;
  final ValueChanged<String> onSelect;
  final VoidCallback onNext;
  const _StepDocType({required this.selected, required this.docTypes,
      required this.onSelect, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text("Type de document", style: TextStyle(fontSize: 18,
            fontWeight: FontWeight.w700, color: DriverPalette.textPrimary)),
        const SizedBox(height: 8),
        const Text("Choisissez votre pièce d'identité principale.",
            style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary)),
        const SizedBox(height: 24),
        ...docTypes.map((d) {
          final sel = selected == d.$1;
          return GestureDetector(
            onTap: () => onSelect(d.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sel ? DriverPalette.primary.withValues(alpha: 0.07) : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? DriverPalette.primary : DriverPalette.border,
                    width: sel ? 2 : 1),
              ),
              child: Row(children: [
                Icon(d.$3, color: sel ? DriverPalette.primary : DriverPalette.textMuted, size: 26),
                const SizedBox(width: 14),
                Text(d.$2, style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 15,
                    color: sel ? DriverPalette.primary : DriverPalette.textPrimary)),
                const Spacer(),
                if (sel) const Icon(Icons.check_circle, color: DriverPalette.primary, size: 20),
              ]),
            ),
          );
        }),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton(onPressed: onNext,
              child: const Text('Continuer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
        ),
      ],
    );
  }
}

class _StepDocPhotos extends StatelessWidget {
  final String docType;
  final PlatformFile? frontFile, backFile;
  final VoidCallback onPickFront, onPickBack, onNext;
  const _StepDocPhotos({
    required this.docType, required this.frontFile, required this.backFile,
    required this.onPickFront, required this.onPickBack, required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final hasFront = frontFile != null;
    final hasBack = backFile != null;
    final canContinue = hasFront && (docType == 'PASSPORT' || hasBack);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text('Photos du ${docType == 'CNI' ? 'CNI' : 'Passeport'}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: DriverPalette.textPrimary)),
        const SizedBox(height: 20),
        _PhotoSlot(label: 'Recto', file: frontFile, onPick: onPickFront),
        if (docType == 'CNI') ...[
          const SizedBox(height: 12),
          _PhotoSlot(label: 'Verso', file: backFile, onPick: onPickBack),
        ],
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton(
            onPressed: canContinue ? onNext : null,
            child: const Text('Continuer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

class _StepLicense extends StatelessWidget {
  final PlatformFile? licenseFile;
  final VoidCallback onPick;
  final bool busy;
  final VoidCallback onSubmit;
  const _StepLicense({required this.licenseFile, required this.onPick,
      required this.busy, required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text('Permis de conduire',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: DriverPalette.textPrimary)),
        const SizedBox(height: 8),
        const Text('Photo claire recto de votre permis de conduire.',
            style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary)),
        const SizedBox(height: 20),
        _PhotoSlot(label: 'Permis de conduire', file: licenseFile, onPick: onPick),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton(
            onPressed: (licenseFile != null && !busy) ? onSubmit : null,
            child: busy
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Text('Envoyer pour vérification',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
      ],
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  final String label;
  final PlatformFile? file;
  final VoidCallback onPick;
  const _PhotoSlot({required this.label, required this.file, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final picked = file != null;
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: picked ? DriverPalette.primary.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: picked ? DriverPalette.primary : DriverPalette.border,
              width: picked ? 2 : 1,
              style: picked ? BorderStyle.solid : BorderStyle.solid),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(picked ? Icons.check_circle_outline : Icons.add_photo_alternate_outlined,
                size: 32, color: picked ? DriverPalette.primary : DriverPalette.textMuted),
            const SizedBox(height: 8),
            Text(picked ? file!.name : label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: picked ? FontWeight.w600 : FontWeight.w400,
                    color: picked ? DriverPalette.primary : DriverPalette.textSecondary)),
            if (!picked)
              const Text('Appuyez pour sélectionner',
                  style: TextStyle(fontSize: 11, color: DriverPalette.textMuted)),
          ]),
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

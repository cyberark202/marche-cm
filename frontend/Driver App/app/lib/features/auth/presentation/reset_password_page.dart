import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/theme/driver_theme.dart';
import '../infrastructure/driver_auth_api.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Forgot-password flow (2 steps): email → emailed code + new password.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

  Future<void> _requestCode() async {
    final email = _emailCtrl.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = 'Adresse email invalide.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await DriverAuthApi.requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() { _codeSent = true; _busy = false; });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Si un compte existe, un code vient d'être envoyé."),
        ),
      );
    } catch (e) {
      if (mounted) setState(() { _error = ApiError.friendly(e); _busy = false; });
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    final pass = _passCtrl.text;
    if (code.length < 4) {
      setState(() => _error = 'Saisissez le code reçu par email.');
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = 'Mot de passe trop court (8 caractères minimum).');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await DriverAuthApi.confirmPasswordReset(
        email: _emailCtrl.text.trim(), code: code, newPassword: pass);
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mot de passe réinitialisé. Connectez-vous.')),
      );
    } catch (e) {
      if (mounted) setState(() { _error = ApiError.friendly(e); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Mot de passe oublié'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _codeSent
                  ? 'Saisissez le code reçu par email et votre nouveau mot de passe.'
                  : "Saisissez l'email de votre compte. Nous vous enverrons un code.",
              style: const TextStyle(
                  fontSize: 14, color: DriverPalette.textSecondary),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.alertCircle, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626), fontSize: 13)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _emailCtrl,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(LucideIcons.atSign),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Code de réinitialisation',
                  prefixIcon: Icon(LucideIcons.mapPin),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Nouveau mot de passe',
                  prefixIcon: const Icon(LucideIcons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? LucideIcons.eye
                        : LucideIcons.eyeOff),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : (_codeSent ? _confirm : _requestCode),
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(
                        _codeSent
                            ? 'Réinitialiser le mot de passe'
                            : 'Envoyer le code',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _busy ? null : _requestCode,
                  child: const Text('Renvoyer un code'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

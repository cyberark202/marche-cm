import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'auth_api_service.dart';

/// Forgot-password flow (2 steps):
///   1. enter the account email → a 6-digit code is emailed;
///   2. enter the code + a new password.
class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key, this.initialEmail = ""});

  final String initialEmail;

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final AuthApiService _authApi = AuthApiService();
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  bool _passVisible = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(v.trim());

  Future<void> _requestCode() async {
    final email = _emailCtrl.text.trim();
    if (!_validEmail(email)) {
      setState(() => _error = "Adresse email invalide.");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _authApi.requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() => _codeSent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Si un compte existe, un code vient d'être envoyé par email.",
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _codeCtrl.text.trim();
    final pass = _passCtrl.text;
    if (code.length < 4) {
      setState(() => _error = "Saisissez le code reçu par email.");
      return;
    }
    if (pass.length < 8) {
      setState(() => _error = "Mot de passe trop court (8 caractères minimum).");
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _authApi.confirmPasswordReset(
        email: _emailCtrl.text.trim(),
        code: code,
        newPassword: pass,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mot de passe réinitialisé. Connectez-vous."),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        backgroundColor: AppPalette.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text("Mot de passe oublié"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _codeSent
                ? "Saisissez le code reçu par email et votre nouveau mot de passe."
                : "Saisissez l'adresse email de votre compte. Nous vous enverrons un code de réinitialisation.",
            style: const TextStyle(fontSize: 14, color: Color(0xFF526252)),
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
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626), fontSize: 13)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _emailCtrl,
            enabled: !_codeSent,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Email",
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Code de réinitialisation",
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _passCtrl,
              obscureText: !_passVisible,
              decoration: InputDecoration(
                labelText: "Nouveau mot de passe",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_passVisible
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _passVisible = !_passVisible),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppPalette.primary),
              onPressed: _busy ? null : (_codeSent ? _confirm : _requestCode),
              child: Text(
                _busy
                    ? "Veuillez patienter…"
                    : (_codeSent
                        ? "Réinitialiser le mot de passe"
                        : "Envoyer le code"),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _requestCode,
              child: const Text("Renvoyer un code"),
            ),
          ],
        ],
      ),
    );
  }
}

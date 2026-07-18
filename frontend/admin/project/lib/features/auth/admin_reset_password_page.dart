import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import 'auth_api_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

class AdminResetPasswordPage extends StatefulWidget {
  const AdminResetPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<AdminResetPasswordPage> createState() => _AdminResetPasswordPageState();
}

class _AdminResetPasswordPageState extends State<AdminResetPasswordPage> {
  final _auth = AuthApiService();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _codeSent = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _email.text = widget.initialEmail;
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validEmail(String v) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());

  Future<void> _requestCode() async {
    if (!_validEmail(_email.text)) {
      showSnack(context, 'Adresse email invalide.');
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.requestPasswordReset(email: _email.text.trim());
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _loading = false;
      });
      showSnack(context, "Si un compte existe, un code vient d'être envoyé.");
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length < 4) {
      showSnack(context, 'Saisissez le code reçu par email.');
      return;
    }
    if (_password.text.length < 8) {
      showSnack(context, 'Mot de passe trop court (8 caractères minimum).');
      return;
    }
    setState(() => _loading = true);
    try {
      await _auth.confirmPasswordReset(
        email: _email.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(context, 'Mot de passe réinitialisé. Connectez-vous.');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mot de passe oublié')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeSent
                        ? 'Saisissez le code reçu par email et votre nouveau mot de passe.'
                        : "Saisissez l'email de votre compte administrateur. Un code de réinitialisation vous sera envoyé.",
                    style: const TextStyle(color: AppPalette.textMuted),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    enabled: !_codeSent,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-mail professionnel',
                      prefixIcon: Icon(LucideIcons.mail),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Code de réinitialisation',
                        prefixIcon: Icon(LucideIcons.mapPin),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _obscure,
                      onSubmitted: (_) => _confirm(),
                      decoration: InputDecoration(
                        labelText: 'Nouveau mot de passe',
                        prefixIcon: const Icon(LucideIcons.lock),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? LucideIcons.eye
                              : LucideIcons.eyeOff),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed:
                        _loading ? null : (_codeSent ? _confirm : _requestCode),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text(_codeSent
                            ? 'Réinitialiser le mot de passe'
                            : 'Envoyer le code'),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loading ? null : _requestCode,
                      child: const Text('Renvoyer un code'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

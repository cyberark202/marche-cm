import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import 'auth_api_service.dart';
import 'session_store.dart';

/// Screen 02 — Admin login (email + password, security messaging).
class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _auth = AuthApiService();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _loading) return;
    setState(() => _loading = true);
    final session = context.read<AdminSessionStore>();
    try {
      final result = await _auth.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      final access = (result['access'] ?? '').toString();
      final refresh = (result['refresh'] ?? '').toString();
      var profile = result['user'];
      if (profile is! Map<String, dynamic>) {
        profile = await _auth.me();
      }
      final role = (profile['role'] ?? '').toString();
      if (role != 'GENERAL_ADMIN') {
        if (!mounted) return;
        showSnack(context,
            "Ce compte n'a pas accès à la console d'administration.");
        setState(() => _loading = false);
        return;
      }
      session.setSession(
        accessToken: access,
        refreshTokenValue: refresh.isEmpty ? null : refresh,
        profile: profile,
      );
    } catch (e) {
      if (!mounted) return;
      showSnack(context, e.toString().replaceFirst('Exception: ', ''));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: AppPalette.gradientPrimary,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: const Icon(Icons.shield_moon_outlined,
                              color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Marché CM',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              Text('Console d’administration',
                                  style: TextStyle(
                                      color: AppPalette.textMuted,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    const Text('Connectez-vous',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text(
                      'Accès réservé aux administrateurs Marché CM.',
                      style: TextStyle(color: AppPalette.textMuted),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'E-mail professionnel',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) =>
                          (v == null || !v.contains('@')) ? 'E-mail invalide' : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 4)
                          ? 'Mot de passe requis'
                          : null,
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                            )
                          : const Text('Se connecter'),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppPalette.infoSoft,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              size: 18, color: AppPalette.info),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Connexion chiffrée. Les actions financières exigent une vérification 2FA supplémentaire.',
                              style: TextStyle(
                                  fontSize: 12, color: AppPalette.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

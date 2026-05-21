import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'auth_api_service.dart';

class BuyerRegisterPage extends StatefulWidget {
  const BuyerRegisterPage({super.key});

  @override
  State<BuyerRegisterPage> createState() => _BuyerRegisterPageState();
}

class _BuyerRegisterPageState extends State<BuyerRegisterPage> {
  final _authApi = AuthApiService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final CountryService _countryService = CountryService();

  String _countryCode = 'CM';
  bool _busy = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  bool _acceptTerms = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().length < 2) return 'Nom complet requis (2 caractères min).';
    if (!_phoneCtrl.text.startsWith('+')) return 'Numéro au format international (ex: +237…).';
    if (_phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length < 8) return 'Numéro de téléphone invalide.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_emailCtrl.text.trim())) return 'Adresse email invalide.';
    if (_passCtrl.text.length < 8) return 'Mot de passe trop court (8 caractères min).';
    if (_passCtrl.text != _confirmPassCtrl.text) return 'Les mots de passe ne correspondent pas.';
    if (!_acceptTerms) return 'Veuillez accepter les conditions d\'utilisation.';
    return null;
  }

  Future<void> _register() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _authApi.register(
        name: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        countryCode: _countryCode,
        city: '',
        role: 'BUYER',
        companyName: '',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compte créé ! Connectez-vous pour continuer.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.of(context).pop(); // Back to login
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      setState(() { _error = raw; _busy = false; });
    }
  }

  void _pickCountry() {
    showCountryPicker(
      context: context,
      favorite: const ['CM', 'FR', 'BE', 'CA', 'US', 'GB'],
      showPhoneCode: false,
      countryListTheme: const CountryListThemeData(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        inputDecoration: InputDecoration(
          labelText: 'Rechercher un pays',
          prefixIcon: Icon(Icons.search),
        ),
      ),
      onSelect: (c) => setState(() => _countryCode = c.countryCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final country = _countryService.findByCode(_countryCode);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                    colors: [Color(0xFF0F766E), Color(0xFF059669)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.storefront, color: Colors.white, size: 17),
                            ),
                            const SizedBox(width: 8),
                            const Text('Market CM',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A))),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Créer un compte Acheteur',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Form ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Welcome card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF0F766E), Color(0xFF059669)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 28),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Rejoignez Market CM',
                                    style: TextStyle(color: Colors.white,
                                        fontWeight: FontWeight.w700, fontSize: 15)),
                                Text('Accédez à des milliers de produits camerounais',
                                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(_error!, style: const TextStyle(
                                color: Color(0xFFDC2626), fontSize: 13))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _field(label: 'Nom complet', icon: Icons.person_outline,
                        controller: _nameCtrl, hint: 'Ex: Jean Dupont',
                        action: TextInputAction.next),
                    const SizedBox(height: 12),
                    _field(label: 'Numéro de téléphone', icon: Icons.phone_outlined,
                        controller: _phoneCtrl, hint: 'Ex: +2376XXXXXXXX',
                        type: TextInputType.phone, action: TextInputAction.next),
                    const SizedBox(height: 12),
                    _field(label: 'Adresse email', icon: Icons.alternate_email,
                        controller: _emailCtrl, hint: 'exemple@email.com',
                        type: TextInputType.emailAddress, action: TextInputAction.next),
                    const SizedBox(height: 12),

                    // Country picker
                    GestureDetector(
                      onTap: _pickCountry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.public, color: AppPalette.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                country != null
                                    ? '${country.flagEmoji} ${country.name}'
                                    : 'Sélectionner un pays',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: country != null
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Password
                    _passwordField(
                      label: 'Mot de passe', controller: _passCtrl,
                      obscure: _obscurePass,
                      onToggle: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    const SizedBox(height: 12),
                    _passwordField(
                      label: 'Confirmer le mot de passe', controller: _confirmPassCtrl,
                      obscure: _obscureConfirm,
                      onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      action: TextInputAction.done,
                      onSubmit: (_) => _register(),
                    ),
                    const SizedBox(height: 16),

                    // Terms checkbox
                    GestureDetector(
                      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _acceptTerms,
                            onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                            activeColor: AppPalette.primary,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'J\'accepte les conditions d\'utilisation et la politique de confidentialité de Market CM.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _register,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white))
                            : const Text('Créer mon compte acheteur',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Déjà un compte ? ',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.maybePop(context),
                          child: const Text('Se connecter',
                              style: TextStyle(
                                  color: AppPalette.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required String label, required IconData icon,
    required TextEditingController controller, String? hint,
    TextInputType type = TextInputType.text,
    TextInputAction action = TextInputAction.next,
    VoidCallback? onSubmit,
  }) =>
      TextField(
        controller: controller,
        keyboardType: type,
        textInputAction: action,
        onSubmitted: onSubmit != null ? (_) => onSubmit() : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppPalette.primary, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5)),
        ),
      );

  Widget _passwordField({
    required String label, required TextEditingController controller,
    required bool obscure, required VoidCallback onToggle,
    TextInputAction action = TextInputAction.next,
    ValueChanged<String>? onSubmit,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscure,
        textInputAction: action,
        onSubmitted: onSubmit,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline, color: AppPalette.primary, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                size: 20, color: const Color(0xFF94A3B8)),
            onPressed: onToggle,
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5)),
        ),
      );
}

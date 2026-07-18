import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import 'auth_api_service.dart';
import 'session_store.dart';
import 'package:lucide_icons/lucide_icons.dart';

class SellerRegisterPage extends StatefulWidget {
  const SellerRegisterPage({super.key});

  @override
  State<SellerRegisterPage> createState() => _SellerRegisterPageState();
}

class _SellerRegisterPageState extends State<SellerRegisterPage> {
  final _authApi = AuthApiService();
  final _nameCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _airCtrl = TextEditingController();
  final _seaCtrl = TextEditingController();
  final CountryService _countryService = CountryService();

  String _countryCode = 'CM';
  // Compte « Vendeur » unifié : un seul type de compte professionnel (SUPPLIER).
  // Le choix Fournisseur/Grossiste a été supprimé. Les livreurs utilisent
  // l'application Market CM Driver.
  final String _role = 'SUPPLIER';
  bool _busy = false;
  bool _obscurePass = true;
  bool _acceptTerms = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _airCtrl.dispose();
    _seaCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().length < 2) return 'Nom complet requis.';
    if (_companyCtrl.text.trim().length < 2) return 'Nom de l\'entreprise requis.';
    if (!_phoneCtrl.text.startsWith('+')) return 'Numéro au format international (ex: +237…).';
    if (_phoneCtrl.text.replaceAll(RegExp(r'\D'), '').length < 8) return 'Numéro invalide.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_emailCtrl.text.trim())) {
      return 'Email invalide.';
    }
    if (_passCtrl.text.length < 8) return 'Mot de passe trop court (8 min).';
    if (_passCtrl.text != _confirmPassCtrl.text) return 'Mots de passe différents.';
    if (!_acceptTerms) return 'Acceptez les conditions d\'utilisation.';
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
      final payload = await _authApi.registerSeller(
        name: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        countryCode: _countryCode,
        city: _cityCtrl.text.trim(),
        role: _role,
        companyName: _companyCtrl.text.trim(),
      );
      if (!mounted) return;
      final access = (payload['access'] ?? '').toString();
      final refresh = (payload['refresh'] ?? '').toString();
      final user = payload['user'] is Map<String, dynamic>
          ? payload['user'] as Map<String, dynamic>
          : <String, dynamic>{};
      if (access.isEmpty) {
        // Defensive fallback (backend without token issuance): back to login.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Compte professionnel créé ! Connectez-vous.'),
            backgroundColor: Color(0xFF059669),
          ),
        );
        Navigator.of(context).pop();
        return;
      }
      // Auto-login: open the session; the root router lands the seller on the
      // dashboard (or the pending-verification screen until KYC is approved).
      final session = context.read<SessionStore>();
      session.setSession(
        accessToken: access,
        refreshTokenValue: refresh.isEmpty ? null : refresh,
        userRole: session.roleFromBackend((user['role'] ?? _role).toString()),
        currentUserId: user['id'] is int ? user['id'] as int : null,
        currentUsername: user['username']?.toString(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bienvenue ! Votre compte professionnel a été créé.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
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
          prefixIcon: Icon(LucideIcons.search),
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
            // ── Header ───────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 12, 20, 16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.arrowLeft),
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
                                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(LucideIcons.store, color: Colors.white, size: 17),
                            ),
                            const SizedBox(width: 8),
                            const Text('Market CM',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A))),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text('Créer un compte Vendeur / Pro',
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
                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],

                    // Personal info
                    const _SectionLabel(label: 'Informations personnelles'),
                    const SizedBox(height: 8),
                    _field(label: 'Nom complet du responsable', icon: LucideIcons.user,
                        ctrl: _nameCtrl, hint: 'Ex: Jean Dupont'),
                    const SizedBox(height: 10),
                    _field(label: 'Nom de l\'entreprise', icon: LucideIcons.building2,
                        ctrl: _companyCtrl, hint: 'Ex: Dupont SARL'),
                    const SizedBox(height: 16),

                    // Contact info
                    const _SectionLabel(label: 'Coordonnées'),
                    const SizedBox(height: 8),
                    _field(label: 'Téléphone', icon: LucideIcons.phone,
                        ctrl: _phoneCtrl, hint: '+2376XXXXXXXX',
                        type: TextInputType.phone),
                    const SizedBox(height: 10),
                    _field(label: 'Email professionnel', icon: LucideIcons.atSign,
                        ctrl: _emailCtrl, hint: 'contact@entreprise.com',
                        type: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _pickCountry,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.white, borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.globe, color: AppPalette.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      country != null
                                          ? '${country.flagEmoji} ${country.name}'
                                          : 'Pays',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: country != null
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF94A3B8),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(LucideIcons.chevronDown, color: Color(0xFF94A3B8)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(label: 'Ville', icon: LucideIcons.building2,
                              ctrl: _cityCtrl, hint: 'Ex: Douala'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Security
                    const _SectionLabel(label: 'Sécurité'),
                    const SizedBox(height: 8),
                    _passField(label: 'Mot de passe', ctrl: _passCtrl,
                        obscure: _obscurePass,
                        onToggle: () => setState(() => _obscurePass = !_obscurePass)),
                    const SizedBox(height: 10),
                    _passField(label: 'Confirmer', ctrl: _confirmPassCtrl,
                        obscure: _obscurePass,
                        onToggle: () => setState(() => _obscurePass = !_obscurePass),
                        action: TextInputAction.done),
                    const SizedBox(height: 16),

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
                              'J\'accepte les CGU et la politique de confidentialité. Je reconnais que Marché CM agit comme simple intermédiaire et agent de séquestre ; je reste seul responsable de la conformité et de la qualité des produits que je vends.',
                              style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _busy ? null : _register,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _busy
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Créer mon compte professionnel',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('Déjà un compte ? ',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                        GestureDetector(
                          onTap: () => Navigator.maybePop(context),
                          child: const Text('Se connecter',
                              style: TextStyle(color: AppPalette.primary,
                                  fontWeight: FontWeight.w600, fontSize: 14)),
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
    required TextEditingController ctrl, String? hint,
    TextInputType type = TextInputType.text,
    TextInputAction action = TextInputAction.next,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        textInputAction: action,
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          prefixIcon: Icon(icon, color: AppPalette.primary, size: 20),
          filled: true, fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppPalette.primary, width: 1.5)),
        ),
      );

  Widget _passField({
    required String label, required TextEditingController ctrl,
    required bool obscure, required VoidCallback onToggle,
    TextInputAction action = TextInputAction.next,
  }) =>
      TextField(
        controller: ctrl,
        obscureText: obscure,
        textInputAction: action,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(LucideIcons.lock, color: AppPalette.primary, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                size: 20, color: const Color(0xFF94A3B8)),
            onPressed: onToggle,
          ),
          filled: true, fillColor: Colors.white,
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

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: Color(0xFF94A3B8), letterSpacing: 0.5));
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
            const Icon(LucideIcons.alertCircle, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Expanded(child: Text(message,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
          ],
        ),
      );
}

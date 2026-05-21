import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import 'auth_api_service.dart';

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
  String _role = 'SUPPLIER';
  bool _busy = false;
  bool _obscurePass = true;
  bool _acceptTerms = false;
  String? _error;

  static const _roles = [
    ('SUPPLIER', 'Fournisseur', Icons.factory_outlined,
        'Produisez ou importez des marchandises'),
    ('WHOLESALER', 'Grossiste', Icons.store_outlined,
        'Vendez en grande quantité à des revendeurs'),
    ('TRANSIT_AGENT', 'Transitaire', Icons.local_shipping_outlined,
        'Gérez le transport et la logistique'),
  ];

  bool get _isTransit => _role == 'TRANSIT_AGENT';

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
    if (_isTransit) {
      if (double.tryParse(_airCtrl.text.trim()) == null) return 'Prix aérien invalide.';
      if (double.tryParse(_seaCtrl.text.trim()) == null) return 'Prix maritime invalide.';
    }
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
      await _authApi.register(
        name: _nameCtrl.text.trim(),
        phoneNumber: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        countryCode: _countryCode,
        city: _cityCtrl.text.trim(),
        role: _role,
        companyName: _companyCtrl.text.trim(),
        airPricePerKg: _isTransit ? double.tryParse(_airCtrl.text.trim()) : null,
        seaPricePerKg: _isTransit ? double.tryParse(_seaCtrl.text.trim()) : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Compte professionnel créé ! Connectez-vous.'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      Navigator.of(context).pop();
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
            // ── Header ───────────────────────────────────────
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
                                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.store, color: Colors.white, size: 17),
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
                    // Role selector
                    const Text('Type de profil professionnel',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: Color(0xFF334155))),
                    const SizedBox(height: 10),
                    ...(_roles.map((r) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _RoleCard(
                            role: r.$1, title: r.$2, icon: r.$3, desc: r.$4,
                            selected: _role == r.$1,
                            onTap: () => setState(() => _role = r.$1),
                          ),
                        ))),
                    const SizedBox(height: 16),

                    if (_error != null) ...[
                      _ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],

                    // Personal info
                    const _SectionLabel(label: 'Informations personnelles'),
                    const SizedBox(height: 8),
                    _field(label: 'Nom complet du responsable', icon: Icons.person_outline,
                        ctrl: _nameCtrl, hint: 'Ex: Jean Dupont'),
                    const SizedBox(height: 10),
                    _field(label: 'Nom de l\'entreprise', icon: Icons.business_outlined,
                        ctrl: _companyCtrl, hint: 'Ex: Dupont SARL'),
                    const SizedBox(height: 16),

                    // Contact info
                    const _SectionLabel(label: 'Coordonnées'),
                    const SizedBox(height: 8),
                    _field(label: 'Téléphone', icon: Icons.phone_outlined,
                        ctrl: _phoneCtrl, hint: '+2376XXXXXXXX',
                        type: TextInputType.phone),
                    const SizedBox(height: 10),
                    _field(label: 'Email professionnel', icon: Icons.alternate_email,
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
                                  Icon(Icons.public, color: AppPalette.primary, size: 20),
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
                                  const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _field(label: 'Ville', icon: Icons.location_city_outlined,
                              ctrl: _cityCtrl, hint: 'Ex: Douala'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Transit pricing
                    if (_isTransit) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Color(0xFF0369A1)),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('Renseignez vos tarifs de transport (XAF/kg)',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF0369A1))),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _field(label: 'Aérien (XAF/kg)', icon: Icons.flight_outlined,
                                ctrl: _airCtrl, hint: '5000',
                                type: const TextInputType.numberWithOptions(decimal: true)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _field(label: 'Maritime (XAF/kg)', icon: Icons.directions_boat_outlined,
                                ctrl: _seaCtrl, hint: '2000',
                                type: const TextInputType.numberWithOptions(decimal: true)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

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
                              'J\'accepte les conditions d\'utilisation et la politique de confidentialité.',
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
          prefixIcon: const Icon(Icons.lock_outline, color: AppPalette.primary, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
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

class _RoleCard extends StatelessWidget {
  final String role, title, desc;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _RoleCard({
    required this.role, required this.title, required this.icon,
    required this.desc, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF4F46E5).withValues(alpha: 0.05)
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF4F46E5).withValues(alpha: 0.1)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    color: selected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                    size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: selected
                                ? const Color(0xFF4F46E5)
                                : const Color(0xFF0F172A))),
                    Text(desc,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: Color(0xFF4F46E5), size: 18),
            ],
          ),
        ),
      );
}

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
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
            const SizedBox(width: 8),
            Expanded(child: Text(message,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
          ],
        ),
      );
}

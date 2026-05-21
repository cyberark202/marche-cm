import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/driver_theme.dart';
import '../application/auth_notifier.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final CountryService _cs = CountryService();
  String _countryCode = 'CM';
  String _vehicleType = 'MOTO';
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  static const _vehicles = [
    ('MOTO', 'Moto / Scooter', Icons.two_wheeler),
    ('CAR', 'Voiture', Icons.directions_car),
    ('VAN', 'Camionnette', Icons.airport_shuttle),
    ('TRUCK', 'Camion', Icons.local_shipping),
    ('BICYCLE', 'Vélo', Icons.pedal_bike),
    ('FOOT', 'À pied', Icons.directions_walk),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_nameCtrl.text.trim().length < 2) return 'Nom trop court.';
    if (!_phoneCtrl.text.startsWith('+')) return 'Téléphone au format international (ex: +237…).';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_emailCtrl.text.trim())) {
      return 'Email invalide.';
    }
    if (_passCtrl.text.length < 8) return 'Mot de passe trop court (8 min).';
    return null;
  }

  Future<void> _register() async {
    final err = _validate();
    if (err != null) { setState(() => _error = err); return; }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authProvider.notifier).register(
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        countryCode: _countryCode,
        vehicleType: _vehicleType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compte créé ! Connectez-vous.')),
      );
      context.go('/login');
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  void _pickCountry() => showCountryPicker(
        context: context,
        favorite: const ['CM', 'FR', 'SN', 'CI', 'GA'],
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

  @override
  Widget build(BuildContext context) {
    final country = _cs.findByCode(_countryCode);
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Créer un compte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: T.gradientPrimary,
                borderRadius: BorderRadius.circular(DriverRadii.md),
              ),
              child: const Row(
                children: [
                  Icon(Icons.local_shipping, color: Colors.white, size: 28),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Market CM Driver',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                      Text('Inscription Livreur',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
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
                child: Row(children: [
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            _label('Informations personnelles'),
            const SizedBox(height: 8),
            _tf(label: 'Nom complet', ctrl: _nameCtrl, icon: Icons.person_outline,
                hint: 'Ex: Jean Dupont'),
            const SizedBox(height: 12),
            _tf(label: 'Téléphone', ctrl: _phoneCtrl, icon: Icons.phone_outlined,
                hint: '+2376XXXXXXXX', type: TextInputType.phone),
            const SizedBox(height: 12),
            _tf(label: 'Email', ctrl: _emailCtrl, icon: Icons.alternate_email,
                hint: 'vous@email.com', type: TextInputType.emailAddress),
            const SizedBox(height: 12),

            // Country
            GestureDetector(
              onTap: _pickCountry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(DriverRadii.sm),
                  border: Border.all(color: DriverPalette.border),
                ),
                child: Row(children: [
                  const Icon(Icons.public, color: DriverPalette.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      country != null
                          ? '${country.flagEmoji} ${country.name}'
                          : 'Sélectionner un pays',
                      style: TextStyle(
                        color: country != null ? DriverPalette.textPrimary : DriverPalette.textMuted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: DriverPalette.textMuted),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // Vehicle type
            _label('Type de véhicule'),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.4,
              children: _vehicles.map((v) {
                final sel = _vehicleType == v.$1;
                return GestureDetector(
                  onTap: () => setState(() => _vehicleType = v.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: sel ? DriverPalette.primary.withValues(alpha: 0.08) : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? DriverPalette.primary : DriverPalette.border,
                          width: sel ? 2 : 1),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(v.$3,
                          color: sel ? DriverPalette.primary : DriverPalette.textMuted, size: 22),
                      const SizedBox(height: 4),
                      Text(v.$2,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500,
                              color: sel ? DriverPalette.primary : DriverPalette.textSecondary)),
                    ]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            _label('Sécurité'),
            const SizedBox(height: 8),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _register(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _register,
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Créer mon compte livreur',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: DriverPalette.textMuted, letterSpacing: 0.5));

  Widget _tf({
    required String label, required TextEditingController ctrl,
    required IconData icon, String? hint,
    TextInputType type = TextInputType.text,
  }) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          prefixIcon: Icon(icon),
        ),
      );
}

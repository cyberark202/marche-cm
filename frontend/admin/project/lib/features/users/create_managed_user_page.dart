import 'package:flutter/material.dart';

import '../data/admin_repository.dart';

/// Screen 33b — Admin creates a managed business account.
/// The backend (`create_managed_user`) restricts roles to SUPPLIER /
/// WHOLESALER / TRANSIT_AGENT and forbids creating a GENERAL_ADMIN.
class CreateManagedUserPage extends StatefulWidget {
  const CreateManagedUserPage({super.key});

  @override
  State<CreateManagedUserPage> createState() => _CreateManagedUserPageState();
}

class _CreateManagedUserPageState extends State<CreateManagedUserPage> {
  final _repo = AdminRepository.instance;
  final _formKey = GlobalKey<FormState>();

  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _country = TextEditingController(text: 'CM');
  final _city = TextEditingController();
  final _airPrice = TextEditingController();
  final _seaPrice = TextEditingController();

  // Roles the admin is allowed to create (matches backend whitelist).
  static const _roles = <String, String>{
    'SUPPLIER': 'Fournisseur',
    'WHOLESALER': 'Grossiste',
    'TRANSIT_AGENT': 'Livreur',
  };
  String _role = 'SUPPLIER';
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [
      _username, _email, _password, _phone, _country, _city, _airPrice, _seaPrice
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isDriver => _role == 'TRANSIT_AGENT';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final payload = <String, dynamic>{
      'username': _username.text.trim(),
      'email': _email.text.trim(),
      'password': _password.text,
      'role': _role,
      'phone_number': _phone.text.trim(),
      'country_code': _country.text.trim().toUpperCase(),
      'city': _city.text.trim(),
    };
    if (_isDriver) {
      payload['air_price_per_kg'] = _airPrice.text.trim();
      payload['sea_price_per_kg'] = _seaPrice.text.trim();
    }
    setState(() => _busy = true);
    try {
      await _repo.createManagedUser(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compte créé.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_repo.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Champ requis' : null;

  String? _positive(String? v) {
    if (v == null || v.trim().isEmpty) return 'Champ requis';
    final n = double.tryParse(v.trim());
    if (n == null || n <= 0) return 'Valeur > 0 requise';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte géré')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rôle'),
              items: [
                for (final e in _roles.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _role = v ?? 'SUPPLIER'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(labelText: 'Nom du compte'),
              validator: (v) => (v == null || v.trim().length < 3)
                  ? '3 caractères minimum'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'E-mail invalide'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe (8 caractères min.)'),
              validator: (v) => (v == null || v.length < 8)
                  ? '8 caractères minimum'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Téléphone', hintText: '+2376...'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _country,
                    decoration: const InputDecoration(labelText: 'Pays'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'Ville'),
                    validator: _required,
                  ),
                ),
              ],
            ),
            if (_isDriver) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _airPrice,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Prix avion / kg (FCFA)'),
                validator: _positive,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _seaPrice,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Prix bateau / kg (FCFA)'),
                validator: _positive,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Créer le compte'),
            ),
          ],
        ),
      ),
    );
  }
}

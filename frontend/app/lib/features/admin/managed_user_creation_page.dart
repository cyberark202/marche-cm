import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';

class ManagedUserCreationPage extends StatefulWidget {
  const ManagedUserCreationPage({super.key});

  @override
  State<ManagedUserCreationPage> createState() =>
      _ManagedUserCreationPageState();
}

class _ManagedUserCreationPageState extends State<ManagedUserCreationPage> {
  final ApiService _api = ApiService();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _city = TextEditingController();
  final _airPricePerKg = TextEditingController(text: "3500");
  final _seaPricePerKg = TextEditingController(text: "1800");
  final CountryService _countryService = CountryService();
  List<Map<String, String>> _roleChoices = const [];
  String _roleValue = "";
  String _defaultCountryCode = "";
  String _countryCodeValue = "";
  bool _busy = false;
  int _defaultAirPricePerKg = 3500;
  int _defaultSeaPricePerKg = 1800;

  @override
  void initState() {
    super.initState();
    final deviceCountry =
        (WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? "")
            .trim()
            .toUpperCase();
    final fallbackCountry = _countryService.findByCode(deviceCountry) != null
        ? deviceCountry
        : "CM";
    _defaultCountryCode = fallbackCountry;
    _countryCodeValue = fallbackCountry;
    _loadUiConfig();
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _city.dispose();
    _airPricePerKg.dispose();
    _seaPricePerKg.dispose();
    super.dispose();
  }

  Future<void> _createManagedUser() async {
    if (_busy) return;
    final validationError = _validateInput();
    if (validationError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }
    final token = context.read<SessionStore>().token;
    final payload = <String, dynamic>{
      "username": _username.text.trim(),
      "email": _email.text.trim(),
      "password": _password.text.trim(),
      "role": _roleValue,
    };
    final selectedCountry = _countryCodeValue.trim().isNotEmpty
        ? _countryCodeValue.trim().toUpperCase()
        : _defaultCountryCode.trim().toUpperCase();
    if (_countryService.findByCode(selectedCountry) != null) {
      payload["country_code"] = selectedCountry;
    }
    if (_city.text.trim().isNotEmpty) {
      payload["city"] = _city.text.trim();
    }
    if (_roleValue == "TRANSIT_AGENT") {
      payload["air_price_per_kg"] =
          (double.tryParse(_airPricePerKg.text.trim().replaceAll(",", ".")) ??
                  0)
              .toStringAsFixed(2);
      payload["sea_price_per_kg"] =
          (double.tryParse(_seaPricePerKg.text.trim().replaceAll(",", ".")) ??
                  0)
              .toStringAsFixed(2);
    }
    setState(() => _busy = true);
    try {
      await _api.post("/api/users/create_managed_user/", payload, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Compte metier cree.")),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      final message = e
          .toString()
          .replaceFirst("Exception: ", "")
          .replaceFirst("POST /api/users/create_managed_user/ failed: ", "");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message.isEmpty ? "Creation impossible." : message)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateInput() {
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text.trim();
    final city = _city.text.trim();
    final selectedCountry = _countryCodeValue.trim().isNotEmpty
        ? _countryCodeValue.trim().toUpperCase()
        : _defaultCountryCode.trim().toUpperCase();

    if (username.length < 3) {
      return "Username invalide (3 caracteres minimum).";
    }
    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      return "Email invalide.";
    }
    if (password.length < 8) {
      return "Mot de passe trop court (8 caracteres minimum).";
    }
    if (city.length > 120) {
      return "Ville trop longue.";
    }
    if (_roleValue.isEmpty) {
      return "Selectionnez un role.";
    }
    if (_roleValue == "TRANSIT_AGENT") {
      final air =
          double.tryParse(_airPricePerKg.text.trim().replaceAll(",", "."));
      final sea =
          double.tryParse(_seaPricePerKg.text.trim().replaceAll(",", "."));
      if (air == null || air <= 0) {
        return "Prix/kg avion invalide (doit etre > 0).";
      }
      if (sea == null || sea <= 0) {
        return "Prix/kg bateau invalide (doit etre > 0).";
      }
    }
    if (_countryService.findByCode(selectedCountry) == null) {
      return "Selectionnez un pays valide.";
    }
    return null;
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final roles = BackendUiConfigService.instance
          .readChoiceList(config, ["choices", "managed_user_roles"]);
      final country = BackendUiConfigService.instance
          .readString(config, ["defaults", "country_code"]);
      final defaultAir = BackendUiConfigService.instance
          .readInt(config, ["defaults", "transport_air_price_per_kg"]);
      final defaultSea = BackendUiConfigService.instance
          .readInt(config, ["defaults", "transport_sea_price_per_kg"]);
      if (!mounted) return;
      var countryCode = country.trim().toUpperCase();
      if (_countryService.findByCode(countryCode) == null) {
        countryCode = "CM";
      }
      setState(() {
        _roleChoices = roles;
        _roleValue = roles.isEmpty ? "" : roles.first["value"]!;
        _defaultCountryCode = countryCode;
        _countryCodeValue =
            _countryCodeValue.isEmpty ? countryCode : _countryCodeValue;
        _defaultAirPricePerKg =
            defaultAir > 0 ? defaultAir : _defaultAirPricePerKg;
        _defaultSeaPricePerKg =
            defaultSea > 0 ? defaultSea : _defaultSeaPricePerKg;
        if (_airPricePerKg.text.trim().isEmpty ||
            _airPricePerKg.text == "3500") {
          _airPricePerKg.text = _defaultAirPricePerKg.toString();
        }
        if (_seaPricePerKg.text.trim().isEmpty ||
            _seaPricePerKg.text == "1800") {
          _seaPricePerKg.text = _defaultSeaPricePerKg.toString();
        }
      });
    } catch (_) {}
  }

  Country? _selectedCountry() {
    final code = _countryCodeValue.trim().isNotEmpty
        ? _countryCodeValue
        : _defaultCountryCode;
    return _countryService.findByCode(code.trim().toUpperCase());
  }

  void _openCountryPicker() {
    showCountryPicker(
      context: context,
      favorite: const ["CM", "FR", "BE", "CA", "CH", "US", "GB"],
      showPhoneCode: false,
      countryListTheme: const CountryListThemeData(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      onSelect: (country) {
        if (!mounted) return;
        setState(() => _countryCodeValue = country.countryCode);
      },
    );
  }

  Widget _countrySelectorField() {
    final country = _selectedCountry();
    final label = country == null
        ? "Selectionner un pays"
        : "${country.flagEmoji} ${country.name} (${country.countryCode})";
    return InkWell(
      onTap: _busy ? null : _openCountryPicker,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: "Pays",
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTransitRole = _roleValue == "TRANSIT_AGENT";
    return Scaffold(
      appBar: AppBar(title: const Text("Creation compte metier")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _HeaderCard(
            title: "Compte metier",
            subtitle:
                "Creez un compte fournisseur, grossiste ou transitaire depuis cet ecran.",
          ),
          const SizedBox(height: 10),
          _SectionCard(
            child: Column(
              children: [
                TextField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: "Username"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: "Email"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: "Mot de passe"),
                  obscureText: true,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _city,
                  decoration:
                      const InputDecoration(labelText: "Ville (optionnel)"),
                ),
                const SizedBox(height: 10),
                _countrySelectorField(),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _roleValue.isEmpty ? null : _roleValue,
                  items: _roleChoices
                      .map(
                        (role) => DropdownMenuItem<String>(
                          value: role["value"],
                          child: Text(role["label"] ?? role["value"]!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _roleValue = value ?? _roleValue),
                  decoration: const InputDecoration(labelText: "Role"),
                ),
                if (isTransitRole) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _airPricePerKg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Prix/kg avion (FCFA)",
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _seaPricePerKg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: "Prix/kg bateau (FCFA)",
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _createManagedUser,
                    child: Text(_busy ? "Creation..." : "Creer compte"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

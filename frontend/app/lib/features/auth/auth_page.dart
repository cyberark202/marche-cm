import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/backend_ui_config_service.dart';
import 'auth_api_service.dart';
import 'session_store.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final AuthApiService _authApi = AuthApiService();
  late final GoogleSignIn _googleSignIn;

  final _loginEmail = TextEditingController();
  final _loginPass = TextEditingController();

  final _regName = TextEditingController();
  final _regPhone = TextEditingController();
  final _regEmail = TextEditingController();
  final _regCity = TextEditingController();
  final _regPass = TextEditingController();
  final _regCompany = TextEditingController();
  final _regAirPrice = TextEditingController();
  final _regSeaPrice = TextEditingController();
  String _selectedRole = 'BUYER';
  final CountryService _countryService = CountryService();
  String _defaultCountryCode = "";
  String _regCountryCode = "";

  bool _busy = false;

  static const Color _brand = Color(0xFF1E8E4B);

  @override
  void initState() {
    super.initState();
    final deviceCountry = _deviceCountryCode();
    final defaultCountry = _countryService.findByCode(deviceCountry) != null
        ? deviceCountry
        : "CM";
    _defaultCountryCode = defaultCountry;
    _regCountryCode = defaultCountry;
    _loadUiConfig();
    _googleSignIn = GoogleSignIn(
      scopes: const ["email"],
      clientId:
          AppConfig.googleClientId.isEmpty ? null : AppConfig.googleClientId,
      serverClientId: AppConfig.googleServerClientId.isEmpty
          ? null
          : AppConfig.googleServerClientId,
    );
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final countryCode = BackendUiConfigService.instance.readString(
        config,
        ["defaults", "country_code"],
      );
      if (!mounted) {
        return;
      }
      _applyCountryDefaults(countryCode.toUpperCase());
    } catch (e) {
      debugPrint('[AuthPage] _loadUiConfig error: $e');
    }
  }

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPass.dispose();
    _regName.dispose();
    _regPhone.dispose();
    _regEmail.dispose();
    _regCity.dispose();
    _regPass.dispose();
    _regCompany.dispose();
    _regAirPrice.dispose();
    _regSeaPrice.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    final email = _loginEmail.text.trim();
    final password = _loginPass.text;
    if (email.isEmpty) {
      _showError(Exception("Saisissez votre email."));
      return;
    }
    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      _showError(Exception("Adresse email invalide."));
      return;
    }
    if (password.isEmpty) {
      _showError(Exception("Saisissez votre mot de passe."));
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = await _authApi.login(
        email: email,
        password: password,
      );
      final access = (payload["access"] ?? "").toString();
      final refresh = (payload["refresh"] ?? "").toString();
      if (access.isEmpty) {
        throw Exception("Token d'acces manquant.");
      }
      final user = payload["user"] is Map<String, dynamic>
          ? payload["user"] as Map<String, dynamic>
          : await _authApi.me(access);
      if (!mounted) return;
      final session = context.read<SessionStore>();
      session.setSession(
        accessToken: access,
        refreshTokenValue: refresh.isEmpty ? null : refresh,
        userRole: session.roleFromBackend((user["role"] ?? "BUYER").toString()),
        currentUserId: user["id"] is int ? user["id"] as int : null,
        currentUsername: user["username"]?.toString(),
      );
      unawaited(_resolveLocationWithoutGps(accessToken: access, user: user));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Connexion reussie.")));
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() async {
    if (_busy) return;
    final validationError = _validateRegisterInput();
    if (validationError != null) {
      _showError(Exception(validationError));
      return;
    }
    final selectedCountry = _regCountryCode.trim().isNotEmpty
        ? _regCountryCode
        : _defaultCountryCode;
    if (_countryService.findByCode(selectedCountry) == null) {
      _showError(Exception("Selectionnez un pays valide."));
      return;
    }
    setState(() => _busy = true);
    try {
      await _authApi.register(
        name: _regName.text.trim(),
        phoneNumber: _regPhone.text.trim(),
        email: _regEmail.text.trim(),
        password: _regPass.text,
        countryCode: selectedCountry.trim().toUpperCase(),
        city: _regCity.text.trim(),
        role: _selectedRole,
        companyName: _regCompany.text.trim(),
        airPricePerKg: _selectedRole == 'TRANSIT_AGENT'
            ? double.tryParse(_regAirPrice.text.trim())
            : null,
        seaPricePerKg: _selectedRole == 'TRANSIT_AGENT'
            ? double.tryParse(_regSeaPrice.text.trim())
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Inscription reussie. Vous pouvez vous connecter.")),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateRegisterInput() {
    final name = _regName.text.trim();
    final phone = _regPhone.text.trim();
    final email = _regEmail.text.trim();
    final password = _regPass.text;
    final city = _regCity.text.trim();
    final isBusiness = _selectedRole != 'BUYER';
    final isTransit = _selectedRole == 'TRANSIT_AGENT';

    if (name.length < 2) {
      return "Nom complet invalide (2 caracteres minimum).";
    }
    if (!phone.startsWith('+')) {
      return "Le numero doit commencer par un indicatif pays (ex: +237...).";
    }
    if (phone.replaceAll(RegExp(r"[^0-9]"), "").length < 8) {
      return "Numero de telephone invalide.";
    }
    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      return "Adresse email invalide.";
    }
    if (password.length < 8) {
      return "Mot de passe trop court (8 caracteres minimum).";
    }
    if (city.length > 120) {
      return "Ville trop longue.";
    }
    if (isBusiness && _regCompany.text.trim().length < 2) {
      return "Nom de l'entreprise requis (2 caracteres minimum).";
    }
    if (isTransit) {
      final air = double.tryParse(_regAirPrice.text.trim());
      if (air == null || air <= 0) {
        return "Prix transport aerien invalide (ex: 5000).";
      }
      final sea = double.tryParse(_regSeaPrice.text.trim());
      if (sea == null || sea <= 0) {
        return "Prix transport maritime invalide (ex: 2000).";
      }
    }
    return null;
  }

  Future<void> _loginWithGoogle() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (AppConfig.googleServerClientId.isEmpty &&
          AppConfig.googleClientId.isEmpty) {
        throw Exception(
            "Google non configure: ajoutez GOOGLE_SERVER_CLIENT_ID (et GOOGLE_CLIENT_ID pour iOS).");
      }
      await _googleSignIn.signOut();
      final account = await _googleSignIn.signIn();
      if (account == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Connexion Google annulee.")));
        return;
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw Exception(
            "Impossible d'obtenir le token Google. Configurez le client OAuth mobile.");
      }
      final payload = await _authApi.googleAuth(idToken: idToken);
      final access = (payload["access"] ?? "").toString();
      final refresh = (payload["refresh"] ?? "").toString();
      final user = payload["user"] is Map<String, dynamic>
          ? payload["user"] as Map<String, dynamic>
          : <String, dynamic>{};
      if (access.isEmpty) {
        throw Exception("Token d'acces manquant.");
      }
      if (!mounted) return;
      final session = context.read<SessionStore>();
      session.setSession(
        accessToken: access,
        refreshTokenValue: refresh.isEmpty ? null : refresh,
        userRole: session.roleFromBackend((user["role"] ?? "BUYER").toString()),
        currentUserId: user["id"] is int ? user["id"] as int : null,
        currentUsername: user["username"]?.toString(),
      );
      unawaited(_resolveLocationWithoutGps(accessToken: access, user: user));
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Connexion Google reussie.")));
    } catch (e) {
      if (!mounted) return;
      _showError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(Object error) {
    final raw = error.toString();
    final message = raw.contains("Connection refused") ||
            raw.contains("Failed host lookup") ||
            raw.contains("127.0.0.1")
        ? "Serveur inaccessible. Lancez le backend puis verifiez API_BASE_URL."
        : raw.replaceFirst("Exception: ", "");
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _resolveLocationWithoutGps({
    required String accessToken,
    required Map<String, dynamic> user,
  }) async {
    final hasLatitude = user["location_latitude"] != null;
    final hasLongitude = user["location_longitude"] != null;
    if (hasLatitude && hasLongitude) {
      return;
    }
    final currentCountry = (user["country_code"] ?? "").toString().trim();
    final guessedCountry =
        currentCountry.isNotEmpty ? "" : _deviceCountryCode();
    try {
      await _authApi.resolveLocation(
        accessToken: accessToken,
        countryCode: guessedCountry,
      );
    } catch (e) {
      debugPrint('[AuthPage] resolveLocation error: $e');
    }
  }

  String _deviceCountryCode() {
    final countryCode =
        (WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? "")
            .trim()
            .toUpperCase();
    if (countryCode.length == 2) {
      return countryCode;
    }
    return "";
  }

  void _applyCountryDefaults(String preferredCountryCode) {
    var candidate = preferredCountryCode.trim().toUpperCase();
    if (_countryService.findByCode(candidate) == null) {
      candidate = _deviceCountryCode();
    }
    if (_countryService.findByCode(candidate) == null) {
      candidate = "CM";
    }
    if (!mounted) return;
    setState(() {
      _defaultCountryCode = candidate;
      if (_regCountryCode.trim().isEmpty) {
        _regCountryCode = candidate;
      }
    });
  }

  Country? _selectedRegisterCountry() {
    final current = _regCountryCode.trim().isNotEmpty
        ? _regCountryCode
        : _defaultCountryCode;
    return _countryService.findByCode(current.trim().toUpperCase());
  }

  void _openCountryPicker() {
    showCountryPicker(
      context: context,
      favorite: const ["CM", "FR", "BE", "CA", "CH", "US", "GB"],
      showPhoneCode: false,
      countryListTheme: const CountryListThemeData(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        inputDecoration: InputDecoration(
          labelText: "Rechercher un pays",
          prefixIcon: Icon(Icons.search),
        ),
      ),
      onSelect: (country) {
        if (!mounted) return;
        setState(() => _regCountryCode = country.countryCode);
      },
    );
  }

  Widget _countryPickerField() {
    final country = _selectedRegisterCountry();
    final label = country == null
        ? "Selectionner un pays"
        : "${country.flagEmoji} ${country.name} (${country.countryCode})";
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _busy ? null : _openCountryPicker,
      child: InputDecorator(
        decoration: _fieldDecoration(
          label: "Pays de residence",
          icon: Icons.public,
          hint: "Selectionner",
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

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: _brand),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E2D8)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD8E2D8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _brand, width: 1.4),
      ),
    );
  }

  Widget _loginTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        TextField(
          controller: _loginEmail,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
          decoration: _fieldDecoration(
            label: "Email",
            icon: Icons.alternate_email,
            hint: "exemple@email.com",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _loginPass,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          decoration:
              _fieldDecoration(label: "Mot de passe", icon: Icons.lock_outline),
          obscureText: true,
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy ? null : _login,
            child: Text(_busy ? "Connexion..." : "Se connecter"),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: const BorderSide(color: Color(0xFFD5DFD5)),
            ),
            onPressed: _busy ? null : _loginWithGoogle,
            icon: const Icon(Icons.login),
            label: const Text("Continuer avec Google"),
          ),
        ),
      ],
    );
  }

  Widget _roleSelector() {
    const roles = [
      ('BUYER', 'Acheteur', Icons.shopping_bag_outlined),
      ('SUPPLIER', 'Fournisseur', Icons.factory_outlined),
      ('WHOLESALER', 'Grossiste', Icons.store_outlined),
      ('TRANSIT_AGENT', 'Transitaire', Icons.local_shipping_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Je suis :",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A4A3A),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: roles.map((r) {
            final isSelected = _selectedRole == r.$1;
            return GestureDetector(
              onTap: _busy ? null : () => setState(() => _selectedRole = r.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? _brand : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _brand : const Color(0xFFD5E0D5),
                  ),
                  boxShadow: isSelected
                      ? [BoxShadow(color: _brand.withValues(alpha: 0.2), blurRadius: 6, offset: const Offset(0, 2))]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(r.$3, size: 15,
                        color: isSelected ? Colors.white : const Color(0xFF4A6A4A)),
                    const SizedBox(width: 5),
                    Text(
                      r.$2,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : const Color(0xFF3A4A3A),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _registerTab() {
    final isBusiness = _selectedRole != 'BUYER';
    final isTransit = _selectedRole == 'TRANSIT_AGENT';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        // ── Role selector ──────────────────────────────────
        _roleSelector(),
        const SizedBox(height: 16),

        // ── Common fields ──────────────────────────────────
        TextField(
          controller: _regName,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: "Nom complet",
            icon: Icons.person_outline,
            hint: "Ex: Jean Dupont",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regPhone,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.phone,
          decoration: _fieldDecoration(
            label: "Numero de telephone",
            icon: Icons.phone_outlined,
            hint: "Ex: +2376XXXXXXXX",
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _regEmail,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
          decoration: _fieldDecoration(
            label: "Email",
            icon: Icons.alternate_email,
            hint: "exemple@email.com",
          ),
        ),
        const SizedBox(height: 12),
        _countryPickerField(),
        const SizedBox(height: 12),
        TextField(
          controller: _regCity,
          textInputAction: TextInputAction.next,
          decoration: _fieldDecoration(
            label: "Ville (optionnel)",
            icon: Icons.location_city_outlined,
            hint: "Ex: Douala",
          ),
        ),

        // ── Business fields ────────────────────────────────
        if (isBusiness) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _regCompany,
            textInputAction: TextInputAction.next,
            decoration: _fieldDecoration(
              label: "Nom de l'entreprise",
              icon: Icons.business_outlined,
              hint: "Ex: Société Dupont SARL",
            ),
          ),
        ],

        // ── Transit agent pricing ──────────────────────────
        if (isTransit) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F8F0),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB8D8B8)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14,
                    color: _brand.withValues(alpha: 0.8)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Renseignez vos tarifs de transport (XAF/kg)",
                    style: TextStyle(fontSize: 12, color: Color(0xFF3A5A3A)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _regAirPrice,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _fieldDecoration(
                    label: "Aerien (XAF/kg)",
                    icon: Icons.flight_outlined,
                    hint: "Ex: 5000",
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _regSeaPrice,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: _fieldDecoration(
                    label: "Maritime (XAF/kg)",
                    icon: Icons.directions_boat_outlined,
                    hint: "Ex: 2000",
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 12),
        TextField(
          controller: _regPass,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _register(),
          decoration:
              _fieldDecoration(label: "Mot de passe", icon: Icons.lock_outline),
          obscureText: true,
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brand,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy ? null : _register,
            child: Text(_busy ? "Inscription..." : "Creer mon compte"),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "En vous inscrivant, vous acceptez nos conditions d'utilisation.",
          style: TextStyle(color: Color(0xFF5A6A5A), fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F6F2),
        body: SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFF4F8F4), Color(0xFFE9F1EA)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          "Authentification",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF182118),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Connectez-vous rapidement pour acheter et vendre en toute confiance.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF526252),
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F5F0),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const TabBar(
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: _brand,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                            labelColor: Colors.white,
                            unselectedLabelColor: Color(0xFF4F5F4F),
                            tabs: [
                              Tab(text: "Connexion"),
                              Tab(text: "Inscription"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _loginTab(),
                              _registerTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

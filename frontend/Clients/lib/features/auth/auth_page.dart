import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/app_logo.dart';
import '../../core/app_theme.dart';
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
  final CountryService _countryService = CountryService();
  String _defaultCountryCode = "";
  String _regCountryCode = "";

  bool _busy = false;
  bool _showLogin = true;
  bool _acceptRegisterTerms = false;
  bool _loginPassVisible = false;
  bool _rememberMe = false;

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
      if (!mounted) return;
      _applyCountryDefaults(countryCode.toUpperCase());
    } catch (_) {}
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
    if (!_acceptRegisterTerms) {
      _showError(Exception(
          "Vous devez accepter les CGU et le statut d'intermédiaire pour continuer."));
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

    if (name.length < 2) return "Nom complet invalide (2 caracteres minimum).";
    if (!phone.startsWith('+')) {
      return "Le numero doit commencer par un indicatif pays (ex: +237...).";
    }
    if (phone.replaceAll(RegExp(r"[^0-9]"), "").length < 8) {
      return "Numero de telephone invalide.";
    }
    if (!RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(email)) {
      return "Adresse email invalide.";
    }
    if (password.length < 8) return "Mot de passe trop court (8 caracteres minimum).";
    if (city.length > 120) return "Ville trop longue.";
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
      if (access.isEmpty) throw Exception("Token d'acces manquant.");
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
    if (hasLatitude && hasLongitude) return;
    final currentCountry = (user["country_code"] ?? "").toString().trim();
    final guessedCountry =
        currentCountry.isNotEmpty ? "" : _deviceCountryCode();
    try {
      await _authApi.resolveLocation(
        accessToken: accessToken,
        countryCode: guessedCountry,
      );
    } catch (_) {}
  }

  String _deviceCountryCode() {
    final countryCode =
        (WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? "")
            .trim()
            .toUpperCase();
    if (countryCode.length == 2) return countryCode;
    return "";
  }

  void _applyCountryDefaults(String preferredCountryCode) {
    var candidate = preferredCountryCode.trim().toUpperCase();
    if (_countryService.findByCode(candidate) == null) {
      candidate = _deviceCountryCode();
    }
    if (_countryService.findByCode(candidate) == null) candidate = "CM";
    if (!mounted) return;
    setState(() {
      _defaultCountryCode = candidate;
      if (_regCountryCode.trim().isEmpty) _regCountryCode = candidate;
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

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppPalette.primary),
      suffixIcon: suffixIcon,
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
        borderSide: const BorderSide(color: AppPalette.primary, width: 1.4),
      ),
    );
  }

  Widget _logoWidget() {
    return const MarcheLogo(size: 32);
  }

  Widget _heroSection() {
    return Container(
      color: const Color(0xFF063D27),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _logoWidget(),
              const SizedBox(width: 8),
              const Text(
                "Marché.",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text("Mode invité →"),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            "Bonjour 👋",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: "Connectez-vous ",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
                TextSpan(
                  text: "pour commencer.",
                  style: TextStyle(
                    color: Color(0xFFF5B400),
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Achetez en gros ou en détail. Paiement Mobile Money sécurisé.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _loginForm() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 24),
        const Text(
          "E-mail",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A4A3A),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _loginEmail,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.emailAddress,
          decoration: _fieldDecoration(
            label: "",
            icon: Icons.alternate_email,
            hint: "exemple@email.com",
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Mot de passe",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF3A4A3A),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _loginPass,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _login(),
          obscureText: !_loginPassVisible,
          decoration: _fieldDecoration(
            label: "",
            icon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(
                _loginPassVisible ? Icons.visibility_off : Icons.visibility,
                color: Colors.grey,
              ),
              onPressed: () =>
                  setState(() => _loginPassVisible = !_loginPassVisible),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: _rememberMe,
              onChanged: (v) => setState(() => _rememberMe = v ?? false),
              activeColor: AppPalette.primary,
            ),
            const Text("Se souvenir", style: TextStyle(fontSize: 13)),
            const Spacer(),
            TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.primary,
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: const Text("Mot de passe oublié ?"),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy ? null : _login,
            child: Text(
              _busy ? "Connexion..." : "Se connecter →",
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                "OU CONTINUER AVEC",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD8E2D8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: _busy ? null : _loginWithGoogle,
                child: const Text(
                  "G  Google",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD8E2D8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {},
                child: const Text(
                  "📱 OTP SMS",
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _showLogin = false),
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: "Pas encore de compte ? ",
                    style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                  ),
                  TextSpan(
                    text: "S'inscrire",
                    style: TextStyle(
                      color: AppPalette.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _registerForm() {
    final country = _selectedRegisterCountry();
    final countryLabel = country == null
        ? "Selectionner un pays"
        : "${country.flagEmoji} ${country.name} (${country.countryCode})";

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        const SizedBox(height: 24),
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
            label: "Numéro de téléphone",
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
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy ? null : _openCountryPicker,
          child: InputDecorator(
            decoration: _fieldDecoration(
              label: "Pays de résidence",
              icon: Icons.public,
              hint: "Selectionner",
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    countryLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
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
        const SizedBox(height: 12),
        TextField(
          controller: _regPass,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _register(),
          obscureText: true,
          decoration: _fieldDecoration(
            label: "Mot de passe",
            icon: Icons.lock_outline,
          ),
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () =>
              setState(() => _acceptRegisterTerms = !_acceptRegisterTerms),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _acceptRegisterTerms,
                onChanged: (v) =>
                    setState(() => _acceptRegisterTerms = v ?? false),
                activeColor: AppPalette.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "J'accepte les CGU et la politique de confidentialité. Je reconnais que Marché CM agit comme simple intermédiaire de mise en relation et agent de séquestre, et n'est ni vendeur, ni transporteur des biens.",
                  style: TextStyle(
                      fontSize: 12.5, color: Color(0xFF5A6A5A), height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _busy ? null : _register,
            child: Text(
              _busy ? "Inscription..." : "Créer mon compte →",
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _showLogin = true),
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: "Déjà un compte ? ",
                    style: TextStyle(color: Color(0xFF666666), fontSize: 14),
                  ),
                  TextSpan(
                    text: "Se connecter",
                    style: TextStyle(
                      color: AppPalette.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Column(
        children: [
          _heroSection(),
          // Coin arrondi bas sur le fond vert
          Container(
            height: 24,
            color: const Color(0xFF063D27),
            child: Container(
              decoration: const BoxDecoration(
                color: AppPalette.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
          ),
          Expanded(
            child: _showLogin ? _loginForm() : _registerForm(),
          ),
        ],
      ),
    );
  }
}

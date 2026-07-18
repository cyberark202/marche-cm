import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  // Build-time injection: --dart-define=API_BASE_URL=http://localhost:8000
  // The key MUST be the identifier "API_BASE_URL", not a URL literal.
  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://cm.digital-get.com",
  );

  static String get apiBaseUrl {
    if (_apiBaseUrlFromEnv.isNotEmpty) {
      return _apiBaseUrlFromEnv;
    }
    if (kIsWeb) {
      return "https://cm.digital-get.com";
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return "https://cm.digital-get.com";
    }
    return "https://cm.digital-get.com";
  }

  // Site vitrine public (partage produit, téléchargement app). Un lien produit
  // profond nécessitera une route web /p/{id} côté vitrine (follow-up infra).
  static const String siteUrl = String.fromEnvironment(
    "SITE_URL",
    defaultValue: "https://marketcm.com",
  );

  // Identité de l'app pour la gouvernance runtime (/api/app/runtime-config/).
  // appVersion DOIT rester aligné sur la version de pubspec.yaml (sans le +build).
  static const String appId = "clients";
  static const String appVersion = "0.1.0";

  static const String googleClientId = String.fromEnvironment(
    "GOOGLE_CLIENT_ID",
    defaultValue: "",
  );

  static const String googleServerClientId = String.fromEnvironment(
    "GOOGLE_SERVER_CLIENT_ID",
    defaultValue: "",
  );

  static const bool _authBypassFromEnv = bool.fromEnvironment(
    "AUTH_BYPASS",
    defaultValue: false,
  );

  static bool get authBypass => _authBypassFromEnv && !kReleaseMode;

  static const String authBypassToken = String.fromEnvironment(
    "AUTH_BYPASS_TOKEN",
    defaultValue: "",
  );
}

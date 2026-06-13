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

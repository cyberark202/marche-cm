import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "https://marche-cm.onrender.com",
    defaultValue: "https://marche-cm.onrender.com",
  );

  static String get apiBaseUrl {
    if (_apiBaseUrlFromEnv.isNotEmpty) {
      return _apiBaseUrlFromEnv;
    }
    if (kIsWeb) {
      return "https://marche-cm.onrender.com";
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return "https://marche-cm.onrender.com";
    }
    return "https://marche-cm.onrender.com";
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

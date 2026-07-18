import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://cm.digital-get.com",
  );

  static const String appId = "app";
  static const String appVersion = "0.1.0";

  static String get apiBaseUrl {
    final String url = _resolveBaseUrl();
    _assertHttpsInRelease(url);
    return url;
  }

  static String _resolveBaseUrl() {
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

  static void _assertHttpsInRelease(String url) {
    if (!kReleaseMode) return;
    if (url.startsWith("https://")) return;
    final host = Uri.tryParse(url)?.host ?? "";
    if (host == "127.0.0.1" || host == "localhost") return;
    throw StateError(
      "[AppConfig] API_BASE_URL must use HTTPS in release builds. "
      "Got: $url — build with --dart-define=API_BASE_URL=https://... "
      "to fix this.",
    );
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

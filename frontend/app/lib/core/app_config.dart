import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  // Build-time injection: --dart-define=API_BASE_URL=https://api.marche-cm.com
  // The key must be an identifier, NOT a URL string.
  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://cm.digital-get.com",
  );

  // Identité pour la gouvernance runtime (/api/app/runtime-config/).
  // appVersion DOIT rester aligné sur pubspec.yaml (sans le +build).
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
    // Development fallbacks — local dev server addresses.
    // These are intentionally HTTP because TLS is not available on loopback
    // during local development. _assertHttpsInRelease blocks them in release.
    if (kIsWeb) {
      return "https://cm.digital-get.com";
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 10.0.2.2 is the Android emulator's alias for the host machine.
      return "https://cm.digital-get.com";
    }
    // iOS simulator / desktop dev
    return "https://cm.digital-get.com";
  }

  // MITM protection: crash fast in release builds rather than silently
  // sending credentials over an unencrypted connection.
  // Loopback (127.0.0.1 / localhost) is exempt: traffic never leaves the
  // machine, so HTTP is safe there and local release testing stays possible.
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

  // Auth bypass is only available in debug/profile builds, never in release.
  static bool get authBypass => _authBypassFromEnv && !kReleaseMode;

  static const String authBypassToken = String.fromEnvironment(
    "AUTH_BYPASS_TOKEN",
    defaultValue: "",
  );
}

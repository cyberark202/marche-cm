import 'package:flutter/foundation.dart';

/// Centralised runtime configuration for the admin console.
///
/// The base URL is shared with the other Marché CM apps so the admin app
/// targets the exact same backend. Override at build time with:
///   --dart-define=API_BASE_URL=https://api.marche-cm.com
class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://marche-cm.onrender.com",
  );

  static String get apiBaseUrl {
    final String url = _apiBaseUrlFromEnv.isNotEmpty
        ? _apiBaseUrlFromEnv
        : "https://marche-cm.onrender.com";
    _assertHttpsInRelease(url);
    return url;
  }

  // MITM protection: crash fast in release builds rather than silently
  // sending admin credentials over an unencrypted connection.
  // Loopback (127.0.0.1 / localhost) is exempt: traffic never leaves the
  // machine, so HTTP is safe there and local release testing stays possible.
  static void _assertHttpsInRelease(String url) {
    if (!kReleaseMode) return;
    if (url.startsWith("https://")) return;
    final host = Uri.tryParse(url)?.host ?? "";
    if (host == "127.0.0.1" || host == "localhost") return;
    throw StateError(
      "[AppConfig] API_BASE_URL must use HTTPS in release builds. Got: $url",
    );
  }
}

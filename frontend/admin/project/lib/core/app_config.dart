import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const String _apiBaseUrlFromEnv = String.fromEnvironment(
    "API_BASE_URL",
    defaultValue: "https://cm.digital-get.com",
  );

  static const String appId = "admin";
  static const String appVersion = "1.0.0";

  static String get apiBaseUrl {
    final String url = _apiBaseUrlFromEnv.isNotEmpty
        ? _apiBaseUrlFromEnv
        : "https://cm.digital-get.com";
    _assertHttpsInRelease(url);
    return url;
  }

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

import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const String appId = 'driver';
  static const String appVersion = '1.0.0';

  static const String _prodBaseUrl = 'https://cm.digital-get.com';
  static const String _devBaseUrl = 'http://10.0.2.2:8000';

  static const String _apiBaseUrlFromEnv =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _wsBaseUrlFromEnv =
      String.fromEnvironment('WS_BASE_URL', defaultValue: '');

  static String get apiBaseUrl {
    final url = _apiBaseUrlFromEnv.isNotEmpty
        ? _apiBaseUrlFromEnv
        : (kDebugMode ? _devBaseUrl : _prodBaseUrl);
    _assertHttpsInRelease(url);
    return url;
  }

  static void _assertHttpsInRelease(String url) {
    if (kDebugMode) return;
    if (url.startsWith('https://')) return;
    final host = Uri.tryParse(url)?.host ?? '';
    if (host == '127.0.0.1' || host == 'localhost') return;
    throw StateError('[AppConfig] API_BASE_URL doit être en HTTPS en release. Reçu : $url');
  }

  static String get wsBaseUrl => _wsBaseUrlFromEnv.isNotEmpty
      ? _wsBaseUrlFromEnv
      : (kDebugMode ? 'ws://10.0.2.2:8000' : 'wss://cm.digital-get.com');

  static String get driverWsUrl => '$wsBaseUrl/ws/events/';

  static bool get isProduction => !kDebugMode;
}

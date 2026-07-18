import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  // Identité pour la gouvernance runtime (/api/app/runtime-config/).
  // appVersion DOIT rester aligné sur pubspec.yaml (sans le +build).
  static const String appId = 'driver';
  static const String appVersion = '1.0.0';

  static const String _prodBaseUrl = 'https://cm.digital-get.com';
  static const String _devBaseUrl = 'http://10.0.2.2:8000';

  // Build-time overrides (used for local web testing):
  //   --dart-define=API_BASE_URL=http://localhost:8000
  //   --dart-define=WS_BASE_URL=ws://localhost:8000
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

  // Protection MITM : en build release, refuser un backend non-HTTPS plutôt que
  // d'envoyer le token chauffeur en clair. Loopback exempté (trafic local).
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

  // M-5: there is no dedicated driver WebSocket route on the backend. Driver
  // realtime events (orders, logistics, notifications) are delivered over the
  // shared events stream (EventsConsumer), exactly like the buyer/seller apps.
  // Append `?token=<jwt>` (or send it via the `bearer` sub-protocol) when
  // opening the socket.
  static String get driverWsUrl => '$wsBaseUrl/ws/events/';

  static bool get isProduction => !kDebugMode;
}

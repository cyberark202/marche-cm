import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const String _prodBaseUrl = 'https://marche-cm.onrender.com';
  static const String _devBaseUrl = 'http://10.0.2.2:8000';

  // Build-time overrides (used for local web testing):
  //   --dart-define=API_BASE_URL=http://localhost:8000
  //   --dart-define=WS_BASE_URL=ws://localhost:8000
  static const String _apiBaseUrlFromEnv =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');
  static const String _wsBaseUrlFromEnv =
      String.fromEnvironment('WS_BASE_URL', defaultValue: '');

  static String get apiBaseUrl => _apiBaseUrlFromEnv.isNotEmpty
      ? _apiBaseUrlFromEnv
      : (kDebugMode ? _devBaseUrl : _prodBaseUrl);

  static String get wsBaseUrl => _wsBaseUrlFromEnv.isNotEmpty
      ? _wsBaseUrlFromEnv
      : (kDebugMode ? 'ws://10.0.2.2:8000' : 'wss://marche-cm.onrender.com');

  // M-5: there is no dedicated driver WebSocket route on the backend. Driver
  // realtime events (orders, logistics, notifications) are delivered over the
  // shared events stream (EventsConsumer), exactly like the buyer/seller apps.
  // Append `?token=<jwt>` (or send it via the `bearer` sub-protocol) when
  // opening the socket.
  static String get driverWsUrl => '$wsBaseUrl/ws/events/';

  static bool get isProduction => !kDebugMode;
}

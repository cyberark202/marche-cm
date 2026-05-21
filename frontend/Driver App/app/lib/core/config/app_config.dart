import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const String _prodBaseUrl = 'https://marche-cm.onrender.com';
  static const String _devBaseUrl = 'http://10.0.2.2:8000';

  static String get apiBaseUrl => kDebugMode ? _devBaseUrl : _prodBaseUrl;

  static String get wsBaseUrl =>
      kDebugMode ? 'ws://10.0.2.2:8000' : 'wss://marche-cm.onrender.com';

  static String get driverWsUrl => '$wsBaseUrl/ws/driver/';

  static bool get isProduction => !kDebugMode;
}

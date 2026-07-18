import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_token_manager.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

class PushNotificationService {
  PushNotificationService._();

  static String? _lastRegistered;

  static Future<void> initialize() async {
    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);
    messaging.onTokenRefresh.listen(_registerToken);
  }

  static Future<void> _registerToken(String fcmToken) async {
    if (_lastRegistered == fcmToken) return;
    try {
      final accessToken = AuthTokenManager.instance.accessToken;
      if (accessToken == null || accessToken.isEmpty) return;

      final deviceType = Platform.isIOS ? 'ios' : 'android';
      final resp = await http.post(
        Uri.parse('${AppConfig.apiBaseUrl}/api/auth/fcm-token/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'registration_id': fcmToken, 'type': deviceType}),
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _lastRegistered = fcmToken;
      }
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }
}

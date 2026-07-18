import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'security/secure_dio_client.dart';

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
      final deviceType = Platform.isIOS ? 'ios' : 'android';
      await SecureDioClient.dio.post(
        '/api/auth/fcm-token/',
        data: {'registration_id': fcmToken, 'type': deviceType},
      );
      _lastRegistered = fcmToken;
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }
}

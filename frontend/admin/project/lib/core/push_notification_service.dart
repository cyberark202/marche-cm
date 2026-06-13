import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'security/secure_dio_client.dart';

/// Must be a top-level function — the FCM background isolate cannot access
/// class state. Firebase is initialized by the system before this runs.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

/// FCM push notifications for the Admin console.
///
/// The admin console is web-first; Firebase web core initializes for the
/// shared marche-cm project. Web push requires a VAPID key + service worker
/// (not configured yet), so token retrieval is skipped on web. Native
/// platforms are not registered for the admin app (see firebase_options.dart).
class PushNotificationService {
  PushNotificationService._();

  static String? _lastRegistered;

  /// Call once after Firebase.initializeApp() and SecureDioClient.initialize().
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

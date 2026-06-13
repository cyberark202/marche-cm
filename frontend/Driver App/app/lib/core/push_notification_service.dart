import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'network/driver_dio_client.dart';

/// Must be a top-level function — the FCM background isolate cannot access
/// class state. Firebase is initialized by the system before this runs.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

/// FCM push notifications for the Driver app.
///
/// Realtime stays WebSocket-first; FCM adds wake-on-push for new assignments.
/// Web push needs a VAPID key + service worker (not configured yet), so token
/// retrieval is skipped on web; Firebase core still initializes.
class PushNotificationService {
  PushNotificationService._();

  static String? _lastRegistered;

  /// Call once after Firebase.initializeApp() and DriverDioClient.initialize().
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
      // DriverDioClient injects the Authorization header; the call is a no-op
      // server-side (401 ignored) until the driver is authenticated.
      await DriverDioClient.dio.post(
        '/api/auth/fcm-token/',
        data: {'registration_id': fcmToken, 'type': deviceType},
      );
      _lastRegistered = fcmToken;
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }
}

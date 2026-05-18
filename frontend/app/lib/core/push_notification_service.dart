import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'security/secure_dio_client.dart';

/// Must be a top-level function — FCM background isolate cannot access class state.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // Firebase is already initialized by the system before this runs.
  // System tray notification is shown automatically for notification+data messages.
  // Add local notification plugin calls here if you need custom presentation.
}

class PushNotificationService {
  PushNotificationService._();

  static const _kFcmTokenKey = 'sec.fcm_token';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Call once after Firebase.initializeApp() and SecureDioClient.initialize().
  static Future<void> initialize() async {
    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    final messaging = FirebaseMessaging.instance;

    // iOS / macOS: request permission. Android 13+ also respects this.
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await messaging.getToken();
    if (token != null) await _registerToken(token);

    // Re-register whenever FCM rotates the token.
    messaging.onTokenRefresh.listen(_registerToken);
  }

  static Future<void> _registerToken(String fcmToken) async {
    try {
      // Skip redundant API call if token hasn't changed.
      final cached = await _storage.read(key: _kFcmTokenKey);
      if (cached == fcmToken) return;

      final deviceType = kIsWeb
          ? 'web'
          : (Platform.isIOS ? 'ios' : 'android');

      await SecureDioClient.dio.post(
        '/api/auth/fcm-token/',
        data: {'registration_id': fcmToken, 'type': deviceType},
      );
      await _storage.write(key: _kFcmTokenKey, value: fcmToken);
    } catch (e) {
      debugPrint('[FCM] Token registration failed: $e');
    }
  }

  /// Call on logout so the backend stops delivering to this device.
  static Future<void> clearToken() async {
    try {
      final token = await _storage.read(key: _kFcmTokenKey);
      if (token != null && token.isNotEmpty) {
        await SecureDioClient.dio.delete(
          '/api/auth/fcm-token/',
          data: {'registration_id': token},
        );
      }
    } catch (_) {}
    await _storage.delete(key: _kFcmTokenKey);
  }
}

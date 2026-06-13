import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_token_manager.dart';

/// Must be a top-level function — the FCM background isolate cannot access
/// class state. Firebase is initialized by the system before this runs.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {}

/// FCM push notifications for the Clients (buyer) app.
///
/// Foreground/background message handling + device-token registration to the
/// backend. Web push requires a VAPID key + service worker (not configured
/// yet), so token retrieval is skipped on web; Firebase core still initializes.
class PushNotificationService {
  PushNotificationService._();

  // In-memory dedup: avoid re-POSTing the same token within a session.
  static String? _lastRegistered;

  /// Call once after Firebase.initializeApp().
  static Future<void> initialize() async {
    // Web push needs a VAPID key + firebase-messaging-sw.js — defer until set.
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

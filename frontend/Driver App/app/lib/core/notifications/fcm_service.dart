import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize({
    required Future<void> Function(String token) onTokenRefresh,
  }) async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await _messaging.getToken();
    if (token != null) {
      await onTokenRefresh(token);
    }

    _messaging.onTokenRefresh.listen((newToken) async {
      try {
        await onTokenRefresh(newToken);
      } catch (e) {
        debugPrint('[FcmService] token refresh error: $e');
      }
    });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FcmService] foreground message: ${message.notification?.title}');
    });
  }
}

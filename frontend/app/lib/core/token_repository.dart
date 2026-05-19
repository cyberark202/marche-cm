import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';

// Shared storage keys — never change these; they're persisted on-device.
const kTokenKeyAccess = 'sec.access_token';
const kTokenKeyRefresh = 'sec.refresh_token';
const kTokenKeyDeviceId = 'sec.device_id';

/// Single source of truth for token storage (Android Keystore / iOS Keychain).
///
/// All layers (Dio, SessionStore, PushNotificationService) read/write through
/// this class to avoid split-brain between multiple independent stores.
class TokenRepository {
  TokenRepository._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_OAEPwithSHA_256andMGF1Padding,
      storageCipherAlgorithm: StorageCipherAlgorithm.AES_GCM_NoPadding,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<String?> getAccessToken() => _storage.read(key: kTokenKeyAccess);
  static Future<String?> getRefreshToken() => _storage.read(key: kTokenKeyRefresh);

  static Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) {
    final ops = <Future>[
      _storage.write(key: kTokenKeyAccess, value: accessToken),
    ];
    if (refreshToken != null && refreshToken.isNotEmpty) {
      ops.add(_storage.write(key: kTokenKeyRefresh, value: refreshToken));
    }
    return Future.wait(ops);
  }

  static Future<void> clearTokens() => Future.wait([
        _storage.delete(key: kTokenKeyAccess),
        _storage.delete(key: kTokenKeyRefresh),
      ]);

  static Future<String> getOrCreateDeviceId() async {
    var id = await _storage.read(key: kTokenKeyDeviceId);
    if (id == null || id.isEmpty) {
      final rand = Random.secure();
      final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
      id = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      await _storage.write(key: kTokenKeyDeviceId, value: id);
    }
    return id;
  }

  /// Perform a token refresh against the backend.
  /// Returns the new access token on success, null on failure.
  static Future<({String? access, String? refresh})> refresh() async {
    final storedRefresh = await getRefreshToken();
    if (storedRefresh == null || storedRefresh.isEmpty) {
      return (access: null, refresh: null);
    }
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.apiBaseUrl}/api/auth/refresh/'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': storedRefresh}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccess = (data['access'] as String?)?.trim();
        final newRefresh = (data['refresh'] as String?)?.trim();
        if (newAccess != null && newAccess.isNotEmpty) {
          await saveTokens(accessToken: newAccess, refreshToken: newRefresh);
          return (access: newAccess, refresh: newRefresh);
        }
      }
    } catch (e) {
      debugPrint('[TokenRepository.refresh] network error: $e');
    }
    return (access: null, refresh: null);
  }
}

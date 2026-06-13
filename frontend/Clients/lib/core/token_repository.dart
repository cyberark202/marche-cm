import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// Shared storage keys — never change these; they're persisted on-device.
const kTokenKeyAccess = 'sec.access_token';
const kTokenKeyRefresh = 'sec.refresh_token';

/// Persistent token storage for the Clients (buyer) app — backed by the
/// Android Keystore / iOS Keychain (encrypted localStorage on web).
///
/// Token *refresh* is handled by [AuthTokenManager] (http-based), so this class
/// is intentionally storage-only: it survives app restarts so a returning user
/// is not forced to log in again. SessionStore reads/writes through here.
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
}

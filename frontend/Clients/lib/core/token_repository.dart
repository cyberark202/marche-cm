import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const kTokenKeyAccess = 'sec.access_token';
const kTokenKeyRefresh = 'sec.refresh_token';

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

  static Future<String?> getAccessToken() => _read(kTokenKeyAccess);
  static Future<String?> getRefreshToken() => _read(kTokenKeyRefresh);

  static Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('[TokenRepository] unreadable secure storage, purging: $e');
      try {
        await _storage.deleteAll();
      } catch (e) {
        debugPrint('[TokenRepository] purge failed: $e');
      }
      return null;
    }
  }

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

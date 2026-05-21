import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DriverSecureStorage {
  DriverSecureStorage._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAccess = 'driver_access_token';
  static const _kRefresh = 'driver_refresh_token';
  static const _kUserId = 'driver_user_id';
  static const _kUsername = 'driver_username';
  static const _kOnboarded = 'driver_onboarded';

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: access),
      _storage.write(key: _kRefresh, value: refresh),
    ]);
  }

  static Future<String?> getAccessToken() => _storage.read(key: _kAccess);
  static Future<String?> getRefreshToken() => _storage.read(key: _kRefresh);

  static Future<void> saveProfile({
    required int userId,
    required String username,
  }) async {
    await Future.wait([
      _storage.write(key: _kUserId, value: userId.toString()),
      _storage.write(key: _kUsername, value: username),
    ]);
  }

  static Future<int?> getUserId() async {
    final v = await _storage.read(key: _kUserId);
    return v != null ? int.tryParse(v) : null;
  }

  static Future<String?> getUsername() => _storage.read(key: _kUsername);

  static Future<void> setOnboarded(bool value) =>
      _storage.write(key: _kOnboarded, value: value.toString());

  static Future<bool> isOnboarded() async {
    final v = await _storage.read(key: _kOnboarded);
    return v == 'true';
  }

  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: _kAccess),
      _storage.delete(key: _kRefresh),
    ]);
  }

  static Future<void> clearAll() => _storage.deleteAll();
}

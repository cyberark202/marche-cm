import 'package:flutter/foundation.dart';
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

  // Coalesce concurrent reads of the same key into a single underlying
  // `_storage.read()` call. Right after login, the shell fires the dashboard's
  // first API call *and* opens the realtime WebSocket in the same frame — both
  // read the access token independently. On web those concurrent reads of the
  // same key can spuriously throw, which used to trip the corruption-purge
  // below and delete a token that had just been saved (instant logout right
  // after a successful login).
  static final Map<String, Future<String?>> _pendingReads = {};

  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    await Future.wait([
      _storage.write(key: _kAccess, value: access),
      _storage.write(key: _kRefresh, value: refresh),
    ]);
  }

  static Future<String?> getAccessToken() => _read(_kAccess);
  static Future<String?> getRefreshToken() => _read(_kRefresh);

  static Future<String?> _read(String key) {
    final pending = _pendingReads[key];
    if (pending != null) return pending;
    final future = _readOnce(key).whenComplete(() => _pendingReads.remove(key));
    _pendingReads[key] = future;
    return future;
  }

  // Web: a localStorage ciphertext that no longer matches the WebCrypto key
  // (key regenerated, port reused by another app) throws OperationError on
  // every read, blocking boot and all requests. Retry once first — a transient
  // error unrelated to real corruption must not nuke a valid session — then
  // purge and treat as logged out only if it fails twice.
  static Future<String?> _readOnce(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      try {
        return await _storage.read(key: key);
      } catch (e) {
        debugPrint('[DriverSecureStorage] unreadable secure storage, purging: $e');
        try {
          await _storage.deleteAll();
        } catch (e) {
          debugPrint('[DriverSecureStorage] purge failed: $e');
        }
        return null;
      }
    }
  }

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
    final v = await _read(_kUserId);
    return v != null ? int.tryParse(v) : null;
  }

  static Future<String?> getUsername() => _read(_kUsername);

  static Future<void> setOnboarded(bool value) =>
      _storage.write(key: _kOnboarded, value: value.toString());

  static Future<bool> isOnboarded() async {
    final v = await _read(_kOnboarded);
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

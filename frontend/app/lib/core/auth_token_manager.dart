import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';

typedef TokenGetter = String? Function();
typedef TokensRefreshedCallback = void Function(String accessToken, String? refreshToken);
typedef AuthFailedCallback = void Function();

class AuthTokenManager {
  AuthTokenManager._();

  static final AuthTokenManager instance = AuthTokenManager._();

  TokenGetter? _getAccessToken;
  TokenGetter? _getRefreshToken;
  TokensRefreshedCallback? _onTokensRefreshed;
  AuthFailedCallback? _onAuthFailed;
  final http.Client _client = http.Client();

  void configure({
    required TokenGetter getAccessToken,
    required TokenGetter getRefreshToken,
    required TokensRefreshedCallback onTokensRefreshed,
    required AuthFailedCallback onAuthFailed,
  }) {
    _getAccessToken = getAccessToken;
    _getRefreshToken = getRefreshToken;
    _onTokensRefreshed = onTokensRefreshed;
    _onAuthFailed = onAuthFailed;
  }

  String? get accessToken => _getAccessToken?.call();

  Future<String?> refreshAccessToken() async {
    final refresh = _getRefreshToken?.call();
    if (refresh == null || refresh.isEmpty) {
      _onAuthFailed?.call();
      return null;
    }
    try {
      final response = await _client.post(
        Uri.parse("${AppConfig.apiBaseUrl}/api/auth/refresh/"),
        headers: const {"Content-Type": "application/json"},
        body: jsonEncode({"refresh": refresh}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _onAuthFailed?.call();
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _onAuthFailed?.call();
        return null;
      }
      final newAccess = (decoded["access"] ?? "").toString();
      final newRefreshRaw = (decoded["refresh"] ?? "").toString();
      if (newAccess.isEmpty) {
        _onAuthFailed?.call();
        return null;
      }
      final newRefresh = newRefreshRaw.isEmpty ? null : newRefreshRaw;
      _onTokensRefreshed?.call(newAccess, newRefresh);
      return newAccess;
    } catch (_) {
      _onAuthFailed?.call();
      return null;
    }
  }
}

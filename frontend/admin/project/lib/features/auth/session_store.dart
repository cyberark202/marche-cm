import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../../core/security/secure_dio_client.dart';
import '../../core/token_repository.dart';

/// Admin session. Unlike the consumer apps, only GENERAL_ADMIN accounts are
/// allowed through — any other role is rejected at login and on restore.
class AdminSessionStore extends ChangeNotifier {
  String? token;
  String? refreshToken;
  int? userId;
  String? username;
  String? email;
  String? rawRole;
  String? _authNotice;

  Timer? _refreshTimer;

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  bool get isAdmin => rawRole == 'GENERAL_ADMIN';
  String? get authNotice => _authNotice;

  /// Cold-start restore: validates the stored token and confirms the account
  /// is still a GENERAL_ADMIN. Non-admin sessions are cleared.
  Future<void> restoreFromStorage() async {
    final stored = await TokenRepository.getAccessToken();
    if (stored == null || stored.isEmpty) return;
    try {
      final response = await SecureDioClient.dio.get('/api/auth/me/');
      final data = response.data;
      if (response.statusCode != 200 || data is! Map<String, dynamic>) {
        await TokenRepository.clearTokens();
        return;
      }
      final role = (data['role'] ?? '').toString();
      if (role != 'GENERAL_ADMIN') {
        await TokenRepository.clearTokens();
        _authNotice = "Ce compte n'a pas accès à la console d'administration.";
        return;
      }
      token = stored;
      refreshToken = await TokenRepository.getRefreshToken();
      _applyProfile(data);
    } on DioException {
      // Network error — keep token optimistically; first API call will surface.
      token = stored;
      refreshToken = await TokenRepository.getRefreshToken();
    } catch (_) {
      await TokenRepository.clearTokens();
      return;
    }
    _scheduleProactiveRefresh(stored);
    notifyListeners();
  }

  void setSession({
    required String accessToken,
    String? refreshTokenValue,
    required Map<String, dynamic> profile,
  }) {
    token = accessToken;
    refreshToken = refreshTokenValue;
    _applyProfile(profile);
    _authNotice = null;
    TokenRepository.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshTokenValue,
    );
    _scheduleProactiveRefresh(accessToken);
    notifyListeners();
  }

  void updateTokens({required String accessToken, String? refreshTokenValue}) {
    token = accessToken;
    if (refreshTokenValue != null && refreshTokenValue.isNotEmpty) {
      refreshToken = refreshTokenValue;
    }
    TokenRepository.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshTokenValue,
    );
    _scheduleProactiveRefresh(accessToken);
    notifyListeners();
  }

  void logout({String? notice}) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    token = null;
    refreshToken = null;
    userId = null;
    username = null;
    email = null;
    rawRole = null;
    _authNotice = notice;
    TokenRepository.clearTokens();
    notifyListeners();
  }

  String? consumeAuthNotice() {
    final value = _authNotice;
    _authNotice = null;
    return value;
  }

  void _applyProfile(Map<String, dynamic> data) {
    rawRole = (data['role'] ?? '').toString();
    userId = data['id'] is int ? data['id'] as int : int.tryParse('${data['id']}');
    final name = (data['username'] ?? data['name'] ?? '').toString().trim();
    username = name.isEmpty ? null : name;
    final mail = (data['email'] ?? '').toString().trim();
    email = mail.isEmpty ? null : mail;
  }

  // ── Proactive JWT refresh ────────────────────────────────────────────────

  void _scheduleProactiveRefresh(String accessToken) {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    final exp = _jwtExp(accessToken);
    if (exp == null) return;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    final refreshAt = expiresAt.subtract(const Duration(seconds: 60));
    final delay = refreshAt.difference(DateTime.now().toUtc());
    if (delay.inSeconds < 5) {
      _doRefresh();
      return;
    }
    _refreshTimer = Timer(delay, _doRefresh);
  }

  Future<void> _doRefresh() async {
    if (!isAuthenticated) return;
    final result = await TokenRepository.refresh();
    if (!isAuthenticated) return;
    if (result.access != null && result.access!.isNotEmpty) {
      token = result.access;
      if (result.refresh != null && result.refresh!.isNotEmpty) {
        refreshToken = result.refresh;
      }
      notifyListeners();
      _scheduleProactiveRefresh(result.access!);
    } else {
      logout(notice: 'Session expirée. Veuillez vous reconnecter.');
    }
  }

  static int? _jwtExp(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
        case 3:
          payload += '=';
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = json['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

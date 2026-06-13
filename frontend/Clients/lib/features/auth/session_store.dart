import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../core/auth_token_manager.dart';
import '../../core/token_repository.dart';
import 'auth_api_service.dart';

enum UserRole { generalAdmin, supplier, wholesaler, transitAgent, buyer }

class SessionStore extends ChangeNotifier {
  UserRole role = UserRole.buyer;
  String? token;
  String? refreshToken;
  int? userId;
  String? username;
  String? _authNotice;
  Locale appLocale = const Locale("fr");

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  String? get authNotice => _authNotice;

  /// Restores a persisted session on cold start so the user is not forced to
  /// log in again after closing the app. Reads tokens from secure storage and
  /// reloads the profile (role/userId/username) via `/api/auth/me/`.
  ///
  /// - Valid token  → profile loaded, session active.
  /// - Expired token → one silent refresh is attempted before giving up.
  /// - Network down  → tokens are kept optimistically (the first authenticated
  ///   screen will retry); we do NOT wipe a possibly-valid session offline.
  Future<void> restoreFromStorage() async {
    final stored = await TokenRepository.getAccessToken();
    if (stored == null || stored.isEmpty) return;
    token = stored;
    refreshToken = await TokenRepository.getRefreshToken();

    try {
      final data = await AuthApiService().me(stored);
      _applyUser(data);
      notifyListeners();
    } on http.ClientException {
      // Server unreachable — keep the stored tokens optimistically.
      notifyListeners();
    } catch (_) {
      // Likely an expired/invalid access token — attempt a single refresh.
      final newAccess = await AuthTokenManager.instance.refreshAccessToken();
      if (newAccess == null || newAccess.isEmpty) {
        // refreshAccessToken already invoked onAuthFailed -> logout() (cleared).
        return;
      }
      token = newAccess;
      try {
        final data = await AuthApiService().me(newAccess);
        _applyUser(data);
      } catch (_) {
        // Keep the freshly refreshed token; profile will load on next call.
      }
      notifyListeners();
    }
  }

  void _applyUser(Map<String, dynamic> data) {
    role = roleFromBackend((data["role"] ?? "").toString());
    final id = data["id"];
    userId = id is int ? id : int.tryParse("${id ?? ''}");
    final name = (data["username"] ?? data["name"] ?? "").toString().trim();
    username = name.isEmpty ? null : name;
  }

  void switchRole(UserRole newRole) {
    role = newRole;
    notifyListeners();
  }

  void setSession({
    required String accessToken,
    String? refreshTokenValue,
    required UserRole userRole,
    int? currentUserId,
    String? currentUsername,
  }) {
    token = accessToken;
    refreshToken = refreshTokenValue;
    role = userRole;
    userId = currentUserId;
    username = currentUsername;
    _authNotice = null;
    TokenRepository.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshTokenValue,
    );
    notifyListeners();
  }

  void updateTokens({
    required String accessToken,
    String? refreshTokenValue,
  }) {
    token = accessToken;
    if (refreshTokenValue != null && refreshTokenValue.isNotEmpty) {
      refreshToken = refreshTokenValue;
    }
    TokenRepository.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshTokenValue,
    );
    notifyListeners();
  }

  void updateProfile({
    String? currentUsername,
  }) {
    if (currentUsername != null && currentUsername.trim().isNotEmpty) {
      username = currentUsername.trim();
    }
    notifyListeners();
  }

  void logout({String? notice}) {
    token = null;
    refreshToken = null;
    userId = null;
    username = null;
    role = UserRole.buyer;
    _authNotice = notice;
    TokenRepository.clearTokens();
    notifyListeners();
  }

  void setLocale(String languageCode) {
    final code = languageCode.trim().toLowerCase();
    if (code != "fr" && code != "en") {
      return;
    }
    appLocale = Locale(code);
    notifyListeners();
  }

  String? consumeAuthNotice() {
    final value = _authNotice;
    _authNotice = null;
    return value;
  }

  UserRole roleFromBackend(String rawRole) {
    switch (rawRole) {
      case "GENERAL_ADMIN":
        return UserRole.generalAdmin;
      case "SUPPLIER":
        return UserRole.supplier;
      case "WHOLESALER":
        return UserRole.wholesaler;
      case "TRANSIT_AGENT":
        return UserRole.transitAgent;
      default:
        return UserRole.buyer;
    }
  }
}

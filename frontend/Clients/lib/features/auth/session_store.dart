import 'package:flutter/widgets.dart';

enum UserRole { generalAdmin, supplier, wholesaler, transitAgent, buyer }

class SessionStore extends ChangeNotifier {
  UserRole role = UserRole.buyer;
  String? token;
  String? refreshToken;
  int? userId;
  String? username;
  String? _authNotice;
  Locale appLocale = const Locale("fr");

  void switchRole(UserRole newRole) {
    role = newRole;
    notifyListeners();
  }

  bool get isAuthenticated => token != null && token!.isNotEmpty;
  String? get authNotice => _authNotice;

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

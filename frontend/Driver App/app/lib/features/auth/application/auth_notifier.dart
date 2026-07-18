import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_state.dart';
import '../infrastructure/driver_auth_api.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/security/driver_secure_storage.dart';

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    DriverDioClient.onAuthFailed = _onSessionExpired;
    _restore();
  }

  /// Un 401 dont le refresh a échoué = session morte : repasse au login
  /// immédiatement au lieu de laisser l'utilisateur dans le shell en erreur.
  void _onSessionExpired() {
    if (!mounted || !state.isAuthenticated) return;
    state = const AuthState(isLoading: false);
  }

  Future<void> _restore() async {
    final token = await DriverSecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      state = state.copyWith(isAuthenticated: false, isLoading: false);
      return;
    }

    // Valide la session auprès du backend avant d'entrer dans le shell : un
    // token périmé laissait l'utilisateur coincé sur des écrans en 401.
    // L'intercepteur tente un refresh transparent ; s'il échoue, il purge les
    // tokens — leur absence après l'appel est donc le signal « session morte ».
    // Backend injoignable (tokens toujours là) = session conservée.
    Map<String, dynamic>? me;
    try {
      me = await DriverAuthApi.me();
    } catch (e) {
      final remaining = await DriverSecureStorage.getAccessToken();
      if (remaining == null || remaining.isEmpty) {
        state = state.copyWith(isAuthenticated: false, isLoading: false);
        return;
      }
      debugPrint('[AuthNotifier] /me indisponible au restore: $e');
    }

    final userId = await DriverSecureStorage.getUserId();
    final username = await DriverSecureStorage.getUsername();
    var onboarded = await DriverSecureStorage.isOnboarded();
    // Reconnexion sur un nouvel appareil après validation KYC : le backend
    // fait foi quand le flag local dit "non onboardé".
    if (!onboarded && me != null && me['is_verified'] == true) {
      await DriverSecureStorage.setOnboarded(true);
      onboarded = true;
    }
    state = state.copyWith(
      isAuthenticated: true,
      isOnboarded: onboarded,
      userId: userId,
      username: username,
      isLoading: false,
    );
    // Hors-ligne au boot : re-vérifiera le statut KYC via le backend.
    if (!onboarded && me == null) _syncKycStatus();
  }

  Future<void> _syncKycStatus() async {
    try {
      final me = await DriverAuthApi.me();
      if (me['is_verified'] == true) {
        await DriverSecureStorage.setOnboarded(true);
        state = state.copyWith(isOnboarded: true);
      }
    } catch (_) {}
  }

  Future<void> login({required String email, required String password}) async {
    final payload = await DriverAuthApi.login(email: email, password: password);
    final access = (payload['access'] ?? '').toString();
    final refresh = (payload['refresh'] ?? '').toString();
    final user = payload['user'] is Map<String, dynamic>
        ? payload['user'] as Map<String, dynamic>
        : <String, dynamic>{};

    // ISOLATION: Market CM Driver est réservée aux chauffeurs (TRANSIT_AGENT).
    // Tout autre rôle est rejeté ici, même si l'authentification a réussi.
    final role = (user['role'] ?? '').toString();
    if (role != 'TRANSIT_AGENT') {
      await DriverSecureStorage.clearAll();
      throw Exception(
          "Ce compte n'est pas un compte chauffeur. Utilisez l'application correspondant à votre rôle.");
    }

    await DriverSecureStorage.saveTokens(
        access: access, refresh: refresh.isNotEmpty ? refresh : '');
    final userId = user['id'] is int ? user['id'] as int : null;
    final username = (user['username'] ?? user['name'] ?? '').toString();
    if (userId != null) {
      await DriverSecureStorage.saveProfile(
          userId: userId, username: username);
    }

    // Sync KYC status from the login payload so a driver reconnecting on a
    // new device (cleared storage) is not forced through onboarding again.
    final isVerified = user['is_verified'] == true;
    if (isVerified) await DriverSecureStorage.setOnboarded(true);
    final onboarded = isVerified || await DriverSecureStorage.isOnboarded();

    state = state.copyWith(
      isAuthenticated: true,
      isOnboarded: onboarded,
      userId: userId,
      username: username.isNotEmpty ? username : null,
      isLoading: false,
    );
  }

  Future<void> register({
    required String name,
    required String phone,
    required String email,
    required String password,
    required String countryCode,
    String? vehicleType,
  }) async {
    final payload = await DriverAuthApi.register(
      name: name,
      phoneNumber: phone,
      email: email,
      password: password,
      countryCode: countryCode,
      vehicleType: vehicleType,
    );

    // Auto-login: the backend forces the role to TRANSIT_AGENT and issues
    // tokens, so a freshly registered driver lands straight on the KYC
    // onboarding (router redirects to /onboarding because isOnboarded == false).
    final access = (payload['access'] ?? '').toString();
    final refresh = (payload['refresh'] ?? '').toString();
    if (access.isEmpty) return; // fallback: caller navigates to /login

    final user = payload['user'] is Map<String, dynamic>
        ? payload['user'] as Map<String, dynamic>
        : <String, dynamic>{};
    await DriverSecureStorage.saveTokens(
        access: access, refresh: refresh.isNotEmpty ? refresh : '');
    final userId = user['id'] is int ? user['id'] as int : null;
    final username = (user['username'] ?? user['name'] ?? '').toString();
    if (userId != null) {
      await DriverSecureStorage.saveProfile(userId: userId, username: username);
    }

    final onboarded = await DriverSecureStorage.isOnboarded();
    state = state.copyWith(
      isAuthenticated: true,
      isOnboarded: onboarded,
      userId: userId,
      username: username.isNotEmpty ? username : null,
      isLoading: false,
    );
  }

  Future<void> completeKyc() async {
    await DriverSecureStorage.setOnboarded(true);
    state = state.copyWith(isOnboarded: true);
  }

  Future<void> logout() async {
    await DriverSecureStorage.clearAll();
    state = const AuthState(isLoading: false);
  }
}

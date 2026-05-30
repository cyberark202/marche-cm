import 'package:dio/dio.dart';

import '../../core/security/secure_dio_client.dart';

class AuthApiService {
  static Dio get _dio => SecureDioClient.dio;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/auth/login/',
      data: {'email': email, 'password': password},
    );
    _assertOk(response);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Réponse de connexion invalide.');
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _dio.get('/api/auth/me/');
    _assertOk(response);
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Réponse profil invalide.');
  }

  Future<void> logout({required String refreshToken}) async {
    final response =
        await _dio.post('/api/auth/logout/', data: {'refresh': refreshToken});
    _assertOk(response);
  }

  /// Request a step-up verification code for a sensitive admin action.
  /// Returns the challenge token used to confirm the action.
  Future<String> requestSensitiveAction(String actionKey) async {
    final response = await _dio.post(
      '/api/auth/sensitive-action/request/',
      data: {'action_key': actionKey},
    );
    _assertOk(response);
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final token = (data['challenge_token'] ?? '').toString();
      if (token.isNotEmpty) return token;
    }
    throw Exception("Impossible d'initier la vérification de sécurité.");
  }

  static void _assertOk(Response response) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final data = response.data;
      String? detail;
      if (data is Map<String, dynamic>) {
        detail = data['detail']?.toString();
        if (detail == null && data.isNotEmpty) {
          final first = data.values.first;
          detail = first is List && first.isNotEmpty
              ? first.first.toString()
              : first.toString();
        }
      }
      throw Exception(detail ?? 'Erreur API ($status).');
    }
  }
}

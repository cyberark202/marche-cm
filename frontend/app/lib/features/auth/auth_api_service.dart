import 'package:dio/dio.dart';

import '../../core/security/secure_dio_client.dart';

class AuthApiService {
  static Dio get _dio => SecureDioClient.dio;

  Future<Map<String, dynamic>> registerSeller({
    required String name,
    required String phoneNumber,
    required String email,
    required String password,
    required String role,
    String countryCode = '',
    String city = '',
    String companyName = '',
  }) async {
    final payload = <String, dynamic>{
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'password': password,
      'role': role,
    };
    if (countryCode.trim().isNotEmpty) {
      payload['country_code'] = countryCode.trim().toUpperCase();
    }
    if (city.trim().isNotEmpty) payload['city'] = city.trim();
    if (companyName.trim().isNotEmpty) payload['company_name'] = companyName.trim();

    final response = await _dio.post('/api/auth/register/seller/', data: payload);
    _assertOk(response, 'registerSeller');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Reponse d\'inscription invalide.');
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post(
      '/api/auth/login/',
      data: {'email': email, 'password': password},
    );
    _assertOk(response, 'login');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Reponse de connexion invalide.');
  }

  Future<Map<String, dynamic>> googleAuth({required String idToken}) async {
    final response =
        await _dio.post('/api/auth/google/', data: {'id_token': idToken});
    _assertOk(response, 'googleAuth');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Reponse Google invalide.');
  }

  Future<Map<String, dynamic>> me(String accessToken) async {
    final response = await _dio.get('/api/auth/me/');
    _assertOk(response, 'me');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Reponse profil invalide.');
  }

  Future<void> requestPasswordReset({required String email}) async {
    final response = await _dio.post(
      '/api/auth/password/reset/request/',
      data: {'email': email.trim().toLowerCase()},
    );
    _assertOk(response, 'requestPasswordReset');
  }

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _dio.post(
      '/api/auth/password/reset/confirm/',
      data: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'new_password': newPassword,
      },
    );
    _assertOk(response, 'confirmPasswordReset');
  }

  Future<Map<String, dynamic>> resolveLocation({
    required String accessToken,
    String countryCode = '',
    String city = '',
  }) async {
    final payload = <String, dynamic>{};
    if (countryCode.trim().isNotEmpty) {
      payload['country_code'] = countryCode.trim().toUpperCase();
    }
    if (city.trim().isNotEmpty) payload['city'] = city.trim();

    final response =
        await _dio.post('/api/auth/location/resolve/', data: payload);
    _assertOk(response, 'resolveLocation');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('Reponse localisation invalide.');
  }

  Future<void> logout({
    required String refreshToken,
    String? accessToken,
  }) async {
    final response =
        await _dio.post('/api/auth/logout/', data: {'refresh': refreshToken});
    _assertOk(response, 'logout');
  }

  static void _assertOk(Response response, String label) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final data = response.data;
      String? detail;
      if (data is Map<String, dynamic>) {
        detail = data['detail']?.toString();
        if (detail == null && data.isNotEmpty) {
          final first = data.values.first;
          if (first is List && first.isNotEmpty) {
            detail = first.first.toString();
          } else {
            detail = first.toString();
          }
        }
      }
      throw Exception(detail ?? 'Erreur API ($status).');
    }
  }
}

import 'package:dio/dio.dart';

import '../../core/security/secure_dio_client.dart';

class AuthApiService {
  static Dio get _dio => SecureDioClient.dio;

  /// Professional self-registration — SUPPLIER / WHOLESALER only.
  ///
  /// ISOLATION: this app never creates buyer, driver or admin accounts. The
  /// backend endpoint `/api/auth/register/seller/` rejects any role outside
  /// {SUPPLIER, WHOLESALER}, so the server is the source of truth even if the
  /// client is tampered with.
  Future<void> registerSeller({
    required String name,
    required String phoneNumber,
    required String email,
    required String password,
    required String role, // 'SUPPLIER' | 'WHOLESALER'
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

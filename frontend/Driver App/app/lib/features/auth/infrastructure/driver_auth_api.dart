import '../../../core/network/driver_dio_client.dart';

class DriverAuthApi {
  DriverAuthApi._();

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final resp = await DriverDioClient.dio.post(
      '/api/auth/login/',
      data: {'email': email, 'password': password},
    );
    final data = resp.data;
    if (data is! Map<String, dynamic>) throw Exception('Réponse inattendue du serveur.');
    if ((data['access'] ?? '').toString().isEmpty) {
      throw Exception('Identifiants incorrects.');
    }
    return data;
  }

  /// Audit ref: [Front-Driver] backend exposes /api/auth/register/
  /// (config/urls.py:103). The previous /api/driver/register/ path does not
  /// exist server-side.
  ///
  /// The public register endpoint creates a BUYER. The driver role
  /// (TRANSIT_AGENT) is granted after KYC documents are reviewed and a
  /// TransportProfile is approved by admin. The `vehicleType` provided here
  /// is forwarded to a separate /api/transport-profiles/ call by the
  /// onboarding flow — not to the auth endpoint.
  static Future<Map<String, dynamic>> register({
    required String name,
    required String phoneNumber,
    required String email,
    required String password,
    required String countryCode,
    String? vehicleType,  // forwarded by caller to TransportProfile creation
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'password': password,
      'country_code': countryCode.toUpperCase(),
    };
    final resp = await DriverDioClient.dio.post('/api/auth/register/', data: body);
    final data = resp.data;
    if (resp.statusCode != 201 && resp.statusCode != 200) {
      throw Exception(data is Map ? _extractError(data) : 'Erreur lors de l\'inscription.');
    }
    return data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> me() async {
    final resp = await DriverDioClient.dio.get('/api/auth/me/');
    return resp.data as Map<String, dynamic>;
  }

  static String _extractError(Map data) {
    final errors = data['errors'] ?? data['detail'] ?? data['non_field_errors'];
    if (errors is List && errors.isNotEmpty) return errors.first.toString();
    if (errors is String) return errors;
    return 'Erreur lors de l\'inscription.';
  }
}

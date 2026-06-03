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

  /// Driver self-registration — dedicated, role-isolated endpoint.
  ///
  /// ISOLATION: `/api/auth/register/driver/` forces the role to TRANSIT_AGENT
  /// server-side (HiddenField) and provisions a TransportProfile. This app can
  /// therefore never create a buyer, seller or admin account. The agent is
  /// activated after KYC documents are reviewed; pricing is completed later.
  static Future<Map<String, dynamic>> register({
    required String name,
    required String phoneNumber,
    required String email,
    required String password,
    required String countryCode,
    String? vehicleType,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'phone_number': phoneNumber,
      'email': email,
      'password': password,
      'country_code': countryCode.toUpperCase(),
      if (vehicleType != null && vehicleType.trim().isNotEmpty)
        'vehicle_type': vehicleType.trim(),
    };
    final resp = await DriverDioClient.dio.post('/api/auth/register/driver/', data: body);
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

import 'dart:async';

import 'package:dio/dio.dart';

import 'security/secure_dio_client.dart';

/// Thin REST helper over the shared [SecureDioClient]. All admin screens go
/// through this so error handling and payload coercion stay consistent.
class ApiService {
  static Dio get _dio => SecureDioClient.dio;

  Future<List<Map<String, dynamic>>> getList(String path) async {
    final response = await _dio.get(path);
    _assertOk(response, 'GET $path');
    final data = response.data;
    if (data is List) {
      return data.whereType<Map<String, dynamic>>().toList();
    }
    if (data is Map<String, dynamic>) {
      final results = data['results'];
      if (results is List) {
        return results.whereType<Map<String, dynamic>>().toList();
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getObject(String path) async {
    final response = await _dio.get(path);
    _assertOk(response, 'GET $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('GET $path returned unexpected payload.');
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final response = await _dio.post(path, data: body);
    _assertOk(response, 'POST $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return {'ok': true};
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final response = await _dio.patch(path, data: body);
    _assertOk(response, 'PATCH $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return {'ok': true};
  }

  Future<String> downloadText(String path) async {
    final response = await _dio.get(
      path,
      options: Options(responseType: ResponseType.plain),
    );
    _assertOk(response, 'GET $path');
    return response.data?.toString() ?? '';
  }

  static void _assertOk(Response response, String label) {
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final data = response.data;
      final detail = data is Map
          ? (data['detail'] ?? data['message'] ?? '').toString().trim()
          : data?.toString().trim() ?? '';
      throw Exception(
          detail.isNotEmpty ? detail : 'Erreur $status. Réessayez.');
    }
  }

  String toUserMessage(
    Object error, {
    String fallback = 'Une erreur est survenue. Réessayez.',
  }) {
    if (error is TimeoutException) {
      return 'La requête a expiré. Vérifiez votre connexion et réessayez.';
    }
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    if (raw.isEmpty) return fallback;
    final lower = raw.toLowerCase();
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'Serveur inaccessible. Vérifiez votre connexion puis réessayez.';
    }
    return raw;
  }
}

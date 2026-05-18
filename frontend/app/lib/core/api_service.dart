import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import 'security/secure_dio_client.dart';

class ApiService {
  static Dio get _dio => SecureDioClient.dio;

  Future<List<Map<String, dynamic>>> getList(String path,
      {String? token}) async {
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

  Future<Map<String, dynamic>> getObject(String path, {String? token}) async {
    final response = await _dio.get(path);
    _assertOk(response, 'GET $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    throw Exception('GET $path returned unexpected payload.');
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {String? token}) async {
    final response = await _dio.post(path, data: body);
    _assertOk(response, 'POST $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return {'ok': true};
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body,
      {String? token}) async {
    final response = await _dio.patch(path, data: body);
    _assertOk(response, 'PATCH $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return {'ok': true};
  }

  Future<void> delete(String path, {String? token}) async {
    final response = await _dio.delete(path);
    _assertOk(response, 'DELETE $path');
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? token,
    PlatformFile? file,
    String fileFieldName = 'file',
  }) async {
    final formMap = <String, dynamic>{...fields};

    if (file != null) {
      final fileName = file.name.isEmpty ? 'upload.bin' : file.name;
      MultipartFile multipartFile;

      if (file.bytes != null && file.bytes!.isNotEmpty) {
        multipartFile =
            MultipartFile.fromBytes(file.bytes!, filename: fileName);
      } else if (!kIsWeb && (file.path ?? '').isNotEmpty) {
        multipartFile =
            await MultipartFile.fromFile(file.path!, filename: fileName);
      } else {
        final stream = file.readStream;
        if (stream == null) {
          throw Exception(
            'Le fichier sélectionné est inaccessible sur cette plateforme.',
          );
        }
        final chunks = <int>[];
        await for (final chunk in stream) {
          chunks.addAll(chunk);
        }
        multipartFile = MultipartFile.fromBytes(chunks, filename: fileName);
      }
      formMap[fileFieldName] = multipartFile;
    }

    final response =
        await _dio.post(path, data: FormData.fromMap(formMap));
    _assertOk(response, 'POST multipart $path');
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    return {'ok': true};
  }

  Future<String> downloadText(String path, {String? token}) async {
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
      throw Exception(detail.isNotEmpty ? detail : 'Erreur $status. Reessayez.');
    }
  }

  String toUserMessage(
    Object error, {
    String fallback = 'Une erreur est survenue. Reessayez.',
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
      return 'Serveur inaccessible. Verifiez votre connexion puis reessayez.';
    }

    return raw.isEmpty ? fallback : raw;
  }
}

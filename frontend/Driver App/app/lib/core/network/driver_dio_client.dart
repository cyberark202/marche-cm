import 'dart:async';

import 'package:dio/dio.dart';

import '../security/driver_secure_storage.dart';

class DriverDioClient {
  DriverDioClient._();

  static late final Dio _dio;
  static bool _initialized = false;
  static Completer<String?>? _refreshCompleter;

  static Dio get dio {
    assert(_initialized, 'Call DriverDioClient.initialize() in main()');
    return _dio;
  }

  static const String _baseUrl = String.fromEnvironment(
    'DRIVER_API_BASE_URL',
    defaultValue: 'https://marche-cm.onrender.com',
  );

  static Future<void> initialize() async {
    if (_initialized) return;

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'X-App-Client': 'driver',
      },
    ));

    _dio.interceptors.add(_AuthInterceptor());
    _initialized = true;
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await DriverSecureStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      handler.next(err);
      return;
    }

    // Prevent concurrent refresh races — Completer pattern
    if (DriverDioClient._refreshCompleter != null) {
      final newToken = await DriverDioClient._refreshCompleter!.future;
      if (newToken != null) {
        err.requestOptions.headers['Authorization'] = 'Bearer $newToken';
        final retry = await DriverDioClient._dio.fetch(err.requestOptions);
        handler.resolve(retry);
      } else {
        handler.next(err);
      }
      return;
    }

    DriverDioClient._refreshCompleter = Completer<String?>();
    try {
      final refreshToken = await DriverSecureStorage.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        DriverDioClient._refreshCompleter!.complete(null);
        await DriverSecureStorage.clearTokens();
        handler.next(err);
        return;
      }

      final response = await Dio().post(
        '${DriverDioClient._baseUrl}/api/accounts/token/refresh/',
        data: {'refresh': refreshToken},
      );
      final newAccess = (response.data['access'] ?? '').toString();
      if (newAccess.isEmpty) throw Exception('Empty access token');

      final newRefresh = (response.data['refresh'] ?? '').toString();
      await DriverSecureStorage.saveTokens(
          access: newAccess,
          refresh: newRefresh.isNotEmpty ? newRefresh : refreshToken);

      DriverDioClient._refreshCompleter!.complete(newAccess);
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retry = await DriverDioClient._dio.fetch(err.requestOptions);
      handler.resolve(retry);
    } catch (_) {
      DriverDioClient._refreshCompleter!.complete(null);
      await DriverSecureStorage.clearTokens();
      handler.next(err);
    } finally {
      DriverDioClient._refreshCompleter = null;
    }
  }
}

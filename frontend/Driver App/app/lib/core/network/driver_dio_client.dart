import 'dart:async';

import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../security/driver_secure_storage.dart';

class DriverDioClient {
  DriverDioClient._();

  static late final Dio _dio;
  static bool _initialized = false;
  static Completer<String?>? _refreshCompleter;

  static void Function()? onAuthFailed;

  static Dio get dio {
    assert(_initialized, 'Call DriverDioClient.initialize() in main()');
    return _dio;
  }

  static String get _baseUrl => AppConfig.apiBaseUrl;

  static Future<void> initialize() async {
    if (_initialized) return;

    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'X-App-Client': 'driver',
      },
    ));

    _dio.interceptors.add(_AuthInterceptor());
    _dio.interceptors.add(_ErrorSanitizerInterceptor());
    _initialized = true;
  }
}


class _ErrorSanitizerInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode ?? 0;
    String message;

    if (status == 401) {
      message = "Session expirée. Veuillez vous reconnecter.";
    } else if (status >= 400 && status < 500) {
      message = _serverDetail(err.response?.data) ??
          "La requête n'a pas pu être traitée. Veuillez réessayer.";
    } else if (status >= 500) {
      message = "Une erreur serveur est survenue. Veuillez réessayer plus tard.";
    } else {
      message = "Serveur momentanément injoignable. Veuillez réessayer.";
    }

    handler.reject(DioException(
      requestOptions: err.requestOptions,
      type: err.type,
      response: null,
      error: null,
      stackTrace: null,
      message: message,
    ));
  }

  static String? _serverDetail(dynamic data) {
    if (data is Map) {
      final raw = (data["detail"] ?? data["message"] ?? data["error"])
          ?.toString()
          .trim();
      if (raw != null && raw.isNotEmpty) return raw;
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) {
          final first = value.first?.toString().trim();
          if (first != null && first.isNotEmpty) return first;
        } else if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return null;
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
        DriverDioClient.onAuthFailed?.call();
        handler.next(err);
        return;
      }

      final response = await Dio().post(
        '${DriverDioClient._baseUrl}/api/auth/refresh/',
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
      DriverDioClient.onAuthFailed?.call();
      handler.next(err);
    } finally {
      DriverDioClient._refreshCompleter = null;
    }
  }
}

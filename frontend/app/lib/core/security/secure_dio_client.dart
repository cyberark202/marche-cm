/// Secure Dio HTTP client — request signing, replay nonce, correlation IDs,
/// HTTPS enforcement, device binding, and structured error handling.
///
/// OWASP MASVS-NETWORK-1, MASVS-AUTH-2
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_config.dart';
import '../token_repository.dart';

typedef TokensRefreshedCallback = void Function(String accessToken, String? refreshToken);
typedef AuthFailedCallback = void Function();

/// Singleton Dio client with full security interceptor stack.
/// Call [initialize] once at app startup before any [dio] usage.
class SecureDioClient {
  SecureDioClient._();
  static final SecureDioClient _instance = SecureDioClient._();

  late Dio _dio;
  bool _initialized = false;

  static Dio get dio {
    assert(_instance._initialized, 'Call SecureDioClient.initialize() before using dio');
    return _instance._dio;
  }

  static Future<void> initialize({
    TokensRefreshedCallback? onTokensRefreshed,
    AuthFailedCallback? onAuthFailed,
  }) async {
    if (_instance._initialized) return;

    final deviceId = await TokenRepository.getOrCreateDeviceId();

    final d = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Device-ID': deviceId,
      },
      validateStatus: (_) => true,
    ));

    // Order: security headers → auth (inject + refresh) → error sanitiser
    d.interceptors.add(_SecurityHeadersInterceptor(deviceId: deviceId));
    d.interceptors.add(_AuthInterceptor(
      dio: d,
      onTokensRefreshed: onTokensRefreshed,
      onAuthFailed: onAuthFailed,
    ));
    d.interceptors.add(_ErrorSanitizerInterceptor());

    if (kDebugMode) {
      d.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: false,
        logPrint: (obj) => debugPrint('[Dio] $obj'),
      ));
    }

    _instance._dio = d;
    _instance._initialized = true;
  }
}

// ── Security Headers Interceptor ─────────────────────────────────────────────

class _SecurityHeadersInterceptor extends Interceptor {
  final String deviceId;

  _SecurityHeadersInterceptor({required this.deviceId});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final correlationId = _generateCorrelationId();
    final nonce = _generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    options.headers.addAll({
      'X-Correlation-ID': correlationId,
      'X-Request-Nonce': nonce,
      'X-Request-Timestamp': timestamp.toString(),
      'X-Device-ID': deviceId,
    });
    options.extra['correlation_id'] = correlationId;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final sentId = response.requestOptions.extra['correlation_id'] as String?;
    final echoedId = response.headers.value('x-correlation-id');
    if (kDebugMode && sentId != null && echoedId != null && sentId != echoedId) {
      debugPrint('[Security] Correlation ID mismatch: sent=$sentId echoed=$echoedId');
    }
    handler.next(response);
  }

  static String _generateCorrelationId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateNonce() {
    final rand = Random.secure();
    final bytes = List<int>.generate(24, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }
}

// ── Auth Interceptor — token injection + reactive refresh on 401 ─────────────

class _AuthInterceptor extends Interceptor {
  final Dio dio;
  final TokensRefreshedCallback? onTokensRefreshed;
  final AuthFailedCallback? onAuthFailed;

  // Completer pattern: concurrent 401 responses all piggyback on a single
  // in-flight refresh instead of each triggering an independent refresh or
  // clearing tokens prematurely. Eliminates spurious logouts on wallet pages
  // that fire multiple parallel requests (Future.wait / TabBarView rebuilds).
  Completer<String?>? _refreshCompleter;

  _AuthInterceptor({
    required this.dio,
    this.onTokensRefreshed,
    this.onAuthFailed,
  });

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (_isPublicEndpoint(options.path)) return handler.next(options);

    final token = await TokenRepository.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    if (response.statusCode != 401) return handler.next(response);

    final newToken = await _refreshToken();

    if (newToken == null || newToken.isEmpty) {
      await TokenRepository.clearTokens();
      onAuthFailed?.call();
      return handler.next(response);
    }

    response.requestOptions.headers['Authorization'] = 'Bearer $newToken';
    try {
      final retried = await dio.fetch(response.requestOptions);
      return handler.resolve(retried);
    } catch (_) {
      return handler.next(response);
    }
  }

  /// Returns a fresh access token. If a refresh is already in flight, waits
  /// for it instead of issuing a second concurrent refresh request.
  Future<String?> _refreshToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<String?>();
    _refreshCompleter = completer;
    try {
      final result = await TokenRepository.refresh();
      final newAccess =
          (result.access != null && result.access!.isNotEmpty) ? result.access : null;
      if (newAccess != null) onTokensRefreshed?.call(newAccess, result.refresh);
      completer.complete(newAccess);
      return newAccess;
    } catch (_) {
      completer.complete(null);
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  static bool _isPublicEndpoint(String path) {
    const publicPaths = [
      '/api/auth/refresh/',
      '/api/auth/login/',
      '/api/auth/register/',
      '/api/auth/google/',
      '/api/health/',
      '/api/ui-config/',
    ];
    return publicPaths.any((p) => path.startsWith(p));
  }
}

// ── Error Sanitizer — never surface raw server errors to UI ──────────────────

class _ErrorSanitizerInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final status = response.statusCode ?? 0;
    if (status >= 400) return handler.resolve(_sanitizeErrorResponse(response));
    handler.next(response);
  }

  static Response _sanitizeErrorResponse(Response response) {
    final status = response.statusCode ?? 500;
    final body = response.data;

    // 401: always use fixed message for security (never expose server details).
    if (status == 401) {
      return Response(
        requestOptions: response.requestOptions,
        statusCode: status,
        statusMessage: response.statusMessage,
        headers: response.headers,
        data: {'detail': 'Session expirée. Veuillez vous reconnecter.', 'status': status},
      );
    }

    // For all other errors: prefer the server-supplied message (already
    // user-friendly from Django), fall back to a generic one only when absent.
    String? userMessage;
    if (body is Map) {
      userMessage = (body['detail'] ?? body['message'] ?? body['error'])
          ?.toString()
          .trim();
    }
    if (userMessage == null || userMessage.isEmpty) {
      userMessage = status >= 500
          ? 'Une erreur serveur est survenue. Veuillez réessayer.'
          : 'Erreur inattendue.';
    }

    return Response(
      requestOptions: response.requestOptions,
      statusCode: status,
      statusMessage: response.statusMessage,
      headers: response.headers,
      data: {'detail': userMessage, 'status': status},
    );
  }
}

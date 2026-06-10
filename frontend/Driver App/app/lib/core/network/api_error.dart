import 'package:dio/dio.dart';

/// Centralized, user-safe error mapping for the Driver app.
///
/// SECURITY: the UI must NEVER render a raw `DioException` / exception string.
/// Their `toString()` embeds the request URI and, on transport failures, the
/// underlying `SocketException` (which leaks the server host:port). Every error
/// shown to a driver is funnelled through [ApiError.friendly], which returns a
/// professional French message and never an endpoint, URL or server detail.
///
/// Works hand-in-hand with the sanitizer interceptor in [DriverDioClient]:
/// the interceptor strips technical fields and sets a clean `message`; this
/// helper reads that message (or falls back to a generic one).
class ApiError {
  const ApiError._();

  static const String _generic =
      "Une erreur est survenue. Veuillez réessayer plus tard.";

  static String friendly(Object? error) {
    if (error == null) return _generic;

    if (error is DioException) {
      final msg = error.message?.trim();
      // The interceptor already replaced this with a safe message; if anything
      // technical slipped through, fall back to the generic message.
      if (msg != null && msg.isNotEmpty && !_looksTechnical(msg)) return msg;
      return _generic;
    }

    var text = error.toString().trim();
    const prefix = "Exception: ";
    if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();

    if (text.isEmpty || _looksTechnical(text)) return _generic;
    return text;
  }

  /// True when a string still carries transport/stack/endpoint material that
  /// must not reach the user (URL, host lookup, socket, raw exception type).
  static bool _looksTechnical(String value) {
    final s = value.toLowerCase();
    return s.contains("://") ||
        s.contains("dioexception") ||
        s.contains("socketexception") ||
        s.contains("handshakeexception") ||
        s.contains("failed host lookup") ||
        s.contains("uri:") ||
        s.contains("localhost") ||
        s.contains("127.0.0.1") ||
        s.contains("statuscode");
  }
}

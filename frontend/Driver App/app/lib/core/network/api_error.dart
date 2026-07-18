import 'package:dio/dio.dart';

class ApiError {
  const ApiError._();

  static const String _generic =
      "Une erreur est survenue. Veuillez réessayer plus tard.";

  static String friendly(Object? error) {
    if (error == null) return _generic;

    if (error is DioException) {
      final msg = error.message?.trim();
      if (msg != null && msg.isNotEmpty && !_looksTechnical(msg)) return msg;
      return _generic;
    }

    var text = error.toString().trim();
    const prefix = "Exception: ";
    if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();

    if (text.isEmpty || _looksTechnical(text)) return _generic;
    return text;
  }

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

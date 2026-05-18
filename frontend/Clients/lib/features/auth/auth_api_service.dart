import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/app_config.dart';

class AuthApiService {
  AuthApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  Future<void> register({
    required String name,
    required String phoneNumber,
    required String email,
    required String password,
    String countryCode = "",
    String city = "",
  }) async {
    final payload = <String, dynamic>{
      "name": name,
      "phone_number": phoneNumber,
      "email": email,
      "password": password,
    };
    if (countryCode.trim().isNotEmpty) {
      payload["country_code"] = countryCode.trim().toUpperCase();
    }
    if (city.trim().isNotEmpty) {
      payload["city"] = city.trim();
    }
    final response = await _client.post(
      _uri("/api/auth/register/"),
      headers: const {"Content-Type": "application/json"},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      _uri("/api/auth/login/"),
      headers: const {"Content-Type": "application/json"},
      body: jsonEncode({"email": email, "password": password}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception("Reponse de connexion invalide.");
  }

  Future<Map<String, dynamic>> googleAuth({required String idToken}) async {
    final response = await _client.post(
      _uri("/api/auth/google/"),
      headers: const {"Content-Type": "application/json"},
      body: jsonEncode({"id_token": idToken}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception("Reponse Google invalide.");
  }

  Future<Map<String, dynamic>> me(String accessToken) async {
    final response = await _client.get(
      _uri("/api/auth/me/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception("Reponse profil invalide.");
  }

  Future<Map<String, dynamic>> resolveLocation({
    required String accessToken,
    String countryCode = "",
    String city = "",
  }) async {
    final payload = <String, dynamic>{};
    if (countryCode.trim().isNotEmpty) {
      payload["country_code"] = countryCode.trim().toUpperCase();
    }
    if (city.trim().isNotEmpty) {
      payload["city"] = city.trim();
    }
    final response = await _client.post(
      _uri("/api/auth/location/resolve/"),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception("Reponse localisation invalide.");
  }

  Future<void> logout({required String refreshToken, String? accessToken}) async {
    final response = await _client.post(
      _uri("/api/auth/logout/"),
      headers: {
        "Content-Type": "application/json",
        if (accessToken != null && accessToken.isNotEmpty) "Authorization": "Bearer $accessToken",
      },
      body: jsonEncode({"refresh": refreshToken}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(_extractError(response.body, response.statusCode));
    }
  }

  String _extractError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded["detail"]?.toString();
        if (detail != null && detail.isNotEmpty) {
          return detail;
        }
        if (decoded.entries.isNotEmpty) {
          final firstValue = decoded.entries.first.value;
          if (firstValue is List && firstValue.isNotEmpty) {
            return firstValue.first.toString();
          }
          if (firstValue is Map && firstValue.isNotEmpty) {
            return firstValue.values.first.toString();
          }
          return firstValue.toString();
        }
      }
    } catch (_) {}
    return "Erreur API ($statusCode).";
  }
}

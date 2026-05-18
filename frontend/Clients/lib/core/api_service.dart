import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'auth_token_manager.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 12);

  Uri _uri(String path) => Uri.parse("${AppConfig.apiBaseUrl}$path");

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{"Content-Type": "application/json"};
    if (token != null && token.isNotEmpty) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }

  String? _safeFilePath(PlatformFile file) {
    if (kIsWeb) {
      return null;
    }
    try {
      final path = file.path;
      if (path == null || path.isEmpty) {
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> _withAutoRefresh(
    Future<http.Response> Function(String? token) send, {
    String? token,
  }) async {
    final firstToken = token ?? AuthTokenManager.instance.accessToken;
    final first = await send(firstToken).timeout(_timeout);
    if (first.statusCode != 401) {
      return first;
    }
    final refreshed = await AuthTokenManager.instance.refreshAccessToken();
    if (refreshed == null || refreshed.isEmpty || refreshed == firstToken) {
      return first;
    }
    return send(refreshed).timeout(_timeout);
  }

  Future<List<Map<String, dynamic>>> getList(String path,
      {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.get(_uri(path), headers: _headers(t)),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "GET $path failed: ${response.statusCode} ${response.body}");
    }
    final decoded = jsonDecode(response.body);
    if (decoded is List) {
      return decoded.whereType<Map<String, dynamic>>().toList();
    }
    if (decoded is Map<String, dynamic>) {
      final results = decoded["results"];
      if (results is List) {
        return results.whereType<Map<String, dynamic>>().toList();
      }
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> getObject(String path, {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.get(_uri(path), headers: _headers(t)),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "GET $path failed: ${response.statusCode} ${response.body}");
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw Exception("GET $path returned unexpected payload.");
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.post(
        _uri(path),
        headers: _headers(t),
        body: jsonEncode(body),
      ),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "POST $path failed: ${response.statusCode} ${response.body}");
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {"ok": true};
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body,
      {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.patch(
        _uri(path),
        headers: _headers(t),
        body: jsonEncode(body),
      ),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "PATCH $path failed: ${response.statusCode} ${response.body}");
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {"ok": true};
  }

  Future<void> delete(String path, {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.delete(
        _uri(path),
        headers: _headers(t),
      ),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "DELETE $path failed: ${response.statusCode} ${response.body}");
    }
  }

  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    String? token,
    PlatformFile? file,
    String fileFieldName = "file",
  }) async {
    String? filePath;
    Uint8List? fileBytes;
    Stream<List<int>>? fileReadStream;
    String fileName = "upload.bin";
    if (file != null) {
      fileName = file.name.isEmpty ? "upload.bin" : file.name;
      filePath = _safeFilePath(file);
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        fileBytes = file.bytes!;
      } else if ((filePath ?? "").isNotEmpty) {
        fileBytes = null;
      } else {
        fileReadStream = file.readStream;
        if (fileReadStream == null) {
          throw Exception(
            "Le fichier selectionne est inaccessible sur cette plateforme.",
          );
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk in fileReadStream) {
          builder.add(chunk);
        }
        fileBytes = builder.takeBytes();
      }
    }

    Future<http.StreamedResponse> sendWithToken(String? t) async {
      final request = http.MultipartRequest("POST", _uri(path));
      request.headers.addAll(_headers(t)..remove("Content-Type"));
      request.fields.addAll(fields);
      if (file != null) {
        if (fileBytes != null && fileBytes.isNotEmpty) {
          request.files.add(
            http.MultipartFile.fromBytes(
              fileFieldName,
              fileBytes,
              filename: fileName,
            ),
          );
        } else if ((filePath ?? "").isNotEmpty) {
          request.files.add(
            await http.MultipartFile.fromPath(
              fileFieldName,
              filePath!,
              filename: fileName,
            ),
          );
        } else {
          throw Exception(
            "Le fichier selectionne est inaccessible sur cette plateforme.",
          );
        }
      }
      return request.send();
    }

    final firstToken = token ?? AuthTokenManager.instance.accessToken;
    var streamed = await sendWithToken(firstToken).timeout(_timeout);
    if (streamed.statusCode == 401) {
      final refreshed = await AuthTokenManager.instance.refreshAccessToken();
      if (refreshed != null &&
          refreshed.isNotEmpty &&
          refreshed != firstToken) {
        streamed = await sendWithToken(refreshed).timeout(_timeout);
      }
    }
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(
          "POST multipart $path failed: ${streamed.statusCode} $body");
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return {"ok": true};
  }

  Future<String> downloadText(String path, {String? token}) async {
    final response = await _withAutoRefresh(
      (t) => _client.get(_uri(path), headers: _headers(t)),
      token: token,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          "GET $path failed: ${response.statusCode} ${response.body}");
    }
    return response.body;
  }

  String toUserMessage(
    Object error, {
    String fallback = "Une erreur est survenue. Reessayez.",
  }) {
    if (error is TimeoutException) {
      return "La requête a expiré. Vérifiez votre connexion et réessayez.";
    }
    final raw = error.toString().replaceFirst("Exception: ", "").trim();
    if (raw.isEmpty) {
      return fallback;
    }

    final lower = raw.toLowerCase();
    if (lower.contains("connection refused") ||
        lower.contains("failed host lookup") ||
        lower.contains("socketexception")) {
      return "Serveur inaccessible. Verifiez votre connexion puis reessayez.";
    }

    final candidate =
        raw.contains(" failed: ") ? raw.split(" failed: ").last.trim() : raw;
    try {
      final decoded = jsonDecode(candidate);
      final extracted = _extractDecodedError(decoded);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    } catch (_) {}
    return candidate.isEmpty ? fallback : candidate;
  }

  String _extractDecodedError(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final detail = decoded["detail"]?.toString().trim() ?? "";
      if (detail.isNotEmpty) {
        return detail;
      }
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List && value.isNotEmpty) {
          final first = value.first.toString().trim();
          if (first.isNotEmpty) {
            return first;
          }
        } else if (value is Map && value.isNotEmpty) {
          final nested = _extractDecodedError(value);
          if (nested.isNotEmpty) {
            return nested;
          }
        } else if (value != null) {
          final text = value.toString().trim();
          if (text.isNotEmpty) {
            return text;
          }
        }
      }
    } else if (decoded is List && decoded.isNotEmpty) {
      final first = decoded.first.toString().trim();
      if (first.isNotEmpty) {
        return first;
      }
    }
    return "";
  }
}

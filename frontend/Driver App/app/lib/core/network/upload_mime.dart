import 'package:dio/dio.dart' show DioMediaType;

/// Derives a safe (filename, MIME) pair for a Driver multipart upload.
///
/// The backend rejects a missing / `application/octet-stream` Content-Type
/// (upload hardening UP-001) and an unknown extension. Dio's `MultipartFile`
/// defaults to octet-stream when no `contentType` is passed, so every upload
/// that skipped this 400'd server-side. We declare a concrete MIME and ensure
/// the filename carries a matching extension.
({String filename, DioMediaType mime}) normalizeUpload(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return (filename: name, mime: DioMediaType('image', 'png'));
  if (n.endsWith('.webp')) return (filename: name, mime: DioMediaType('image', 'webp'));
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) {
    return (filename: name, mime: DioMediaType('image', 'jpeg'));
  }
  if (n.endsWith('.pdf')) return (filename: name, mime: DioMediaType('application', 'pdf'));
  // No recognized extension (e.g. a raw camera capture) — assume JPEG.
  return (filename: '$name.jpg', mime: DioMediaType('image', 'jpeg'));
}

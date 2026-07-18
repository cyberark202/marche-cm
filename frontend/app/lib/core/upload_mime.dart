import 'package:dio/dio.dart';

/// Derives a safe (filename, MIME) pair for a multipart upload.
///
/// The backend rejects a missing/octet-stream Content-Type (upload hardening
/// UP-001) and unknown extensions, so every upload must declare a concrete
/// type and carry a recognized extension. Dio's `MultipartFile` otherwise
/// defaults to `application/octet-stream`, which the server refuses.
({String filename, DioMediaType type}) normalizeUpload(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) {
    return (filename: name, type: DioMediaType('image', 'png'));
  }
  if (n.endsWith('.webp')) {
    return (filename: name, type: DioMediaType('image', 'webp'));
  }
  if (n.endsWith('.gif')) {
    return (filename: name, type: DioMediaType('image', 'gif'));
  }
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) {
    return (filename: name, type: DioMediaType('image', 'jpeg'));
  }
  if (n.endsWith('.pdf')) {
    return (filename: name, type: DioMediaType('application', 'pdf'));
  }
  // Video formats accepted by the backend (publish-video). The MIME subtypes
  // must match the server whitelist exactly: video/mp4, video/quicktime,
  // video/webm, video/x-m4v. Without these, a .mp4 fell through to the JPEG
  // fallback below — renamed to ".mp4.jpg" with an image/jpeg type — which the
  // server rejected as an invalid video extension (400).
  if (n.endsWith('.mp4')) {
    return (filename: name, type: DioMediaType('video', 'mp4'));
  }
  if (n.endsWith('.mov')) {
    return (filename: name, type: DioMediaType('video', 'quicktime'));
  }
  if (n.endsWith('.webm')) {
    return (filename: name, type: DioMediaType('video', 'webm'));
  }
  if (n.endsWith('.m4v')) {
    return (filename: name, type: DioMediaType('video', 'x-m4v'));
  }
  // Voice notes (chat) — must match the server audio whitelist.
  if (n.endsWith('.m4a')) {
    return (filename: name, type: DioMediaType('audio', 'mp4'));
  }
  if (n.endsWith('.aac')) {
    return (filename: name, type: DioMediaType('audio', 'aac'));
  }
  if (n.endsWith('.mp3')) {
    return (filename: name, type: DioMediaType('audio', 'mpeg'));
  }
  if (n.endsWith('.ogg') || n.endsWith('.opus')) {
    return (filename: name, type: DioMediaType('audio', 'ogg'));
  }
  if (n.endsWith('.wav')) {
    return (filename: name, type: DioMediaType('audio', 'wav'));
  }
  // No recognized extension (e.g. a raw camera capture) — assume JPEG.
  return (filename: '$name.jpg', type: DioMediaType('image', 'jpeg'));
}

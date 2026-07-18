import 'package:dio/dio.dart' show DioMediaType;

({String filename, DioMediaType mime}) normalizeUpload(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return (filename: name, mime: DioMediaType('image', 'png'));
  if (n.endsWith('.webp')) return (filename: name, mime: DioMediaType('image', 'webp'));
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) {
    return (filename: name, mime: DioMediaType('image', 'jpeg'));
  }
  if (n.endsWith('.pdf')) return (filename: name, mime: DioMediaType('application', 'pdf'));
  return (filename: '$name.jpg', mime: DioMediaType('image', 'jpeg'));
}

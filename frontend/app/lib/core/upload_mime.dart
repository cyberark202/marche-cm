import 'package:dio/dio.dart';

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
  return (filename: '$name.jpg', type: DioMediaType('image', 'jpeg'));
}

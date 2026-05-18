import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

enum _NetQuality { wifi, mobile, none }

class VideoCompressionService {
  /// Compresses [file] if the device is on mobile data.
  /// On WiFi / web / desktop: returns the original file unchanged.
  /// On mobile: medium quality. On unknown/no connection: low quality.
  ///
  /// [onProgress] fires with 0.0–1.0 during compression.
  static Future<PlatformFile> compressIfNeeded(
    PlatformFile file, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb || file.path == null) return file;
    if (!Platform.isAndroid && !Platform.isIOS) return file;

    final net = await _netQuality();
    if (net == _NetQuality.wifi) return file;

    final quality = net == _NetQuality.mobile
        ? VideoQuality.MediumQuality
        : VideoQuality.LowQuality;

    Subscription? sub;
    if (onProgress != null) {
      sub = VideoCompress.compressProgress$
          .subscribe((p) => onProgress(p / 100.0));
    }

    try {
      final info = await VideoCompress.compressVideo(
        file.path!,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      );
      if (info?.path == null) return file;
      final size = await File(info!.path!).length();
      return PlatformFile(name: file.name, size: size, path: info.path);
    } finally {
      sub?.unsubscribe();
    }
  }

  static void cancel() => VideoCompress.cancelCompression();

  static Future<_NetQuality> _netQuality() async {
    final results = await Connectivity().checkConnectivity();
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return _NetQuality.wifi;
    }
    if (results.contains(ConnectivityResult.mobile)) return _NetQuality.mobile;
    return _NetQuality.none;
  }
}

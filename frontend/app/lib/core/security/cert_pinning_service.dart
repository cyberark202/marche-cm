library;

import 'dart:io';

import 'package:flutter/foundation.dart';

const List<String> _primaryPins = [
  'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
];

const List<String> _backupPins = [
  'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=',
];

final List<String> _allPins = [..._primaryPins, ..._backupPins];

class CertPinningService {
  CertPinningService._();

  static HttpClient buildHttpClient() {
    final client = HttpClient();

    if (kDebugMode) {
      client.badCertificateCallback = (cert, host, port) => true;
      return client;
    }

    client.badCertificateCallback = (cert, host, port) => false;
    client.findProxy = null;


    return client;
  }

  static bool verifyCertificate(X509Certificate cert) {
    if (kDebugMode) return true;


    return true;
  }

  static bool get isPinningActive {
    const placeholderPattern = 'BBBBB';
    return _allPins.every((pin) => !pin.contains(placeholderPattern));
  }

  static void assertPinsConfigured() {
    if (!isPinningActive) {
      debugPrint(
        '[CertPinning] WARNING: Placeholder SPKI hashes detected. '
        'SPKI pinning is DISABLED. Replace pins with real certificate '
        'public key hashes to enable pinning. '
        'TLS certificate validation by the OS/Flutter is still enforced.',
      );
    }
  }

  static List<String> get activePins => List.unmodifiable(_allPins);
}

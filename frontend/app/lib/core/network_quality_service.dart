import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkQuality { offline, weak, online }

/// Monitors connectivity and classifies network quality.
///
/// Uses connectivity_plus (already in pubspec). Weak is defined as mobile
/// data without WiFi — relevant for low-end Android on 3G in Cameroon.
/// Callers subscribe to [qualityStream] or read [current] synchronously.
class NetworkQualityService {
  NetworkQualityService._();
  static final NetworkQualityService instance = NetworkQualityService._();

  final _controller = StreamController<NetworkQuality>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  NetworkQuality _current = NetworkQuality.online;

  NetworkQuality get current => _current;
  Stream<NetworkQuality> get qualityStream => _controller.stream;

  bool get isOffline => _current == NetworkQuality.offline;
  bool get isWeak => _current == NetworkQuality.weak;
  bool get isOnline => _current == NetworkQuality.online;

  void init() {
    _sub ??= Connectivity().onConnectivityChanged.listen(_onChanged);
    // Probe initial state without await — stream will correct shortly.
    Connectivity().checkConnectivity().then(_onChanged);
  }

  void _onChanged(List<ConnectivityResult> results) {
    final q = _classify(results);
    if (q != _current) {
      _current = q;
      _controller.add(q);
    }
  }

  NetworkQuality _classify(List<ConnectivityResult> results) {
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      return NetworkQuality.offline;
    }
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return NetworkQuality.online;
    }
    // Mobile / bluetooth / other — flag as weak
    return NetworkQuality.weak;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _controller.close();
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_config.dart';
import 'token_repository.dart';
import 'websocket_service.dart';

class RealtimeEventsService with WidgetsBindingObserver {
  RealtimeEventsService._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final RealtimeEventsService instance = RealtimeEventsService._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocketService? _ws;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _connected = false;
  String? _targetToken;
  bool _paused = false;
  List<String> _connectedTopics = const [];

  Timer? _reconnectTimer;
  Timer? _stabilityTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 8;

  static const List<String> _defaultTopics = [
    "products",
    "orders",
    "chat",
    "logistics",
    "analytics",
    "profiles",
    "wallets",
    "compliance",
    "notifications",
    "support",
  ];

  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool get isConnected => _connected;

  void connect({
    required String accessToken,
    List<String> topics = _defaultTopics,
  }) {
    final token = accessToken.trim();
    if (token.isEmpty) {
      disconnect();
      return;
    }
    if (_targetToken == token &&
        (_connected || _ws != null || _reconnectTimer?.isActive == true)) {
      return;
    }
    _targetToken = token;
    _paused = false;
    _connectedTopics = topics;
    _reconnectAttempts = 0;
    _doConnect(token: token, topics: topics);
  }

  Future<void> connectFromStorage({List<String> topics = _defaultTopics}) async {
    final token = await TokenRepository.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      disconnect();
      return;
    }
    connect(accessToken: token, topics: topics);
  }

  void _doConnect({
    required String token,
    required List<String> topics,
    bool resync = false,
  }) {
    _cancelSubscription();
    _reconnectTimer?.cancel();

    final base = AppConfig.apiBaseUrl
        .replaceFirst("http://", "ws://")
        .replaceFirst("https://", "wss://");
    final topicQuery = Uri.encodeQueryComponent(topics.join(","));

    final url = "$base/ws/events/?topics=$topicQuery";
    _ws = WebSocketService(url, token: token);

    _subscription = _ws!.connect().listen(
      (event) {
        _controller.add(event);
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
    );
    _connected = true;
    _targetToken = token;

    _stabilityTimer?.cancel();
    _stabilityTimer =
        Timer(const Duration(seconds: 20), () => _reconnectAttempts = 0);

    if (resync) {
      for (final topic in topics) {
        _controller.add({"topic": topic, "type": "resync", "payload": const {}});
      }
    }
  }

  void _scheduleReconnect() {
    _stabilityTimer?.cancel();
    if (_reconnectTimer?.isActive == true) return;
    _connected = false;
    _cancelSubscription();

    if (_paused) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    final delaySeconds = (1 << _reconnectAttempts).clamp(2, 32);
    _reconnectAttempts++;

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      final freshToken = await TokenRepository.getAccessToken();
      if (freshToken == null || freshToken.isEmpty) return;
      _doConnect(token: freshToken, topics: _connectedTopics, resync: true);
    });
  }

  void _cancelSubscription() {
    _subscription?.cancel();
    _subscription = null;
    _ws?.dispose();
    _ws = null;
  }

  bool matchesTopic(Map<String, dynamic> event, String topic) {
    return (event["topic"] ?? "").toString() == topic;
  }

  void send(Map<String, dynamic> payload) {
    if (!_connected) return;
    try {
      _ws?.send(payload);
    } catch (_) {
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_paused) return;
      _paused = true;
      _reconnectTimer?.cancel();
      _stabilityTimer?.cancel();
      _cancelSubscription();
      _connected = false;
    } else if (state == AppLifecycleState.resumed) {
      if (!_paused) return;
      _paused = false;
      final token = _targetToken;
      if (token != null && token.isNotEmpty && !_connected) {
        _reconnectAttempts = 0;
        _doConnect(token: token, topics: _connectedTopics, resync: true);
      }
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stabilityTimer?.cancel();
    _stabilityTimer = null;
    _reconnectAttempts = 0;
    _cancelSubscription();
    _connected = false;
    _targetToken = null;
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disconnect();
  }
}

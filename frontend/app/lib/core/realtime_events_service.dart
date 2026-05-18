import 'dart:async';

import 'app_config.dart';
import 'token_repository.dart';
import 'websocket_service.dart';

class RealtimeEventsService {
  RealtimeEventsService._();
  static final RealtimeEventsService instance = RealtimeEventsService._();

  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();
  WebSocketService? _ws;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  bool _connected = false;
  String? _connectedToken;
  List<String> _connectedTopics = const [];

  // Reconnect state
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 8;

  Stream<Map<String, dynamic>> get events => _controller.stream;
  bool get isConnected => _connected;

  void connect({
    required String accessToken,
    List<String> topics = const [
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
    ],
  }) {
    final token = accessToken.trim();
    if (token.isEmpty) {
      disconnect();
      return;
    }
    if (_connected && _connectedToken == token) {
      return;
    }
    _connectedTopics = topics;
    _reconnectAttempts = 0;
    _doConnect(token: token, topics: topics);
  }

  void _doConnect({required String token, required List<String> topics}) {
    _cancelSubscription();
    _reconnectTimer?.cancel();

    final base = AppConfig.apiBaseUrl
        .replaceFirst("http://", "ws://")
        .replaceFirst("https://", "wss://");
    final topicQuery = Uri.encodeQueryComponent(topics.join(","));

    // Token sent via Sec-WebSocket-Protocol subprotocol — never in query string.
    // Backend (config/websocket_auth.py) expects: ['bearer', '<token>'].
    final url = "$base/ws/events/?topics=$topicQuery";
    _ws = WebSocketService(url, token: token);

    _subscription = _ws!.connect().listen(
      (event) {
        _reconnectAttempts = 0; // reset backoff on successful message
        _controller.add(event);
      },
      onError: (_) => _scheduleReconnect(),
      onDone: () => _scheduleReconnect(),
    );
    _connected = true;
    _connectedToken = token;
  }

  void _scheduleReconnect() {
    _connected = false;
    _connectedToken = null;
    _cancelSubscription();

    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    // Exponential backoff: 1s, 2s, 4s, 8s … capped at 32s.
    final delaySeconds = (1 << _reconnectAttempts).clamp(1, 32);
    _reconnectAttempts++;

    // Always fetch the latest token from storage — it may have been refreshed
    // by the REST client while the WebSocket was disconnected (e.g. 4401 expiry).
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      final freshToken = await TokenRepository.getAccessToken();
      if (freshToken == null || freshToken.isEmpty) return;
      _doConnect(token: freshToken, topics: _connectedTopics);
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

  void disconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _cancelSubscription();
    _connected = false;
    _connectedToken = null;
  }

  void dispose() {
    disconnect();
  }
}

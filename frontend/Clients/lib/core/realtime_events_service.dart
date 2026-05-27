import 'dart:async';

import 'app_config.dart';
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

  Stream<Map<String, dynamic>> get events => _controller.stream;

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
    disconnect();
    final base = AppConfig.apiBaseUrl
        .replaceFirst("http://", "ws://")
        .replaceFirst("https://", "wss://");
    final topicQuery = Uri.encodeQueryComponent(topics.join(","));
    // Audit ref: [WS-002] the bearer token is sent via Sec-WebSocket-Protocol
    // ("bearer, <jwt>"), NEVER in the query string — query-string tokens are
    // captured by reverse-proxy access logs, APM products, browser history.
    // Backend production builds REFUSE ?token= now.
    final url = "$base/ws/events/?topics=$topicQuery";
    _ws = WebSocketService(url, protocols: ["bearer", token]);
    _subscription = _ws!.connect().listen(
      (event) {
        _controller.add(event);
      },
      onError: (_) {
        _connected = false;
        _connectedToken = null;
      },
      onDone: () {
        _connected = false;
        _connectedToken = null;
      },
    );
    _connected = true;
    _connectedToken = token;
  }

  bool matchesTopic(Map<String, dynamic> event, String topic) {
    return (event["topic"] ?? "").toString() == topic;
  }

  void disconnect() {
    _subscription?.cancel();
    _subscription = null;
    _ws?.dispose();
    _ws = null;
    _connected = false;
    _connectedToken = null;
  }

  void dispose() {
    disconnect();
  }
}

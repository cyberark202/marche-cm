import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketService(this.url, {this.token});

  final String url;
  final String? token;
  WebSocketChannel? _channel;
  Timer? _pingTimer;

  Stream<Map<String, dynamic>> connect() {
    // Prefer Sec-WebSocket-Protocol subprotocol — token never appears in proxy logs.
    // Backend (config/websocket_auth.py) reads subprotocols[0]=="bearer", subprotocols[1]==<token>.
    final protocols = (token != null && token!.isNotEmpty)
        ? <String>['bearer', token!]
        : <String>[];

    _channel = WebSocketChannel.connect(
      Uri.parse(url),
      protocols: protocols.isEmpty ? null : protocols,
    );

    // Keep-alive ping every 25 s — prevents load-balancer/NAT idle timeouts.
    // The backend ignores unknown message types gracefully.
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add('{"type":"ping"}');
      } catch (_) {}
    });

    return _channel!.stream.map((event) => jsonDecode(event) as Map<String, dynamic>);
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _channel?.sink.close();
    _channel = null;
  }
}

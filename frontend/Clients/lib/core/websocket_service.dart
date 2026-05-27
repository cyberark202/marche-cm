import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  /// Audit ref: [WS-002] tokens must NEVER ride in the query string.
  /// The optional [protocols] list is forwarded as Sec-WebSocket-Protocol
  /// — for the bearer convention pass `['bearer', '<jwt>']`.
  WebSocketService(this.url, {this.protocols});

  final String url;
  final Iterable<String>? protocols;
  WebSocketChannel? _channel;

  Stream<Map<String, dynamic>> connect() {
    _channel = WebSocketChannel.connect(
      Uri.parse(url),
      protocols: protocols,
    );
    return _channel!.stream
        .map((event) => jsonDecode(event) as Map<String, dynamic>);
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _channel?.sink.close();
  }
}


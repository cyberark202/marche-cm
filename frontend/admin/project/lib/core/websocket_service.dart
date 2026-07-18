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
    final protocols = (token != null && token!.isNotEmpty)
        ? <String>['bearer', token!]
        : <String>[];

    _channel = WebSocketChannel.connect(
      Uri.parse(url),
      protocols: protocols.isEmpty ? null : protocols,
    );

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      try {
        _channel?.sink.add('{"type":"ping"}');
      } catch (_) {}
    });

    return _channel!.stream
        .map((event) => jsonDecode(event) as Map<String, dynamic>);
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

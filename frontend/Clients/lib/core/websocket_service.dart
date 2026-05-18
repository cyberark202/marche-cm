import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketService(this.url);

  final String url;
  WebSocketChannel? _channel;

  Stream<Map<String, dynamic>> connect() {
    _channel = WebSocketChannel.connect(Uri.parse(url));
    return _channel!.stream.map((event) => jsonDecode(event) as Map<String, dynamic>);
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void dispose() {
    _channel?.sink.close();
  }
}


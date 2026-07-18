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
  // Dernier token demandé (persiste pendant la mise en arrière-plan pour savoir
  // quoi reconnecter au retour au premier plan). Remis à null par disconnect().
  String? _targetToken;
  bool _paused = false;
  List<String> _connectedTopics = const [];

  // Reconnect state
  Timer? _reconnectTimer;
  Timer? _stabilityTimer;
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
    // Idempotence stricte : appelé à chaque build() du shell. Tant qu'une
    // connexion est établie OU en cours (socket vivant / backoff programmé)
    // pour ce token, ne rien faire — sinon on annule le timer de backoff et on
    // reconnecte immédiatement à chaque rebuild, d'où la boucle de resync
    // « chaque seconde » visible côté vendeur.
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

    // Token sent via Sec-WebSocket-Protocol subprotocol — never in query string.
    // Backend (config/websocket_auth.py) expects: ['bearer', '<token>'].
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

    // Le backoff n'est remis a zero qu'apres une connexion STABLE (et non a
    // chaque message recu) : sans cela, un socket qui flappe (connecte -> 1
    // message -> coupe) reconnecte toujours a 1s, donnant une boucle de
    // reconnexion visible « chaque seconde ». Ici elle reste silencieuse et
    // espacee (backoff exponentiel) tant que la connexion n'a pas tenu 20s.
    _stabilityTimer?.cancel();
    _stabilityTimer =
        Timer(const Duration(seconds: 20), () => _reconnectAttempts = 0);

    // Gap recovery: a best-effort broadcast WS does NOT replay events missed
    // while disconnected. On every *re*connection we emit a synthetic resync
    // event per topic so each subscribed page re-fetches its REST state and
    // closes the gap. The first connection is skipped — pages already load in
    // initState.
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

    // En arrière-plan : on ne relance rien (économie batterie/réseau, pas de
    // rechargement). La reconnexion + resync a lieu au retour au premier plan.
    if (_paused) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) return;

    // Exponential backoff: 2s, 4s, 8s … capped at 32s (jamais 1s).
    final delaySeconds = (1 << _reconnectAttempts).clamp(2, 32);
    _reconnectAttempts++;

    // Always fetch the latest token from storage — it may have been refreshed
    // by the REST client while the WebSocket was disconnected (e.g. 4401 expiry).
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

  /// Envoie un message applicatif sur le socket événements (ex : signal
  /// typing du chat). Silencieux si déconnecté — ces signaux sont éphémères,
  /// jamais rejoués.
  void send(Map<String, dynamic> payload) {
    if (!_connected) return;
    try {
      _ws?.send(payload);
    } catch (_) {
      // Socket en cours de fermeture : le prochain signal partira après resync.
    }
  }

  /// Coupe le flux temps réel quand l'app passe en arrière-plan (aucune
  /// reconnexion tant qu'elle y reste) et le rétablit une fois — avec resync —
  /// au retour au premier plan. Évite la charge réseau et les rechargements
  /// pendant que l'app n'est pas visible.
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

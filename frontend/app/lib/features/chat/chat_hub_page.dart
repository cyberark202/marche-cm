import 'dart:async';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import '../feed/video_post_player.dart';
import 'voice_note.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';

// Filet de sécurité côté client : masque tout lien/e-mail dans le TEXTE affiché
// d'un message. Le backend redige déjà à la source (aucun lien n'est stocké) ;
// ceci couvre l'affichage des messages créés avant cette règle.
final RegExp _kChatEmail =
    RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
final RegExp _kChatScheme =
    RegExp(r'(?:h(?:tt|xx)ps?|ftp)://\S+', caseSensitive: false);
final RegExp _kChatWww = RegExp(r'\bwww\.\S+', caseSensitive: false);
final RegExp _kChatDomain = RegExp(
    r'\b(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+(?:com|net|org|io|co|app|dev|me|ly|gg|to|cc|xyz|info|biz|shop|store|online|site|link|page|pro|tv|fm|cm|fr|ng|gh|sn|ci|ma|tg|bj|cd|ga|cf|ml|tk|us|uk|ca|de|es|it|be|nl|ru|cn|in|tr|br)(?:[:/?#]\S*)?',
    caseSensitive: false);

String maskChatLinks(String input) {
  if (input.isEmpty) return input;
  return input
      .replaceAll(_kChatEmail, '[contact retiré]')
      .replaceAll(_kChatScheme, '[lien retiré]')
      .replaceAll(_kChatWww, '[lien retiré]')
      .replaceAll(_kChatDomain, '[lien retiré]');
}

/// Palette de réactions rapides (long-press sur une bulle, façon WhatsApp).
const List<String> kQuickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"];

class ChatHubPage extends StatefulWidget {
  const ChatHubPage({super.key, this.initialRoomId});

  final int? initialRoomId;

  @override
  State<ChatHubPage> createState() => _ChatHubPageState();
}

class _ChatHubPageState extends State<ChatHubPage> {
  final ApiService _api = ApiService();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  List<Map<String, dynamic>> _rooms = const [];
  // Messages du salon ouvert, ordre ANTÉ-chronologique (index 0 = plus récent),
  // aligné sur l'API et rendu par une ListView reverse (ouverture en bas).
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  String? _error;
  int? _selectedRoomId;
  int _page = 1;
  bool _hasMore = true;
  bool _showScrollDown = false;
  bool _showEmoji = false;
  bool _recording = false;
  final VoiceRecorder _voice = VoiceRecorder();
  Map<String, dynamic>? _replyingTo;
  String _query = "";
  int _selectedFilter = 0; // 0=Tous, 1=Vendeurs, 2=Livreurs, 3=Support

  // Envoi optimiste : ids locaux négatifs, remplacés par la réponse serveur.
  int _localIdSeq = -1;
  // Typing : throttle d'émission + timer d'effacement de l'indicateur reçu.
  DateTime? _typingSentAt;
  bool _peerTyping = false;
  Timer? _typingClearTimer;
  // Surbrillance temporaire après un saut vers le message cité.
  int? _highlightedId;
  Timer? _highlightTimer;

  String? _safePlatformFilePath(PlatformFile file) {
    if (kIsWeb) return null;
    try {
      final path = file.path;
      if (path == null || path.isEmpty) return null;
      return path;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedRoomId = widget.initialRoomId;
    _initialLoad();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "chat")) {
        _onChatEvent(event);
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _typingClearTimer?.cancel();
    _highlightTimer?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _initialLoad() async {
    setState(() => _loading = true);
    await _loadRooms();
    if (_selectedRoomId != null) {
      await _loadMessages(reset: true);
      _markRoomRead(_selectedRoomId!);
    }
    if (mounted) setState(() => _loading = false);
  }

  // ── Temps réel incrémental ────────────────────────────────────────────────
  // Chaque événement met à jour l'état local ; le rechargement complet est
  // réservé au resync (trous après reconnexion).

  void _onChatEvent(Map<String, dynamic> event) {
    final type = (event["type"] ?? "").toString();
    final raw = event["payload"];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    switch (type) {
      case "message_created":
        _onMessageCreated(data);
      case "message_state":
        _onMessageState(data);
      case "room_read":
        _onRoomRead(data);
      case "message_reaction":
        _onMessageReaction(data);
      case "typing":
        _onTyping(data);
      case "room_created":
        _loadRooms();
      default:
        // resync (reconnexion) ou événement inconnu : re-synchronisation REST.
        _loadRooms();
        if (_selectedRoomId != null) _loadMessages(reset: true);
    }
  }

  void _onMessageCreated(Map<String, dynamic> message) {
    final roomId = message["room"];
    final id = message["id"];
    if (roomId == _selectedRoomId) {
      if (id is int && !_messages.any((m) => m["id"] == id)) {
        setState(() => _messages = [message, ..._messages]);
      }
      _markRoomRead(roomId as int);
      if (!_showScrollDown) _scrollToBottomSoon();
    } else if (id is int) {
      // Salon non ouvert : accusé « délivré » (l'app a reçu le message).
      _postBestEffort("/api/chat/messages/$id/mark_delivered/");
    }
    _loadRooms();
  }

  void _onMessageState(Map<String, dynamic> data) {
    final id = data["message_id"];
    final state = (data["state"] ?? "").toString();
    if (id is! int || state.isEmpty) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m["id"] != id) return m;
        final current = (m["my_state"] ?? "").toString();
        if (current == "READ") return m; // jamais de rétrogradation
        return {...m, "my_state": state};
      }).toList();
    });
  }

  void _onRoomRead(Map<String, dynamic> data) {
    if (data["room"] != _selectedRoomId) return;
    final myId = context.read<SessionStore>().userId;
    setState(() {
      _messages = _messages
          .map((m) => m["sender"] == myId ? {...m, "my_state": "READ"} : m)
          .toList();
    });
  }

  void _onMessageReaction(Map<String, dynamic> data) {
    final id = data["message_id"];
    if (id is! int) return;
    final myId = context.read<SessionStore>().userId;
    final reactions = _mapReactions(data["reactions"], myId);
    setState(() {
      _messages = _messages
          .map((m) => m["id"] == id ? {...m, "reactions": reactions} : m)
          .toList();
    });
  }

  /// Convertit le payload serveur [{emoji,count,user_ids}] vers la forme
  /// sérialisée des messages [{emoji,count,mine}].
  List<Map<String, dynamic>> _mapReactions(dynamic raw, int? myId) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) {
      final userIds = (entry["user_ids"] is List)
          ? List.from(entry["user_ids"] as List)
          : const [];
      return <String, dynamic>{
        "emoji": (entry["emoji"] ?? "").toString(),
        "count": entry["count"] ?? 0,
        "mine": entry.containsKey("mine")
            ? entry["mine"] == true
            : (myId != null && userIds.contains(myId)),
      };
    }).toList();
  }

  void _onTyping(Map<String, dynamic> data) {
    final myId = context.read<SessionStore>().userId;
    if (data["room"] != _selectedRoomId || data["user_id"] == myId) return;
    _typingClearTimer?.cancel();
    setState(() => _peerTyping = data["is_typing"] == true);
    if (_peerTyping) {
      // Effacement auto : signal éphémère, jamais de « écrit… » fantôme.
      _typingClearTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _peerTyping = false);
      });
    }
  }

  /// Émission du signal typing, throttlée (max ~1 toutes les 2,5 s).
  void _sendTyping() {
    final roomId = _selectedRoomId;
    if (roomId == null) return;
    final now = DateTime.now();
    if (_typingSentAt != null &&
        now.difference(_typingSentAt!) < const Duration(milliseconds: 2500)) {
      return;
    }
    _typingSentAt = now;
    RealtimeEventsService.instance
        .send({"type": "typing", "room": roomId, "is_typing": true});
  }

  // ── Chargements REST ──────────────────────────────────────────────────────

  Future<void> _loadRooms() async {
    final token = context.read<SessionStore>().token;
    try {
      final rooms = await _api.getList("/api/chat/rooms/", token: token);
      if (!mounted) return;
      setState(() => _rooms = rooms);
      _error = null;
    } catch (e) {
      if (!mounted) return;
      if (_rooms.isEmpty) {
        setState(() {
          _error = _api.toUserMessage(
            e,
            fallback: "Impossible de charger les discussions.",
          );
        });
      }
    }
  }

  Future<void> _loadMessages({required bool reset}) async {
    if (_selectedRoomId == null) return;
    final token = context.read<SessionStore>().token;
    final nextPage = reset ? 1 : _page + 1;
    final path =
        "/api/chat/messages/?room=$_selectedRoomId&page=$nextPage${_query.trim().isNotEmpty ? "&q=${Uri.encodeQueryComponent(_query.trim())}" : ""}";
    try {
      final rows = await _api.getList(path, token: token);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _hasMore = rows.length >= 20;
        // API anté-chronologique : page 1 = plus récents, pages suivantes =
        // historique, ajouté en FIN de liste (haut du fil en rendu inversé).
        _messages = reset ? rows : [..._messages, ...rows];
      });
      _error = null;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(
          e,
          fallback: "Impossible de charger les messages.",
        );
      });
    }
  }

  Future<void> _openRoom(int roomId) async {
    setState(() {
      _selectedRoomId = roomId;
      _messages = const [];
      _peerTyping = false;
      _replyingTo = null;
      _query = "";
      _searchController.clear();
    });
    await _loadMessages(reset: true);
    _markRoomRead(roomId);
  }

  /// Marque TOUT le salon lu (un POST) et remet le badge local à zéro.
  void _markRoomRead(int roomId) {
    final token = context.read<SessionStore>().token;
    setState(() {
      _rooms = _rooms
          .map((r) => r["id"] == roomId ? {...r, "unread_count": 0} : r)
          .toList();
    });
    // Best-effort : un échec réseau sera rattrapé au prochain resync.
    _api.post("/api/chat/rooms/$roomId/mark_read/", {}, token: token).catchError((_) => <String, dynamic>{});
  }

  void _postBestEffort(String path) {
    final token = context.read<SessionStore>().token;
    _api.post(path, {}, token: token).catchError((_) => <String, dynamic>{});
  }

  // ── Envois ────────────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (_selectedRoomId == null) return;
    final ok = await _voice.start();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Micro indisponible ou permission refusée.")));
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _cancelRecording() async {
    await _voice.cancel();
    if (mounted) setState(() => _recording = false);
  }

  Future<void> _stopAndSendVoice() async {
    final token = context.read<SessionStore>().token;
    final path = await _voice.stop();
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final filename = "voice_${DateTime.now().millisecondsSinceEpoch}.m4a";
    try {
      final file = PlatformFile(
          name: filename, size: File(path).lengthSync(), path: path);
      final created = await _api.postMultipart(
        "/api/chat/messages/",
        fields: {"room": _selectedRoomId.toString(), "type": "AUDIO"},
        file: file,
        token: token,
      );
      if (!mounted) return;
      setState(() => _messages = [created, ..._messages]);
      _scrollToBottomSoon();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_api.toUserMessage(e))));
    }
  }

  /// Envoi optimiste : la bulle apparaît immédiatement (horloge), puis est
  /// remplacée par la version serveur ; en échec, état « renvoyer » au tap.
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedRoomId == null) return;
    final myId = context.read<SessionStore>().userId;
    final replyingTo = _replyingTo;
    final local = <String, dynamic>{
      "id": _localIdSeq--,
      "room": _selectedRoomId,
      "sender": myId,
      "type": "TEXT",
      "content": text,
      "created_at": DateTime.now().toIso8601String(),
      "pending": true,
      "failed": false,
      "reactions": const [],
      if (replyingTo != null) "reply_to": replyingTo["id"],
      if (replyingTo != null)
        "reply_preview": {
          "id": replyingTo["id"],
          "type": replyingTo["type"],
          "snippet": _previewOf(replyingTo),
        },
    };
    _messageController.clear();
    setState(() {
      _messages = [local, ..._messages];
      _replyingTo = null;
    });
    _scrollToBottomSoon();
    await _postPending(local);
  }

  Future<void> _postPending(Map<String, dynamic> local) async {
    final token = context.read<SessionStore>().token;
    try {
      final created = await _api.post("/api/chat/messages/", {
        "room": local["room"],
        "content": local["content"],
        "type": "TEXT",
        if (local["reply_to"] != null) "reply_to": local["reply_to"],
      }, token: token);
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m["id"] == local["id"] ? created : m)
            .toList();
      });
      _loadRooms();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m["id"] == local["id"]
                ? {...m, "pending": false, "failed": true}
                : m)
            .toList();
      });
    }
  }

  Future<void> _retryFailed(Map<String, dynamic> message) async {
    setState(() {
      _messages = _messages
          .map((m) => m["id"] == message["id"]
              ? {...m, "pending": true, "failed": false}
              : m)
          .toList();
    });
    await _postPending(message);
  }

  Future<void> _sendAttachment() async {
    if (_selectedRoomId == null) return;
    final token = context.read<SessionStore>().token;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (!mounted) return;
    if (picked == null || picked.files.isEmpty) return;
    final selected = picked.files.single;
    final hasPath = _safePlatformFilePath(selected) != null;
    final hasBytes = selected.bytes != null && selected.bytes!.isNotEmpty;
    if (!hasPath && !hasBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Fichier non accessible sur cette plateforme.")),
      );
      return;
    }
    try {
      final replyId = _replyingTo?["id"];
      final created = await _api.postMultipart(
        "/api/chat/messages/",
        fields: {
          "room": _selectedRoomId.toString(),
          "content": _messageController.text.trim(),
          // Typage précis pour que la bulle rende le média (image inline,
          // vidéo lisible in-app) au lieu d'un lien générique.
          "type": _attachmentType(selected.name),
          if (replyId != null) "reply_to": replyId.toString(),
        },
        file: selected,
        token: token,
      );
      _messageController.clear();
      if (!mounted) return;
      setState(() {
        _replyingTo = null;
        _messages = [created, ..._messages];
      });
      _scrollToBottomSoon();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e))),
      );
    }
  }

  // ── Réactions ─────────────────────────────────────────────────────────────

  Future<void> _react(Map<String, dynamic> message, String emoji) async {
    final id = message["id"];
    if (id is! int || id <= 0) return;
    final token = context.read<SessionStore>().token;
    final myId = context.read<SessionStore>().userId;
    try {
      final result = await _api.post(
          "/api/chat/messages/$id/react/", {"emoji": emoji},
          token: token);
      if (!mounted) return;
      final reactions = _mapReactions(result["reactions"], myId);
      setState(() {
        _messages = _messages
            .map((m) => m["id"] == id ? {...m, "reactions": reactions} : m)
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_api.toUserMessage(e))));
    }
  }

  /// Menu contextuel de bulle (long-press) : réactions rapides + actions.
  void _showMessageActions(Map<String, dynamic> message) {
    final mineReaction = (message["reactions"] is List)
        ? (message["reactions"] as List)
            .whereType<Map>()
            .where((r) => r["mine"] == true)
            .map((r) => (r["emoji"] ?? "").toString())
            .firstOrNull
        : null;
    final content = (message["content"] ?? "").toString();
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: kQuickReactions
                    .map(
                      (emoji) => InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _react(message, emoji);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: mineReaction == emoji
                              ? const BoxDecoration(
                                  color: AppPalette.primarySoft,
                                  shape: BoxShape.circle,
                                )
                              : null,
                          child:
                              Text(emoji, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            ListTile(
              leading: const Icon(LucideIcons.reply),
              title: const Text("Répondre"),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyingTo = message);
              },
            ),
            if (content.isNotEmpty)
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text("Copier"),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: maskChatLinks(content)));
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // ── Scroll / navigation dans le fil ──────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final p = _scrollController.position;
    // ListView reverse : offset 0 = bas du fil (messages récents).
    final farFromBottom = p.pixels > 400;
    if (farFromBottom != _showScrollDown) {
      setState(() => _showScrollDown = farFromBottom);
    }
    // Près du HAUT (fin de l'offset) : charger l'historique plus ancien.
    if (_hasMore && !_loading && p.pixels >= p.maxScrollExtent - 180) {
      _loadMessages(reset: false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _animateToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  /// Saute (approximativement) vers le message cité et le surligne ~1 s.
  void _jumpToMessage(int messageId) {
    final index = _messages.indexWhere((m) => m["id"] == messageId);
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Message plus ancien — remontez le fil.")));
      return;
    }
    if (_scrollController.hasClients && _messages.length > 1) {
      final target = (index / (_messages.length - 1)) *
          _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
    _highlightTimer?.cancel();
    setState(() => _highlightedId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _highlightedId = null);
    });
  }

  // ── Helpers d'affichage ───────────────────────────────────────────────────

  bool _isMine(Map<String, dynamic> msg) {
    final myId = context.read<SessionStore>().userId;
    final sender = msg["sender"];
    return myId != null && sender is int && sender == myId;
  }

  Map<String, dynamic>? get _selectedRoom {
    for (final room in _rooms) {
      if (room["id"] == _selectedRoomId) return room;
    }
    return null;
  }

  Map<String, dynamic>? _peerOf(Map<String, dynamic>? room) {
    final peer = room?["peer"];
    return peer is Map ? Map<String, dynamic>.from(peer) : null;
  }

  String _roomLabel(Map<String, dynamic> room) {
    final peer = _peerOf(room);
    final peerName = (peer?["username"] ?? "").toString();
    final name = (room["name"] ?? "").toString().trim();
    if (name.isNotEmpty) return name;
    if (peerName.isNotEmpty) return peerName;
    return "Discussion ${room["id"]}";
  }

  String _roomInitials(Map<String, dynamic> room) {
    final label = _roomLabel(room);
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return "${parts[0][0]}${parts[1][0]}".toUpperCase();
    }
    return label.isNotEmpty ? label[0].toUpperCase() : "?";
  }

  String _myState(Map<String, dynamic> msg) {
    return (msg["my_state"] ?? "").toString();
  }

  DateTime? _createdAt(Map<String, dynamic> msg) {
    return DateTime.tryParse((msg["created_at"] ?? "").toString())?.toLocal();
  }

  String _previewOf(Map<String, dynamic> msg) {
    final content = (msg["content"] ?? "").toString().trim();
    if (content.isNotEmpty) return maskChatLinks(content);
    return const {
          "IMAGE": "📷 Photo",
          "VIDEO": "🎥 Vidéo",
          "AUDIO": "🎤 Note vocale",
          "DOCUMENT": "📎 Document",
        }[(msg["type"] ?? "").toString().toUpperCase()] ??
        "Pièce jointe";
  }

  /// Libellé de séparateur de jour (Aujourd'hui / Hier / JJ-MM-AAAA).
  String _dayLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return "Hier";
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    return "$dd/$mm/${date.year}";
  }

  String _timeLabel(DateTime date) {
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return "$hh:$mm";
  }

  /// Horodatage compact pour la liste de conversations.
  String _inboxTimeLabel(String rawIso) {
    final date = DateTime.tryParse(rawIso)?.toLocal();
    if (date == null) return "";
    final now = DateTime.now();
    final sameDay = date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    if (sameDay) return _timeLabel(date);
    final label = _dayLabel(date);
    return label == "Hier" ? "Hier" : label;
  }

  /// Ligne de présence sous le nom (header de conversation).
  String _presenceLabel(Map<String, dynamic>? peer) {
    if (_peerTyping) return "écrit…";
    if (peer == null) return "";
    if (peer["is_online"] == true) return "en ligne";
    final lastSeen =
        DateTime.tryParse((peer["last_seen_at"] ?? "").toString())?.toLocal();
    if (lastSeen == null) return "";
    final day = _dayLabel(lastSeen);
    if (day == "Aujourd'hui") return "vu à ${_timeLabel(lastSeen)}";
    if (day == "Hier") return "vu hier à ${_timeLabel(lastSeen)}";
    return "vu le $day";
  }

  /// `true` si un séparateur de jour doit précéder (visuellement) le message
  /// d'index [index] — liste anté-chronologique rendue en reverse : le message
  /// ouvre sa journée quand le message PLUS ANCIEN (index+1) est d'un autre jour.
  bool _needsDayDivider(int index) {
    final current = _createdAt(_messages[index]);
    if (current == null) return false;
    if (index == _messages.length - 1) return !_hasMore;
    final older = _createdAt(_messages[index + 1]);
    if (older == null) return true;
    return current.year != older.year ||
        current.month != older.month ||
        current.day != older.day;
  }

  /// Ticks WhatsApp : ✓ envoyé, ✓✓ livré (gris), ✓✓ lu (bleu).
  Widget _statusTicks(Map<String, dynamic> msg) {
    if (msg["pending"] == true) {
      return const Icon(LucideIcons.clock, size: 13, color: Colors.black38);
    }
    if (msg["failed"] == true) {
      return const Icon(LucideIcons.alertCircle,
          size: 14, color: Colors.redAccent);
    }
    final state = _myState(msg);
    final read = state == "READ";
    final delivered = state == "DELIVERED" || read;
    return Icon(
      delivered ? LucideIcons.checkCheck : LucideIcons.check,
      size: 14,
      color: read ? const Color(0xFF34B7F1) : Colors.black38,
    );
  }

  void _openImageViewer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ImageViewerPage(imageUrl: url)),
    );
  }

  void _openVideoViewer(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _ChatVideoPage(videoUrl: url)),
    );
  }

  /// Encart du message cité, rendu en tête de bulle. Tap → saut vers l'original.
  Widget _replyQuote(Map<String, dynamic> msg) {
    final preview = msg["reply_preview"];
    if (preview is! Map) return const SizedBox.shrink();
    final snippet = maskChatLinks((preview["snippet"] ?? "").toString());
    if (snippet.isEmpty) return const SizedBox.shrink();
    final parentId = preview["id"];
    return GestureDetector(
      onTap: parentId is int ? () => _jumpToMessage(parentId) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: const BoxDecoration(
          color: Color(0x0F000000),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border: Border(left: BorderSide(color: AppPalette.primary, width: 3)),
        ),
        child: Text(
          snippet,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
    );
  }

  /// Pastilles de réactions agrégées sous la bulle (tap = toggle si à moi).
  Widget _reactionPills(Map<String, dynamic> msg) {
    final raw = msg["reactions"];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        children: raw.whereType<Map>().map((reaction) {
          final emoji = (reaction["emoji"] ?? "").toString();
          final count = reaction["count"] ?? 0;
          final mine = reaction["mine"] == true;
          return GestureDetector(
            onTap: () => _react(msg, emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: mine ? AppPalette.primarySoft : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: mine ? AppPalette.primary : const Color(0xFFE2E8F0)),
              ),
              child: Text(
                count is int && count > 1 ? "$emoji $count" : emoji,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _roomAvatarColor(int index) {
    const colors = [
      AppPalette.primary,
      Color(0xFF0EA5E9),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      AppPalette.secondary,
    ];
    return colors[index % colors.length];
  }

  bool _isImageName(String name) {
    final n = name.toLowerCase().split('?').first;
    return n.endsWith('.png') ||
        n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.webp') ||
        n.endsWith('.gif');
  }

  bool _isVideoName(String name) {
    final n = name.toLowerCase().split('?').first;
    return n.endsWith('.mp4') ||
        n.endsWith('.mov') ||
        n.endsWith('.webm') ||
        n.endsWith('.m4v');
  }

  String _attachmentType(String name) {
    if (_isImageName(name)) return "IMAGE";
    if (_isVideoName(name)) return "VIDEO";
    return "DOCUMENT";
  }

  bool _isImageMessage(String type, String fileUrl) =>
      type.toUpperCase() == "IMAGE" || _isImageName(fileUrl);

  bool _isAudioName(String name) {
    final n = name.toLowerCase().split('?').first;
    return n.endsWith('.m4a') ||
        n.endsWith('.aac') ||
        n.endsWith('.mp3') ||
        n.endsWith('.ogg') ||
        n.endsWith('.opus') ||
        n.endsWith('.wav');
  }

  String _absoluteUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith("http://") || url.startsWith("https://")) return url;
    final base = AppConfig.apiBaseUrl;
    return url.startsWith("/") ? "$base$url" : "$base/$url";
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Renders a message: inline image for image attachments, in-app playback
  /// for audio/video, a tappable file chip for other attachments, plain text
  /// otherwise. The raw file link is never shown as bare text.
  Widget _messageBody(Map<String, dynamic> msg) {
    final content = maskChatLinks((msg["content"] ?? "").toString());
    final type = (msg["type"] ?? "TEXT").toString();
    final fileRaw = (msg["file"] ?? "").toString();

    if (fileRaw.isNotEmpty) {
      final url = _absoluteUrl(fileRaw);
      if (type.toUpperCase() == "AUDIO" || _isAudioName(fileRaw)) {
        return AudioMessageBubble(url: url, accent: AppPalette.primary);
      }
      if (type.toUpperCase() == "VIDEO" || _isVideoName(fileRaw)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => _openVideoViewer(url),
              child: Container(
                width: 220,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(LucideIcons.playCircle,
                      color: Colors.white, size: 44),
                ),
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(content),
            ],
          ],
        );
      }
      if (_isImageMessage(type, fileRaw)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: () => _openImageViewer(url),
                child: CachedNetworkImage(
                  imageUrl: url,
                  width: 220,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => const SizedBox(
                    width: 220,
                    height: 150,
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (c, u, e) =>
                      _fileChip(url, "Image indisponible"),
                ),
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(content),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _fileChip(url, "Pièce jointe"),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(content),
          ],
        ],
      );
    }
    return Text(content);
  }

  Widget _fileChip(String url, String label) {
    return InkWell(
      onTap: () => _openUrl(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.fileText, size: 18),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppLoadingState(label: "Chargement des discussions...");
    }
    if (_error != null && _rooms.isEmpty) {
      return AppErrorState(message: _error!, onRetry: _initialLoad);
    }
    if (_rooms.isEmpty) {
      return AppEmptyState(
        title: "Aucune discussion",
        subtitle: "Les discussions avec vos clients apparaîtront ici.",
        onRetry: _initialLoad,
        icon: LucideIcons.messageCircle,
      );
    }

    final inConversation = _selectedRoomId != null;
    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: inConversation
          ? null
          : AppBar(
              backgroundColor: AppPalette.bg,
              surfaceTintColor: Colors.transparent,
              title: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Messagerie",
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                  Text(
                    "Temps réel · WebSocket",
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                        fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
      body: inConversation ? _buildConversationView() : _buildInbox(),
    );
  }

  Widget _buildInbox() {
    return Column(
      children: [
        // Barre de recherche (filtre local des conversations)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: "Rechercher conversation…",
              filled: true,
              fillColor: Colors.white,
              prefixIcon: const Icon(LucideIcons.search, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5DECC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5DECC)),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Chips filtres (par rôle de l'interlocuteur)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _FilterChip(
                label: "Tous",
                selected: _selectedFilter == 0,
                onTap: () => setState(() => _selectedFilter = 0),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: "Clients",
                selected: _selectedFilter == 1,
                onTap: () => setState(() => _selectedFilter = 1),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: "Livreurs",
                selected: _selectedFilter == 2,
                onTap: () => setState(() => _selectedFilter = 2),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: "Support",
                selected: _selectedFilter == 3,
                onTap: () => setState(() => _selectedFilter = 3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildRoomList()),
      ],
    );
  }

  bool _matchesFilter(Map<String, dynamic> room) {
    final query = _query.trim().toLowerCase();
    if (query.isNotEmpty &&
        !_roomLabel(room).toLowerCase().contains(query)) {
      return false;
    }
    if (_selectedFilter == 0) return true;
    final role = (_peerOf(room)?["role"] ?? "").toString();
    return switch (_selectedFilter) {
      1 => role == "BUYER",
      2 => role == "TRANSIT_AGENT",
      3 => role == "GENERAL_ADMIN",
      _ => true,
    };
  }

  Widget _buildRoomList() {
    final rooms = _rooms.where(_matchesFilter).toList();
    if (rooms.isEmpty) {
      return const Center(
        child: Text("Aucune conversation dans ce filtre.",
            style: TextStyle(color: Colors.black45)),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRooms,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: rooms.length,
        itemBuilder: (context, index) {
          final room = rooms[index];
          final peer = _peerOf(room);
          final initials = _roomInitials(room);
          final avatarColor = _roomAvatarColor(index);
          final unread = (room["unread_count"] ?? 0) as int;
          final lastMessage = room["last_message"];
          final snippet = lastMessage is Map
              ? maskChatLinks((lastMessage["snippet"] ?? "").toString())
              : "Touchez pour ouvrir la conversation";
          final timeLabel = lastMessage is Map
              ? _inboxTimeLabel((lastMessage["created_at"] ?? "").toString())
              : "";
          final avatarUrl = (peer?["avatar_url"] ?? "").toString();
          final online = peer?["is_online"] == true;

          return ListTile(
            leading: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor: avatarColor,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? CachedNetworkImageProvider(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          initials,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14),
                        )
                      : null,
                ),
                if (online)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    _roomLabel(room),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            unread > 0 ? FontWeight.w700 : FontWeight.w600,
                        fontSize: 14),
                  ),
                ),
                Text(
                  timeLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          unread > 0 ? FontWeight.w700 : FontWeight.w400,
                      color: unread > 0
                          ? AppPalette.primary
                          : const Color(0xFF9E9E9E)),
                ),
              ],
            ),
            subtitle: Row(
              children: [
                Expanded(
                  child: Text(
                    snippet,
                    style: TextStyle(
                        fontSize: 12,
                        color: unread > 0
                            ? Colors.black87
                            : const Color(0xFF9E9E9E)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (unread > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppPalette.secondary,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                    child: Text(
                      unread > 99 ? "99+" : "$unread",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
            onTap: () => _openRoom(room["id"] as int),
          );
        },
      ),
    );
  }

  Widget _buildConversationView() {
    final room = _selectedRoom;
    final peer = _peerOf(room);
    final presence = _presenceLabel(peer);
    return SafeArea(
      child: Column(
        children: [
          // Header : interlocuteur + présence/typing
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.chevronLeft, size: 20),
                  onPressed: () {
                    setState(() {
                      _selectedRoomId = null;
                      _messages = const [];
                      _peerTyping = false;
                    });
                    _loadRooms();
                  },
                ),
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppPalette.primary,
                  backgroundImage:
                      ((peer?["avatar_url"] ?? "") as String).isNotEmpty
                          ? CachedNetworkImageProvider(
                              (peer!["avatar_url"]).toString())
                          : null,
                  child: ((peer?["avatar_url"] ?? "") as String).isEmpty
                      ? Text(
                          room != null ? _roomInitials(room) : "?",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        room != null ? _roomLabel(room) : "Discussion",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      if (presence.isNotEmpty)
                        Text(
                          presence,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _peerTyping
                                ? AppPalette.primary
                                : (peer?["is_online"] == true
                                    ? const Color(0xFF22C55E)
                                    : Colors.black45),
                            fontWeight: _peerTyping
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw, size: 18),
                  onPressed: () {
                    _loadMessages(reset: true);
                    _loadRooms();
                  },
                ),
              ],
            ),
          ),
          // Messages (reverse : index 0 en bas = plus récent)
          Expanded(
            child: Stack(
              children: [
                ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageItem(index),
                ),
                if (_showScrollDown)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Material(
                      elevation: 3,
                      shape: const CircleBorder(),
                      color: Colors.white,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _animateToBottom,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(LucideIcons.chevronDown,
                              color: AppPalette.primary),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildMessageItem(int index) {
    final msg = _messages[index];
    final mine = _isMine(msg);
    final at = _createdAt(msg);
    final failed = msg["failed"] == true;
    final highlighted = _highlightedId != null && msg["id"] == _highlightedId;

    final bubble = Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      constraints: const BoxConstraints(maxWidth: 320),
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFFBBDEFB)
            : (mine ? const Color(0xFFDCF8C6) : Colors.white),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(14),
          topRight: const Radius.circular(14),
          bottomLeft: Radius.circular(mine ? 14 : 3),
          bottomRight: Radius.circular(mine ? 3 : 14),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _replyQuote(msg),
          _messageBody(msg),
          const SizedBox(height: 3),
          // Heure + ticks de statut (façon WhatsApp).
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (failed)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Text(
                    "Échec — appuyez pour renvoyer",
                    style: TextStyle(fontSize: 10.5, color: Colors.redAccent),
                  ),
                )
              else
                Text(
                  at != null ? _timeLabel(at) : "",
                  style:
                      const TextStyle(fontSize: 10.5, color: Colors.black45),
                ),
              if (mine) ...[
                const SizedBox(width: 4),
                _statusTicks(msg),
              ],
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (_needsDayDivider(index) && at != null)
          _DayDivider(label: _dayLabel(at)),
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Dismissible(
            key: ValueKey("chat-msg-${msg["id"]}"),
            direction: DismissDirection.startToEnd,
            dismissThresholds: const {DismissDirection.startToEnd: 0.25},
            // Swipe-to-reply : le geste n'écarte jamais la bulle, il arme la
            // réponse et revient en place (confirmDismiss=false).
            confirmDismiss: (_) async {
              HapticFeedback.lightImpact();
              setState(() => _replyingTo = msg);
              return false;
            },
            background: const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child:
                    Icon(LucideIcons.reply, color: AppPalette.primary, size: 20),
              ),
            ),
            child: GestureDetector(
              onLongPress: () => _showMessageActions(msg),
              onTap: failed ? () => _retryFailed(msg) : null,
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  bubble,
                  _reactionPills(msg),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppPalette.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyingTo != null) _buildReplyBar(),
          if (_recording)
            VoiceRecordingBar(
              recorder: _voice,
              accent: AppPalette.primary,
              onCancel: _cancelRecording,
              onSend: _stopAndSendVoice,
            )
          else
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showEmoji = !_showEmoji);
                  },
                  icon: Icon(
                      _showEmoji ? LucideIcons.keyboard : LucideIcons.smile,
                      color: AppPalette.textMuted),
                ),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onTap: () {
                      if (_showEmoji) setState(() => _showEmoji = false);
                    },
                    onChanged: (value) {
                      if (value.trim().isNotEmpty) _sendTyping();
                    },
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: "Tapez un message",
                      filled: true,
                      fillColor: const Color(0xFFF2F4F7),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sendAttachment,
                  icon: const Icon(LucideIcons.paperclip),
                ),
                IconButton(
                  onPressed: _startRecording,
                  icon: const Icon(LucideIcons.mic),
                  tooltip: "Note vocale",
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: AppPalette.primary,
                  ),
                  onPressed: _sendMessage,
                  icon: const Icon(LucideIcons.send),
                ),
              ],
            ),
          if (_showEmoji)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _messageController,
              ),
            ),
        ],
      ),
    );
  }

  /// Barre au-dessus du composer indiquant le message auquel on répond.
  Widget _buildReplyBar() {
    final replying = _replyingTo;
    final snippet = replying == null ? "" : _previewOf(replying);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(10),
        border: const Border(
            left: BorderSide(color: AppPalette.primary, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(LucideIcons.reply, size: 16, color: AppPalette.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              snippet,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: const Icon(LucideIcons.x, size: 16, color: Colors.black45),
          ),
        ],
      ),
    );
  }
}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppPalette.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppPalette.primary : const Color(0xFFE5DECC),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF666666),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Séparateur de jour centré (Aujourd'hui / Hier / date).
class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFE1EBF2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF54656F),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// Visionneuse plein écran zoomable pour les images du chat (sans dépendance).
class _ImageViewerPage extends StatelessWidget {
  const _ImageViewerPage({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (_, __, ___) => const Icon(
              LucideIcons.imageOff,
              color: Colors.white38,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

/// Lecture plein écran d'une vidéo reçue dans le chat (réutilise le player du
/// feed : contrôles seek/mute, pause auto hors écran).
class _ChatVideoPage extends StatelessWidget {
  const _ChatVideoPage({required this.videoUrl});
  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: VideoPostPlayer(videoUrl: videoUrl, coverUrl: ""),
    );
  }
}

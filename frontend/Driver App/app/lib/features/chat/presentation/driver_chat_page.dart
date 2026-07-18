import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/network/upload_mime.dart';
import '../../../core/realtime_events_service.dart';
import '../../../core/theme/driver_theme.dart';
import '../../auth/application/auth_notifier.dart';

/// Palette de réactions rapides (long-press sur une bulle, façon WhatsApp).
const List<String> kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// Conversation de coordination livraison (livreur ↔ acheteur).
///
/// Réutilise l'API chat partagée (`/api/chat/messages/`, receipts, réactions)
/// et le flux temps réel `/ws/events/` (événements ciblés + typing) — aucun
/// stack de messagerie parallèle. Ouverte depuis « Contacter l'acheteur »
/// (via l'action backend `/api/shipments/{id}/contact/`) ou la liste des
/// discussions.
class DriverChatPage extends ConsumerStatefulWidget {
  const DriverChatPage({super.key, required this.roomId, required this.title});

  final int roomId;
  final String title;

  @override
  ConsumerState<DriverChatPage> createState() => _DriverChatPageState();
}

class _DriverChatPageState extends ConsumerState<DriverChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  // Messages du salon, ordre ANTÉ-chronologique (index 0 = plus récent),
  // aligné sur l'API et rendu par une ListView reverse (ouverture en bas).
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _showScrollDown = false;
  String? _error;
  int _page = 1;
  bool _hasMore = true;
  int? _myId;
  Map<String, dynamic>? _peer;
  Map<String, dynamic>? _replyingTo;
  // Envoi optimiste : ids locaux négatifs, remplacés par la réponse serveur.
  int _localIdSeq = -1;
  // Typing : throttle d'émission + timer d'effacement de l'indicateur reçu.
  DateTime? _typingSentAt;
  bool _peerTyping = false;
  Timer? _typingClearTimer;
  // Surbrillance temporaire après un saut vers le message cité.
  int? _highlightedId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _myId = ref.read(authProvider).userId;
    _load(reset: true);
    _loadPeer();
    _scroll.addListener(_onScroll);
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'chat')) {
        _onChatEvent(event);
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _typingClearTimer?.cancel();
    _highlightTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ── Temps réel incrémental ──────────────────────────────────────────────

  void _onChatEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? '').toString();
    final raw = event['payload'];
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    switch (type) {
      case 'message_created':
        if (data['room'] == widget.roomId) {
          final id = data['id'];
          if (id is int && !_messages.any((m) => m['id'] == id)) {
            setState(() => _messages = [data, ..._messages]);
          }
          _markRoomRead();
          if (!_showScrollDown) _scrollToBottomSoon();
        }
      case 'message_state':
        _applyState(data['message_id'], (data['state'] ?? '').toString());
      case 'room_read':
        if (data['room'] == widget.roomId) {
          setState(() {
            _messages = _messages
                .map((m) =>
                    m['sender'] == _myId ? {...m, 'my_state': 'READ'} : m)
                .toList();
          });
        }
      case 'message_reaction':
        final id = data['message_id'];
        if (id is int) {
          final reactions = _mapReactions(data['reactions']);
          setState(() {
            _messages = _messages
                .map((m) => m['id'] == id ? {...m, 'reactions': reactions} : m)
                .toList();
          });
        }
      case 'typing':
        if (data['room'] == widget.roomId && data['user_id'] != _myId) {
          _typingClearTimer?.cancel();
          setState(() => _peerTyping = data['is_typing'] == true);
          if (_peerTyping) {
            _typingClearTimer = Timer(const Duration(seconds: 5), () {
              if (mounted) setState(() => _peerTyping = false);
            });
          }
        }
      default:
        // resync (reconnexion) ou événement inconnu : re-synchronisation REST.
        _load(reset: true);
    }
  }

  void _applyState(dynamic id, String state) {
    if (id is! int || state.isEmpty) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m['id'] != id) return m;
        if ((m['my_state'] ?? '') == 'READ') return m;
        return {...m, 'my_state': state};
      }).toList();
    });
  }

  List<Map<String, dynamic>> _mapReactions(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((entry) {
      final userIds = (entry['user_ids'] is List)
          ? List.from(entry['user_ids'] as List)
          : const [];
      return <String, dynamic>{
        'emoji': (entry['emoji'] ?? '').toString(),
        'count': entry['count'] ?? 0,
        'mine': entry.containsKey('mine')
            ? entry['mine'] == true
            : (_myId != null && userIds.contains(_myId)),
      };
    }).toList();
  }

  /// Émission du signal typing, throttlée (max ~1 toutes les 2,5 s).
  void _sendTyping() {
    final now = DateTime.now();
    if (_typingSentAt != null &&
        now.difference(_typingSentAt!) < const Duration(milliseconds: 2500)) {
      return;
    }
    _typingSentAt = now;
    RealtimeEventsService.instance
        .send({'type': 'typing', 'room': widget.roomId, 'is_typing': true});
  }

  // ── Chargements REST ─────────────────────────────────────────────────────

  Future<void> _load({required bool reset}) async {
    final nextPage = reset ? 1 : _page + 1;
    try {
      final res = await DriverDioClient.dio
          .get('/api/chat/messages/?room=${widget.roomId}&page=$nextPage');
      final raw = res.data;
      final rows = <Map<String, dynamic>>[
        if (raw is List) ...raw.cast<Map<String, dynamic>>(),
        if (raw is Map && raw['results'] is List)
          ...(raw['results'] as List).cast<Map<String, dynamic>>(),
      ];
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _hasMore = rows.length >= 20;
        // API anté-chronologique : page 1 = plus récents, pages suivantes =
        // historique, ajouté en FIN de liste (haut du fil en rendu inversé).
        _messages = reset ? rows : [..._messages, ...rows];
        _loading = false;
        _error = null;
      });
      if (reset) _markRoomRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiError.friendly(e);
      });
    }
  }

  /// Fiche de l'interlocuteur (présence incluse) depuis la liste des salons.
  Future<void> _loadPeer() async {
    try {
      final res = await DriverDioClient.dio.get('/api/chat/rooms/');
      final raw = res.data;
      final rows = <Map<String, dynamic>>[
        if (raw is List) ...raw.cast<Map<String, dynamic>>(),
        if (raw is Map && raw['results'] is List)
          ...(raw['results'] as List).cast<Map<String, dynamic>>(),
      ];
      final room = rows.firstWhere(
        (r) => r['id'] == widget.roomId,
        orElse: () => const <String, dynamic>{},
      );
      final peer = room['peer'];
      if (mounted && peer is Map) {
        setState(() => _peer = Map<String, dynamic>.from(peer));
      }
    } catch (_) {
      // Présence indisponible : le titre passé en paramètre reste affiché.
    }
  }

  /// Marque TOUT le salon lu en un POST (remplace la boucle par message).
  void _markRoomRead() {
    DriverDioClient.dio
        .post('/api/chat/rooms/${widget.roomId}/mark_read/', data: {})
        .catchError((_) => Response(requestOptions: RequestOptions()));
  }

  // ── Envois ───────────────────────────────────────────────────────────────

  /// Envoi optimiste : la bulle apparaît immédiatement (horloge), puis est
  /// remplacée par la version serveur ; en échec, état « renvoyer » au tap.
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final replyingTo = _replyingTo;
    final local = <String, dynamic>{
      'id': _localIdSeq--,
      'room': widget.roomId,
      'sender': _myId,
      'type': 'TEXT',
      'content': text,
      'created_at': DateTime.now().toIso8601String(),
      'pending': true,
      'failed': false,
      'reactions': const [],
      if (replyingTo != null) 'reply_to': replyingTo['id'],
      if (replyingTo != null)
        'reply_preview': {
          'id': replyingTo['id'],
          'type': replyingTo['type'],
          'snippet': _previewOf(replyingTo),
        },
    };
    _input.clear();
    setState(() {
      _messages = [local, ..._messages];
      _replyingTo = null;
    });
    _scrollToBottomSoon();
    await _postPending(local);
  }

  Future<void> _postPending(Map<String, dynamic> local) async {
    try {
      final res = await DriverDioClient.dio.post('/api/chat/messages/', data: {
        'room': local['room'],
        'content': local['content'],
        'type': 'TEXT',
        if (local['reply_to'] != null) 'reply_to': local['reply_to'],
      });
      final created = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m['id'] == local['id'] ? created : m)
            .toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages = _messages
            .map((m) => m['id'] == local['id']
                ? {...m, 'pending': false, 'failed': true}
                : m)
            .toList();
      });
    }
  }

  Future<void> _retryFailed(Map<String, dynamic> message) async {
    setState(() {
      _messages = _messages
          .map((m) => m['id'] == message['id']
              ? {...m, 'pending': true, 'failed': false}
              : m)
          .toList();
    });
    await _postPending(message);
  }

  Future<void> _sendAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final norm = normalizeUpload(file.name);
    try {
      final MultipartFile mf;
      // Jamais fromStream : sur Android le flux file_picker peut bloquer l'envoi.
      if (!kIsWeb && (file.path ?? '').isNotEmpty) {
        mf = await MultipartFile.fromFile(file.path!,
            filename: norm.filename, contentType: norm.mime);
      } else if (file.bytes != null && file.bytes!.isNotEmpty) {
        mf = MultipartFile.fromBytes(file.bytes!,
            filename: norm.filename, contentType: norm.mime);
      } else {
        _snack('Fichier inaccessible sur cette plateforme.');
        return;
      }
      final res = await DriverDioClient.dio.post(
        '/api/chat/messages/',
        data: FormData.fromMap({
          'room': widget.roomId.toString(),
          'type': _attachmentType(file.name),
          'file': mf,
        }),
      );
      final created = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() => _messages = [created, ..._messages]);
      _scrollToBottomSoon();
    } catch (e) {
      _snack(ApiError.friendly(e));
    }
  }

  // ── Réactions ────────────────────────────────────────────────────────────

  Future<void> _react(Map<String, dynamic> message, String emoji) async {
    final id = message['id'];
    if (id is! int || id <= 0) return;
    try {
      final res = await DriverDioClient.dio
          .post('/api/chat/messages/$id/react/', data: {'emoji': emoji});
      if (!mounted) return;
      final reactions =
          _mapReactions(res.data is Map ? res.data['reactions'] : null);
      setState(() {
        _messages = _messages
            .map((m) => m['id'] == id ? {...m, 'reactions': reactions} : m)
            .toList();
      });
    } catch (e) {
      _snack(ApiError.friendly(e));
    }
  }

  /// Menu contextuel de bulle (long-press) : réactions rapides + actions.
  void _showMessageActions(Map<String, dynamic> message) {
    final content = (message['content'] ?? '').toString();
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
                        child: Padding(
                          padding: const EdgeInsets.all(8),
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
              title: const Text('Répondre'),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyingTo = message);
              },
            ),
            if (content.isNotEmpty)
              ListTile(
                leading: const Icon(LucideIcons.copy),
                title: const Text('Copier'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: content));
                  Navigator.pop(sheetContext);
                },
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Scroll / navigation dans le fil ─────────────────────────────────────

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    // ListView reverse : offset 0 = bas du fil (messages récents).
    final far = p.pixels > 400;
    if (far != _showScrollDown) setState(() => _showScrollDown = far);
    // Près du HAUT (fin de l'offset) : charger l'historique plus ancien.
    if (_hasMore && !_loading && p.pixels >= p.maxScrollExtent - 180) {
      _load(reset: false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(0);
    });
  }

  void _animateToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0,
        duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
  }

  /// Saute (approximativement) vers le message cité et le surligne ~1 s.
  void _jumpToMessage(int messageId) {
    final index = _messages.indexWhere((m) => m['id'] == messageId);
    if (index < 0) {
      _snack('Message plus ancien — remontez le fil.');
      return;
    }
    if (_scroll.hasClients && _messages.length > 1) {
      final target =
          (index / (_messages.length - 1)) * _scroll.position.maxScrollExtent;
      _scroll.animateTo(
        target.clamp(0.0, _scroll.position.maxScrollExtent),
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

  // ── Helpers d'affichage ──────────────────────────────────────────────────

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

  bool _isAudioName(String name) {
    final n = name.toLowerCase().split('?').first;
    return n.endsWith('.m4a') ||
        n.endsWith('.aac') ||
        n.endsWith('.mp3') ||
        n.endsWith('.ogg') ||
        n.endsWith('.opus') ||
        n.endsWith('.wav');
  }

  String _attachmentType(String name) {
    if (_isImageName(name)) return 'IMAGE';
    if (_isVideoName(name)) return 'VIDEO';
    return 'DOCUMENT';
  }

  String _absUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final base = AppConfig.apiBaseUrl;
    return url.startsWith('/') ? '$base$url' : '$base/$url';
  }

  String _previewOf(Map<String, dynamic> msg) {
    final content = (msg['content'] ?? '').toString().trim();
    if (content.isNotEmpty) return content;
    return const {
          'IMAGE': '📷 Photo',
          'VIDEO': '🎥 Vidéo',
          'AUDIO': '🎤 Note vocale',
          'DOCUMENT': '📎 Document',
        }[(msg['type'] ?? '').toString().toUpperCase()] ??
        'Pièce jointe';
  }

  DateTime? _createdAt(Map<String, dynamic> m) =>
      DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal();

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (diff == 0) return "Aujourd'hui";
    if (diff == 1) return 'Hier';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _timeLabel(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Ligne de présence sous le titre (typing / en ligne / vu à HH:MM).
  String _presenceLabel() {
    if (_peerTyping) return 'écrit…';
    final peer = _peer;
    if (peer == null) return '';
    if (peer['is_online'] == true) return 'en ligne';
    final lastSeen =
        DateTime.tryParse((peer['last_seen_at'] ?? '').toString())?.toLocal();
    if (lastSeen == null) return '';
    final day = _dayLabel(lastSeen);
    if (day == "Aujourd'hui") return 'vu à ${_timeLabel(lastSeen)}';
    if (day == 'Hier') return 'vu hier à ${_timeLabel(lastSeen)}';
    return 'vu le $day';
  }

  /// Liste anté-chronologique rendue en reverse : le message ouvre sa journée
  /// quand le message PLUS ANCIEN (index+1) est d'un autre jour.
  bool _needsDivider(int i) {
    final cur = _createdAt(_messages[i]);
    if (cur == null) return false;
    if (i == _messages.length - 1) return !_hasMore;
    final older = _createdAt(_messages[i + 1]);
    if (older == null) return true;
    return cur.year != older.year ||
        cur.month != older.month ||
        cur.day != older.day;
  }

  bool _isMine(Map<String, dynamic> m) {
    final s = m['sender'];
    return _myId != null && s is int && s == _myId;
  }

  @override
  Widget build(BuildContext context) {
    final peerName = (_peer?['username'] ?? '').toString();
    final presence = _presenceLabel();
    return Scaffold(
      backgroundColor: const Color(0xFFEBF5E4),
      appBar: AppBar(
        backgroundColor: DriverPalette.primary,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(peerName.isNotEmpty ? peerName : widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            if (presence.isNotEmpty)
              Text(
                presence,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      _peerTyping ? FontWeight.w700 : FontWeight.w400,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? _ErrorView(message: _error!, onRetry: () => _load(reset: true))
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) =>
                                _buildMessageItem(index),
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
                                        color: DriverPalette.primary),
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
    final failed = msg['failed'] == true;
    final highlighted = _highlightedId != null && msg['id'] == _highlightedId;

    return Column(
      children: [
        if (_needsDivider(index) && at != null)
          _DayDivider(label: _dayLabel(at)),
        Dismissible(
          key: ValueKey('driver-msg-${msg['id']}'),
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
              child: Icon(LucideIcons.reply,
                  color: DriverPalette.primary, size: 20),
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
                _Bubble(
                  message: msg,
                  mine: mine,
                  highlighted: highlighted,
                  time: at != null ? _timeLabel(at) : '',
                  absUrl: _absUrl,
                  isImageName: _isImageName,
                  isVideoName: _isVideoName,
                  isAudioName: _isAudioName,
                  onQuoteTap: _jumpToMessage,
                ),
                _reactionPills(msg),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Pastilles de réactions agrégées sous la bulle (tap = toggle si à moi).
  Widget _reactionPills(Map<String, dynamic> msg) {
    final raw = msg['reactions'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final mine = _isMine(msg);
    return Padding(
      padding: EdgeInsets.only(
          bottom: 4, left: mine ? 0 : 6, right: mine ? 6 : 0, top: 1),
      child: Wrap(
        spacing: 4,
        children: raw.whereType<Map>().map((reaction) {
          final emoji = (reaction['emoji'] ?? '').toString();
          final count = reaction['count'] ?? 0;
          final isMine = reaction['mine'] == true;
          return GestureDetector(
            onTap: () => _react(msg, emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFFD6EBD0) : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                    color: isMine
                        ? DriverPalette.primary
                        : const Color(0xFFE2E8F0)),
              ),
              child: Text(
                count is int && count > 1 ? '$emoji $count' : emoji,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        color: const Color(0xFFEBF5E4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border(
                      left: BorderSide(
                          color: DriverPalette.primary, width: 3)),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.reply,
                        size: 16, color: DriverPalette.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _previewOf(_replyingTo!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.black54),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = null),
                      child: const Icon(LucideIcons.x,
                          size: 16, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  onPressed: _sendAttachment,
                  icon: const Icon(LucideIcons.paperclip,
                      color: Color(0xFF54656F)),
                  tooltip: 'Joindre un fichier',
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: DriverPalette.border),
                    ),
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      onChanged: (value) {
                        if (value.trim().isNotEmpty) _sendTyping();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Message…',
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: DriverPalette.primary, shape: BoxShape.circle),
                    child: const Icon(LucideIcons.send,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.highlighted,
    required this.time,
    required this.absUrl,
    required this.isImageName,
    required this.isVideoName,
    required this.isAudioName,
    required this.onQuoteTap,
  });

  final Map<String, dynamic> message;
  final bool mine;
  final bool highlighted;
  final String time;
  final String Function(String) absUrl;
  final bool Function(String) isImageName;
  final bool Function(String) isVideoName;
  final bool Function(String) isAudioName;
  final void Function(int) onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final content = (message['content'] ?? '').toString();
    final type = (message['type'] ?? 'TEXT').toString().toUpperCase();
    final fileRaw = (message['file'] ?? '').toString();
    final pending = message['pending'] == true;
    final failed = message['failed'] == true;
    final state = mine ? (message['my_state'] ?? '').toString() : '';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
            bottom: 4, left: mine ? 60 : 0, right: mine ? 0 : 60),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
            BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _quote(),
            _body(context, type, content, fileRaw),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (failed)
                  const Text('Échec — appuyez pour renvoyer',
                      style: TextStyle(
                          fontSize: 10.5, color: Colors.redAccent))
                else if (time.isNotEmpty)
                  Text(time,
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.black45)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  if (pending)
                    const Icon(LucideIcons.clock,
                        size: 12, color: Colors.black38)
                  else if (failed)
                    const Icon(LucideIcons.alertCircle,
                        size: 13, color: Colors.redAccent)
                  else if (state.isNotEmpty)
                    Icon(
                      state == 'READ' || state == 'DELIVERED'
                          ? LucideIcons.checkCheck
                          : LucideIcons.check,
                      size: 13,
                      color: state == 'READ'
                          ? const Color(0xFF34B7F1)
                          : Colors.black38,
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Encart du message cité en tête de bulle. Tap → saut vers l'original.
  Widget _quote() {
    final preview = message['reply_preview'];
    if (preview is! Map) return const SizedBox.shrink();
    final snippet = (preview['snippet'] ?? '').toString();
    if (snippet.isEmpty) return const SizedBox.shrink();
    final parentId = preview['id'];
    return GestureDetector(
      onTap: parentId is int ? () => onQuoteTap(parentId) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 5),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: const BoxDecoration(
          color: Color(0x0F000000),
          borderRadius: BorderRadius.all(Radius.circular(8)),
          border:
              Border(left: BorderSide(color: DriverPalette.primary, width: 3)),
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

  Widget _body(BuildContext context, String type, String content, String fileRaw) {
    const textStyle = TextStyle(fontSize: 14.5, color: Color(0xFF111827), height: 1.35);
    if (fileRaw.isNotEmpty) {
      final url = absUrl(fileRaw);
      if (type == 'AUDIO' || isAudioName(fileRaw)) {
        return _AudioBubble(url: url);
      }
      if (type == 'IMAGE' || isImageName(fileRaw)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => _ImageViewerPage(imageUrl: url))),
                child: Image.network(url,
                    width: 220,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, p) => p == null
                        ? child
                        : const SizedBox(
                            width: 220,
                            height: 150,
                            child: Center(
                                child: CircularProgressIndicator(strokeWidth: 2))),
                    errorBuilder: (c, e, s) => const SizedBox(
                        width: 220, height: 100, child: Icon(LucideIcons.imageOff))),
              ),
            ),
            if (content.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(content, style: textStyle),
            ],
          ],
        );
      }
      // Vidéo ou document : chip cliquable, ouverture externe.
      final isVideo = type == 'VIDEO' || isVideoName(fileRaw);
      return InkWell(
        onTap: () => launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isVideo ? LucideIcons.playCircle : LucideIcons.fileText,
                size: 18, color: DriverPalette.textMuted),
            const SizedBox(width: 4),
            Flexible(
                child: Text(isVideo ? 'Vidéo' : 'Pièce jointe',
                    style: const TextStyle(
                        color: DriverPalette.textMuted,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline))),
          ],
        ),
      );
    }
    return Text(content, style: textStyle);
  }
}

/// Bulle de lecture d'une note vocale (play/pause + progression + vitesse).
class _AudioBubble extends StatefulWidget {
  const _AudioBubble({required this.url});
  final String url;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false;
  // Vitesse de lecture cyclique 1x → 1.5x → 2x (façon WhatsApp).
  static const List<double> _speeds = [1.0, 1.5, 2.0];
  double _speed = 1.0;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lecture audio impossible.')),
        );
      }
    }
  }

  Future<void> _cycleSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    try {
      await _player.setSpeed(next);
    } catch (_) {
      // Certains codecs refusent setSpeed : on garde la lecture normale.
    }
  }

  String _fmt(int s) =>
      '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (_, snap) {
              final playing = snap.data?.playing ?? false;
              final completed =
                  snap.data?.processingState == ProcessingState.completed;
              return IconButton(
                onPressed: _toggle,
                icon: Icon(
                  playing && !completed
                      ? LucideIcons.pauseCircle
                      : LucideIcons.playCircle,
                  color: DriverPalette.primary,
                  size: 34,
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (_, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                final value = (total.inMilliseconds == 0)
                    ? 0.0
                    : (pos.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: value == 0 ? null : value,
                      minHeight: 3,
                      backgroundColor: Colors.black12,
                      color: DriverPalette.primary,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(LucideIcons.mic,
                            size: 12, color: Colors.black38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            total == Duration.zero
                                ? 'Note vocale'
                                : '${_fmt(pos.inSeconds)} / ${_fmt(total.inSeconds)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45),
                          ),
                        ),
                        if (total != Duration.zero)
                          GestureDetector(
                            onTap: _cycleSpeed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _speed == 1.0
                                    ? '1x'
                                    : (_speed == 1.5 ? '1.5x' : '2x'),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF54656F))),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.alertCircle, size: 44, color: DriverPalette.textMuted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: DriverPalette.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

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
          child: Image.network(imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (c, e, s) =>
                  const Icon(LucideIcons.imageOff, color: Colors.white38, size: 64)),
        ),
      ),
    );
  }
}

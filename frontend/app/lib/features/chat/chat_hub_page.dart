import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

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
  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  String? _error;
  int? _selectedRoomId;
  int _page = 1;
  bool _hasMore = true;
  String _query = '';
  bool _sending = false;

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
    _loadRooms();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'chat')) {
        _loadRooms();
      }
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRooms() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final rooms = await _api.getList('/api/chat/rooms/', token: token);
      final preferredId = widget.initialRoomId;
      final selected = rooms.any((r) => r['id'] == _selectedRoomId)
          ? _selectedRoomId
          : (preferredId != null &&
                  rooms.any((r) => r['id'] == preferredId))
              ? preferredId
              : (rooms.isNotEmpty ? rooms.first['id'] as int? : null);
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _selectedRoomId = selected;
      });
      await _loadMessages(reset: true);
      _error = null;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rooms = const [];
        _messages = const [];
        _error = _api.toUserMessage(e, fallback: 'Impossible de charger les discussions.');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMessages({required bool reset}) async {
    if (_selectedRoomId == null) return;
    final token = context.read<SessionStore>().token;
    final nextPage = reset ? 1 : _page + 1;
    final q = _query.trim();
    final path =
        '/api/chat/messages/?room=$_selectedRoomId&page=$nextPage${q.isNotEmpty ? '&q=${Uri.encodeQueryComponent(q)}' : ''}';
    try {
      final rows = await _api.getList(path, token: token);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _hasMore = rows.length >= 20;
        _messages = reset ? rows : [..._messages, ...rows];
      });
      _markVisibleAsRead(rows);
      _scrollToBottom();
      _error = null;
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _api.toUserMessage(e));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _hasMore == false || _loading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 180) {
      _loadMessages(reset: false);
    }
  }

  Future<void> _markVisibleAsRead(List<Map<String, dynamic>> rows) async {
    final token = context.read<SessionStore>().token;
    final myId = context.read<SessionStore>().userId;
    for (final msg in rows) {
      final id = msg['id'];
      final sender = msg['sender'];
      if (id is int && sender is int && myId != null && sender != myId) {
        try {
          await _api.post('/api/chat/messages/$id/mark_delivered/', {}, token: token);
          await _api.post('/api/chat/messages/$id/mark_read/', {}, token: token);
        } catch (_) {}
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedRoomId == null || _sending) return;
    final token = context.read<SessionStore>().token;
    setState(() => _sending = true);
    try {
      await _api.post(
        '/api/chat/messages/',
        {'room': _selectedRoomId, 'content': text, 'type': 'TEXT'},
        token: token,
      );
      _messageController.clear();
      await _loadMessages(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_api.toUserMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendAttachment() async {
    if (_selectedRoomId == null) return;
    final token = context.read<SessionStore>().token;
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final selected = picked.files.single;
    final hasPath = _safePlatformFilePath(selected) != null;
    final hasBytes = selected.bytes != null && selected.bytes!.isNotEmpty;
    if (!hasPath && !hasBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier non accessible sur cette plateforme.')),
      );
      return;
    }
    try {
      await _api.postMultipart(
        '/api/chat/messages/',
        fields: {
          'room': _selectedRoomId.toString(),
          'content': _messageController.text.trim(),
          'type': 'DOCUMENT',
        },
        file: selected,
        token: token,
      );
      _messageController.clear();
      await _loadMessages(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_api.toUserMessage(e))));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  bool _isMine(Map<String, dynamic> msg) {
    final myId = context.read<SessionStore>().userId;
    final sender = msg['sender'];
    return myId != null && sender is int && sender == myId;
  }

  Map<String, dynamic>? get _selectedRoom {
    if (_selectedRoomId == null) return null;
    try {
      return _rooms.firstWhere((r) => r['id'] == _selectedRoomId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEBF5E4),
      body: Column(
        children: [
          _ChatAppBar(
            room: _selectedRoom,
            onRefresh: _loadRooms,
          ),
          _RoomList(
            rooms: _rooms,
            selectedRoomId: _selectedRoomId,
            onRoomSelected: (id) async {
              setState(() => _selectedRoomId = id);
              await _loadMessages(reset: true);
            },
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF075E54)),
                  )
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 48, color: AppPalette.textFaint),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppPalette.textMuted)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadRooms,
                                child: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _rooms.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.chat_bubble_outline,
                                    size: 64, color: AppPalette.textFaint),
                                const SizedBox(height: 12),
                                const Text('Aucune discussion',
                                    style: TextStyle(
                                        color: AppPalette.textMuted,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                const Text(
                                    'Démarrez une conversation depuis une commande.',
                                    style: TextStyle(
                                        color: AppPalette.textFaint,
                                        fontSize: 13.5),
                                    textAlign: TextAlign.center),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final mine = _isMine(msg);
                              return _MessageBubble(
                                message: msg,
                                isMine: mine,
                              );
                            },
                          ),
          ),
          _MessageInput(
            controller: _messageController,
            sending: _sending,
            onSend: _sendMessage,
            onAttachment: _sendAttachment,
          ),
        ],
      ),
    );
  }
}

// ─── App Bar ─────────────────────────────────────────────────────────────────

class _ChatAppBar extends StatelessWidget {
  const _ChatAppBar({required this.room, required this.onRefresh});
  final Map<String, dynamic>? room;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final roomName = room != null
        ? (room!['name'] ?? 'Discussion').toString()
        : 'Messages';

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF075E54),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  roomName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                iconSize: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Room List ────────────────────────────────────────────────────────────────

class _RoomList extends StatelessWidget {
  const _RoomList({
    required this.rooms,
    required this.selectedRoomId,
    required this.onRoomSelected,
  });

  final List<Map<String, dynamic>> rooms;
  final int? selectedRoomId;
  final ValueChanged<int> onRoomSelected;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 60,
      color: const Color(0xFF075E54),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        itemCount: rooms.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final room = rooms[index];
          final id = room['id'] as int?;
          final selected = id == selectedRoomId;
          final label =
              (room['name'] ?? 'Discussion ${room["id"]}').toString();
          return GestureDetector(
            onTap: id != null ? () => onRoomSelected(id) : null,
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                border: Border.all(
                  color: selected
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? const Color(0xFF075E54) : Colors.white,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
  });

  final Map<String, dynamic> message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final content = (message['content'] ?? '').toString();
    final type = (message['type'] ?? 'TEXT').toString().toUpperCase();
    final state = isMine ? (message['my_state'] ?? '').toString() : '';
    final timeRaw = (message['created_at'] ?? '').toString();
    final time = _formatTime(timeRaw);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          bottom: 4,
          left: isMine ? 60 : 0,
          right: isMine ? 0 : 60,
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: isMine ? const Color(0xFFDCF8C6) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMine ? 14 : 3),
                  bottomRight: Radius.circular(isMine ? 3 : 14),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (type == 'DOCUMENT')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file_rounded,
                            size: 16, color: AppPalette.textMuted),
                        const SizedBox(width: 4),
                        const Text('Pièce jointe',
                            style: TextStyle(
                                color: AppPalette.textMuted, fontSize: 13)),
                      ],
                    )
                  else
                    Text(
                      content,
                      style: const TextStyle(
                        fontSize: 14.5,
                        color: AppPalette.text,
                        height: 1.35,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppPalette.textFaint,
                          ),
                        ),
                      if (isMine && state.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _ReadReceipt(state: state),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTime(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ReadReceipt extends StatelessWidget {
  const _ReadReceipt({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = state == 'READ'
        ? Colors.blue
        : state == 'DELIVERED'
            ? AppPalette.textMuted
            : AppPalette.textFaint;
    return Icon(
      state == 'READ' || state == 'DELIVERED'
          ? Icons.done_all_rounded
          : Icons.done_rounded,
      size: 13,
      color: color,
    );
  }
}

// ─── Message Input ────────────────────────────────────────────────────────────

class _MessageInput extends StatelessWidget {
  const _MessageInput({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttachment,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttachment;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFEBF5E4),
          border: Border(
            top: BorderSide(color: Color(0xFFCDD8D0), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: onAttachment,
              icon: const Icon(Icons.attach_file_rounded,
                  color: Color(0xFF54656F)),
              tooltip: 'Joindre un fichier',
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppPalette.border),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: sending ? null : onSend,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF075E54),
                  shape: BoxShape.circle,
                ),
                child: sending
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
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
  String _query = "";
  int _selectedFilter = 0; // 0=Tous, 1=Fournisseurs, 2=Transitaires, 3=Support

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
    _loadRoomsAndFirstPage();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "chat")) {
        _loadRoomsAndFirstPage();
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

  Future<void> _loadRoomsAndFirstPage() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final rooms = await _api.getList("/api/chat/rooms/", token: token);
      final preferredRoomId = widget.initialRoomId;
      final selected = rooms.any((r) => r["id"] == _selectedRoomId)
          ? _selectedRoomId
          : (preferredRoomId != null &&
                  rooms.any((r) => r["id"] == preferredRoomId))
              ? preferredRoomId
              : (rooms.isNotEmpty ? rooms.first["id"] as int? : null);
      setState(() {
        _rooms = rooms;
        _selectedRoomId = selected;
      });
      await _loadMessages(reset: true);
      _error = null;
    } catch (e) {
      setState(() {
        _rooms = const [];
        _messages = const [];
      });
      _error = _api.toUserMessage(
        e,
        fallback: "Impossible de charger les discussions.",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
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
        _messages = reset ? rows : [..._messages, ...rows];
      });
      await _markVisibleAsDeliveredAndRead(rows);
      _scrollToBottomSoon();
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

  Future<void> _markVisibleAsDeliveredAndRead(
      List<Map<String, dynamic>> rows) async {
    final token = context.read<SessionStore>().token;
    final myId = context.read<SessionStore>().userId;
    for (final msg in rows) {
      final id = msg["id"];
      final sender = msg["sender"];
      if (id is int && sender is int && myId != null && sender != myId) {
        try {
          await _api.post("/api/chat/messages/$id/mark_delivered/", {},
              token: token);
          await _api.post("/api/chat/messages/$id/mark_read/", {},
              token: token);
        } catch (_) {}
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _selectedRoomId == null) return;
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/chat/messages/",
          {"room": _selectedRoomId, "content": text, "type": "TEXT"},
          token: token);
      _messageController.clear();
      await _loadMessages(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e))),
      );
    }
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
      await _api.postMultipart(
        "/api/chat/messages/",
        fields: {
          "room": _selectedRoomId.toString(),
          "content": _messageController.text.trim(),
          "type": "DOCUMENT",
        },
        file: selected,
        token: token,
      );
      _messageController.clear();
      await _loadMessages(reset: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e))),
      );
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasMore || _loading) return;
    final p = _scrollController.position;
    if (p.pixels >= p.maxScrollExtent - 180) {
      _loadMessages(reset: false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  bool _isMine(Map<String, dynamic> msg) {
    final myId = context.read<SessionStore>().userId;
    final sender = msg["sender"];
    return myId != null && sender is int && sender == myId;
  }

  String _roomLabel(Map<String, dynamic> room) {
    return (room["name"] ?? "Discussion ${room["id"]}").toString();
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

  Color _roomAvatarColor(int index) {
    const colors = [
      Color(0xFF0F7A4F),
      Color(0xFF0EA5E9),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFE5484D),
    ];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AppLoadingState(label: "Chargement des discussions...");
    }
    if (_error != null) {
      return AppErrorState(message: _error!, onRetry: _loadRoomsAndFirstPage);
    }
    if (_rooms.isEmpty) {
      return AppEmptyState(
        title: "Aucune discussion",
        subtitle: "Créez ou rejoignez une room pour démarrer.",
        onRetry: _loadRoomsAndFirstPage,
        icon: Icons.chat_bubble_outline,
      );
    }

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFF5B400),
        foregroundColor: Colors.black87,
        onPressed: () {},
        child: const Icon(Icons.edit_outlined),
      ),
      body: Column(
        children: [
          // Barre de recherche
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchController,
              onSubmitted: (value) async {
                _query = value;
                await _loadMessages(reset: true);
              },
              decoration: InputDecoration(
                hintText: "Rechercher conversation…",
                filled: true,
                fillColor: Colors.white,
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
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
          // Chips filtres
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
                  label: "Fournisseurs",
                  selected: _selectedFilter == 1,
                  onTap: () => setState(() => _selectedFilter = 1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: "Transitaires",
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
          // Liste des rooms / conversations
          if (_selectedRoomId != null)
            Expanded(
              child: _buildConversationView(),
            )
          else
            Expanded(
              child: _buildRoomList(),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    return ListView.builder(
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        final selected = _selectedRoomId == room["id"];
        final initials = _roomInitials(room);
        final avatarColor = _roomAvatarColor(index);
        final unread = (room["unread_count"] ?? 0) as int;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: avatarColor,
            child: Text(
              initials,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  _roomLabel(room),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const Text(
                "Maintenant",
                style: TextStyle(
                    fontSize: 11, color: Color(0xFF9E9E9E)),
              ),
            ],
          ),
          subtitle: Row(
            children: [
              const Expanded(
                child: Text(
                  "Touchez pour ouvrir la conversation",
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF9E9E9E)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unread > 0)
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5484D),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      "$unread",
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
          selected: selected,
          selectedTileColor: AppPalette.primarySoft,
          onTap: () async {
            setState(() => _selectedRoomId = room["id"] as int?);
            await _loadMessages(reset: true);
          },
        );
      },
    );
  }

  Widget _buildConversationView() {
    return Column(
      children: [
        // Header room sélectionnée
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => setState(() => _selectedRoomId = null),
              ),
              Expanded(
                child: Text(
                  _rooms
                      .where((r) => r["id"] == _selectedRoomId)
                      .map((r) => _roomLabel(r))
                      .firstOrNull ?? "Discussion",
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadRoomsAndFirstPage,
              ),
            ],
          ),
        ),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final mine = _isMine(msg);
              final state = mine ? _myState(msg) : "";
              return Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment:
                        mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      constraints: const BoxConstraints(maxWidth: 320),
                      decoration: BoxDecoration(
                        color: mine
                            ? const Color(0xFFDCF8C6)
                            : Colors.white,
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
                      child: Text((msg["content"] ?? "").toString()),
                    ),
                  ),
                  if (mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        state.isEmpty ? "SENT" : state,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black54),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        // Barre d'envoi
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
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
                icon: const Icon(Icons.attach_file),
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                style: IconButton.styleFrom(
                  backgroundColor: AppPalette.primary,
                ),
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
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

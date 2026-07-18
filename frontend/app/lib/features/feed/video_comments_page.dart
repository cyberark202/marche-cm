import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideoCommentsSheet extends StatefulWidget {
  const VideoCommentsSheet({
    super.key,
    required this.productId,
    required this.initialCount,
  });

  final int productId;
  final int initialCount;

  @override
  State<VideoCommentsSheet> createState() => _VideoCommentsSheetState();
}

class _VideoCommentsSheetState extends State<VideoCommentsSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  final Map<int, List<Map<String, dynamic>>> _replies = {};
  bool _loading = true;
  bool _submitting = false;
  int _count = 0;
  Map<String, dynamic>? _replyingTo;
  List<String> _emojis = const [];

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount;
    _loadUiConfig();
    _loadComments();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _emojis = BackendUiConfigService.instance
            .readStringList(config, ["choices", "feed_comment_emojis"]);
      });
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    final token = context.read<SessionStore>().token;
    try {
      final rows = await _api.getList(
        "/api/video-comments/?product_id=${widget.productId}",
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadReplies(int commentId) async {
    final token = context.read<SessionStore>().token;
    try {
      final rows = await _api.getList(
        "/api/video-comments/?parent_id=$commentId",
        token: token,
      );
      if (!mounted) return;
      setState(() => _replies[commentId] = rows);
    } catch (_) {}
  }

  Future<void> _submitComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final token = context.read<SessionStore>().token;
    final parent = _replyingTo;
    setState(() => _submitting = true);
    try {
      await _api.post(
        "/api/video-comments/",
        {
          "product": widget.productId,
          "message": text,
          if (parent != null) "parent": parent["id"],
        },
        token: token,
      );
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _count += 1;
        _replyingTo = null;
      });
      if (parent != null) {
        await _loadReplies(parent["id"] as int);
        await _loadComments();
      } else {
        await _loadComments();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Impossible d'envoyer le commentaire."))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _toggleCommentLike(Map<String, dynamic> comment,
      {int? parentId}) async {
    final id = comment["id"];
    if (id is! int) return;
    final token = context.read<SessionStore>().token;
    try {
      final result =
          await _api.post("/api/video-comments/$id/like/", {}, token: token);
      if (!mounted) return;
      final updated = {
        ...comment,
        "is_liked": result["liked"] == true,
        "likes_count": result["total_likes"] ?? 0,
      };
      setState(() {
        if (parentId == null) {
          _comments =
              _comments.map((c) => c["id"] == id ? updated : c).toList();
        } else {
          _replies[parentId] = (_replies[parentId] ?? [])
              .map((c) => c["id"] == id ? updated : c)
              .toList();
        }
      });
    } catch (_) {}
  }

  String _formatDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return "";
    final diff = DateTime.now().difference(parsed);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return "il y a ${diff.inMinutes} min";
    if (diff.inHours < 24) return "il y a ${diff.inHours} h";
    return "il y a ${diff.inDays} j";
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) Navigator.of(context).pop(_count);
            },
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "$_count commentaire${_count > 1 ? 's' : ''}",
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: () => Navigator.of(context).pop(_count),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _comments.isEmpty
                          ? const Center(
                              child: Text(
                                  "Aucun commentaire pour le moment."))
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _comments.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) =>
                                  _buildComment(_comments[index]),
                            ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: 12,
                      right: 12,
                      top: 8,
                      bottom:
                          MediaQuery.of(context).viewInsets.bottom + 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyingTo != null) _buildReplyBar(),
                        Row(
                          children: [
                            IconButton(
                              onPressed: () => _openEmojiPicker(context),
                              icon: const Icon(LucideIcons.smile),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                decoration: InputDecoration(
                                  hintText: _replyingTo == null
                                      ? "Ajoutez votre commentaire..."
                                      : "Votre réponse...",
                                  filled: true,
                                  fillColor: const Color(0xFFFFF7ED),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(999),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed:
                                  _submitting ? null : _submitComment,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(LucideIcons.send),
                            )
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyBar() {
    final author = (_replyingTo?["author"] ?? "").toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              "Réponse à @$author",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _replyingTo = null),
            child: const Icon(LucideIcons.x, size: 15, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  Widget _buildComment(Map<String, dynamic> comment, {int? parentId}) {
    final id = comment["id"];
    final author = (comment["author"] ?? "").toString();
    final isSeller = comment["is_seller"] == true;
    final likes = int.tryParse("${comment["likes_count"] ?? 0}") ?? 0;
    final liked = comment["is_liked"] == true;
    final repliesCount =
        int.tryParse("${comment["replies_count"] ?? 0}") ?? 0;
    final loadedReplies = id is int ? _replies[id] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          "@$author",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF9A3412)),
                        ),
                      ),
                      if (isSeller)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0C7C59),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            "Vendeur",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text((comment["message"] ?? "").toString()),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _formatDate((comment["created_at"] ?? "").toString()),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                      if (parentId == null) ...[
                        const SizedBox(width: 14),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _replyingTo = comment),
                          child: const Text(
                            "Répondre",
                            style: TextStyle(
                                color: Colors.black54,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _toggleCommentLike(comment, parentId: parentId),
              child: Column(
                children: [
                  Icon(
                    liked ? Icons.favorite : LucideIcons.heart,
                    size: 16,
                    color: liked ? const Color(0xFFFF3B5C) : Colors.black38,
                  ),
                  if (likes > 0)
                    Text("$likes",
                        style: const TextStyle(
                            fontSize: 11, color: Colors.black45)),
                ],
              ),
            ),
          ],
        ),
        if (parentId == null && repliesCount > 0 && loadedReplies == null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 6),
            child: GestureDetector(
              onTap: id is int ? () => _loadReplies(id) : null,
              child: Text(
                "— Voir les $repliesCount réponse${repliesCount > 1 ? 's' : ''}",
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        if (loadedReplies != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: loadedReplies
                  .map((reply) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildComment(reply, parentId: id as int),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }

  void _openEmojiPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("Émojis",
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _emojis
                    .map(
                      (emoji) => InkWell(
                        onTap: () {
                          _controller.text = "${_controller.text}$emoji";
                          _controller.selection = TextSelection.collapsed(
                              offset: _controller.text.length);
                          Navigator.pop(context);
                        },
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 28)),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

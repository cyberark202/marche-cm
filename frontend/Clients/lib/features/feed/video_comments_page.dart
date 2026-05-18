import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';
import 'feed_models.dart';

class VideoCommentsPage extends StatefulWidget {
  const VideoCommentsPage({super.key, required this.video});

  final VideoPostData video;

  @override
  State<VideoCommentsPage> createState() => _VideoCommentsPageState();
}

class _VideoCommentsPageState extends State<VideoCommentsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  List<CommentData> _remoteComments = [];
  bool _loadingComments = true;
  bool _submitting = false;
  List<String> _emojis = const [];
  List<String> _stickers = const [];

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _loadComments();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _emojis = BackendUiConfigService.instance
            .readStringList(config, ["choices", "feed_comment_emojis"]);
        _stickers = BackendUiConfigService.instance
            .readStringList(config, ["choices", "feed_comment_stickers"]);
      });
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    final token = context.read<SessionStore>().token;
    try {
      final rows = await _api.getList(
        "/api/video-comments/?product_id=${widget.video.id}",
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _remoteComments = rows
            .map((row) => CommentData(
                  author: (row["author"] ?? "").toString(),
                  message: (row["message"] ?? "").toString(),
                  timeLabel: _formatDate((row["created_at"] ?? "").toString()),
                ))
            .toList();
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
    }
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comments = [..._remoteComments, ...widget.video.comments];
    return Scaffold(
      appBar: AppBar(title: const Text("Commentaires récents")),
      body: Column(
        children: [
          Expanded(
            child: _loadingComments
                ? const Center(child: CircularProgressIndicator())
                : comments.isEmpty
                    ? const Center(child: Text("Aucun commentaire pour le moment."))
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: comments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFFFEDD5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "@${comment.author}",
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF9A3412)),
                                ),
                                const SizedBox(height: 4),
                                Text(comment.message),
                                const SizedBox(height: 4),
                                Text(comment.timeLabel, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _openEmojiPicker(context),
                    icon: const Icon(Icons.emoji_emotions_outlined),
                  ),
                  IconButton(
                    onPressed: () => _openStickerPicker(context),
                    icon: const Icon(Icons.celebration_outlined),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: "Ajoutez votre commentaire...",
                        filled: true,
                        fillColor: const Color(0xFFFFF7ED),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(999),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _submitting ? null : _submitComment,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Future<void> _submitComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final token = context.read<SessionStore>().token;
    setState(() => _submitting = true);
    try {
      await _api.post(
        "/api/video-comments/",
        {"product": widget.video.id, "message": text},
        token: token,
      );
      _controller.clear();
      await _loadComments();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e, fallback: "Impossible d'envoyer le commentaire."))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openEmojiPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("Émojis", style: TextStyle(fontWeight: FontWeight.w700)),
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
                          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
                          Navigator.pop(context);
                        },
                        child: Text(emoji, style: const TextStyle(fontSize: 28)),
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

  void _openStickerPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) {
        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.all(12),
          itemCount: _stickers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) {
            final sticker = _stickers[index];
            return ListTile(
              tileColor: const Color(0xFFFFF7ED),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: const Icon(Icons.sticky_note_2_outlined),
              title: Text(sticker),
              onTap: () {
                _controller.text = "${_controller.text}$sticker ";
                _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';
import '../feed/feed_api_service.dart';
import '../feed/feed_models.dart';
import '../feed/video_comments_page.dart';
import '../feed/video_post_player.dart';

class VideosTab extends StatefulWidget {
  const VideosTab({super.key});

  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  final FeedApiService _feedApi = FeedApiService();
  final ApiService _api = ApiService();
  List<VideoPostData> _videos = const [];
  bool _loading = true;
  String? _error;
  int _currentPage = 0;
  final Set<int> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final payload = await _feedApi.loadFeed(token: token);
      if (!mounted) return;
      setState(() {
        _videos = payload.videos;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Impossible de charger les vidéos.";
        _loading = false;
      });
    }
  }

  Future<void> _toggleLike(VideoPostData video) async {
    final token = context.read<SessionStore>().token;
    final alreadyLiked = _likedIds.contains(video.id);
    setState(() {
      if (alreadyLiked) {
        _likedIds.remove(video.id);
      } else {
        _likedIds.add(video.id);
      }
    });
    try {
      await _api.post(
          "/api/video-likes/toggle/", {"product_id": video.id}, token: token);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (alreadyLiked) {
          _likedIds.add(video.id);
        } else {
          _likedIds.remove(video.id);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white54, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text("Réessayer")),
            ],
          ),
        ),
      );
    }
    if (_videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text("Aucune vidéo pour le moment.",
              style: TextStyle(color: Colors.white70)),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _videos.length,
        onPageChanged: (i) => setState(() => _currentPage = i),
        itemBuilder: (context, index) {
          final video = _videos[index];
          return _VideoPage(
            video: video,
            isActive: index == _currentPage,
            isLiked: _likedIds.contains(video.id),
            onLike: () => _toggleLike(video),
            onComment: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => VideoCommentsPage(video: video)),
            ),
          );
        },
      ),
    );
  }
}

class _VideoPage extends StatelessWidget {
  const _VideoPage({
    required this.video,
    required this.isActive,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
  });

  final VideoPostData video;
  final bool isActive;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (video.videoUrl != null &&
            video.videoUrl!.isNotEmpty &&
            isActive)
          VideoPostPlayer(
              videoUrl: video.videoUrl!, coverUrl: video.coverUrl)
        else
          _CoverBg(coverUrl: video.coverUrl),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xCC000000)],
                stops: [0.45, 1.0],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 80,
          bottom: 90,
          child: _PostInfo(video: video),
        ),
        Positioned(
          right: 12,
          bottom: 110,
          child: _ActionBar(
            video: video,
            isLiked: isLiked,
            onLike: onLike,
            onComment: onComment,
          ),
        ),
      ],
    );
  }
}

class _CoverBg extends StatelessWidget {
  const _CoverBg({required this.coverUrl});

  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    if (coverUrl.isEmpty) {
      return const ColoredBox(color: Color(0xFF0C1A12));
    }
    return CachedNetworkImage(
      imageUrl: coverUrl,
      fit: BoxFit.cover,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF0C1A12)),
    );
  }
}

class _PostInfo extends StatelessWidget {
  const _PostInfo({required this.video});

  final VideoPostData video;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: video.publisherAvatar.isNotEmpty
                  ? NetworkImage(video.publisherAvatar)
                  : null,
              backgroundColor: const Color(0xFF0C7C59),
              child: video.publisherAvatar.isEmpty
                  ? const Icon(Icons.person, color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              video.publisherName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ],
        ),
        if (video.description.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            video.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.video,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
  });

  final VideoPostData video;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          color: isLiked ? Colors.red : Colors.white,
          label: (video.likes + (isLiked ? 1 : 0)).toString(),
          onTap: onLike,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.chat_bubble_outline,
          label: video.comments.length.toString(),
          onTap: onComment,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: Icons.share_outlined,
          label: "",
          onTap: () {},
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

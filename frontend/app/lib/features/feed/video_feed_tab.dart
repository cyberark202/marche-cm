import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../feed/feed_models.dart';
import '../feed/video_comments_page.dart';
import '../feed/video_post_player.dart';
import '../feed/video_publish_page.dart';

class VideoFeedTab extends StatefulWidget {
  const VideoFeedTab({super.key});

  @override
  State<VideoFeedTab> createState() => _VideoFeedTabState();
}

class _VideoFeedTabState extends State<VideoFeedTab> {
  final _api = ApiService();
  final _pageController = PageController();

  List<Map<String, dynamic>> _posts = const [];
  bool _loading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _pageController.addListener(_onPageChange);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChange() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentIndex) {
      setState(() => _currentIndex = page);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      // Try the feed endpoint first; fallback to products with video
      List<Map<String, dynamic>> rows = const [];
      try {
        rows = await _api.getList(
          '/api/products/?has_video=true&page_size=20',
          token: token,
        );
      } catch (_) {
        rows = await _api.getList(
          '/api/products/?page_size=20',
          token: token,
        );
      }
      if (!mounted) return;
      // Keep only posts that have a video URL
      final withVideo = rows
          .where((r) =>
              (r['video_url'] ?? r['video'] ?? '').toString().isNotEmpty)
          .toList();
      setState(() {
        _posts = withVideo.isNotEmpty ? withVideo : rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(
            'Vidéos',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const VideoPublishPage()),
              ),
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const _LoadingView()
            : _posts.isEmpty
                ? _EmptyFeedView(onPublish: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const VideoPublishPage()),
                    );
                  })
                : PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    itemCount: _posts.length,
                    itemBuilder: (context, index) {
                      return _VideoPage(
                        post: _posts[index],
                        isActive: index == _currentIndex,
                        pageIndex: index,
                        totalPages: _posts.length,
                      );
                    },
                  ),
      ),
    );
  }
}

// ─── Individual Video Page ────────────────────────────────────────────────────

class _VideoPage extends StatelessWidget {
  const _VideoPage({
    required this.post,
    required this.isActive,
    required this.pageIndex,
    required this.totalPages,
  });

  final Map<String, dynamic> post;
  final bool isActive;
  final int pageIndex;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final videoUrl = (post['video_url'] ?? post['video'] ?? '').toString();
    final coverUrl = (post['image'] ?? '').toString();
    final title = (post['title'] ?? post['name'] ?? '').toString();
    final description = (post['description'] ?? '').toString();
    final supplier = (post['seller_username'] ?? '').toString();
    final price = (post['price_for_min_qty'] ?? '').toString();
    final isVerified = post['seller_is_verified'] == true;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video / cover background
        if (videoUrl.isNotEmpty && isActive)
          VideoPostPlayer(
            videoUrl: _fullUrl(videoUrl),
            coverUrl: coverUrl.isNotEmpty ? _fullUrl(coverUrl) : '',
          )
        else
          _CoverBackground(imageUrl: coverUrl),

        // Gradient overlay bottom
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0, 0.4, 0.7, 1],
              ),
            ),
          ),
        ),

        // Right action bar
        Positioned(
          right: 12,
          bottom: 120,
          child: _ActionBar(post: post),
        ),

        // Bottom info
        Positioned(
          left: 16,
          right: 72,
          bottom: 100,
          child: _PostInfo(
            title: title,
            description: description,
            supplier: supplier,
            price: price,
            isVerified: isVerified,
          ),
        ),

        // Page indicator
        Positioned(
          right: 16,
          top: MediaQuery.of(context).padding.top + 64,
          child: _PageIndicator(
            current: pageIndex,
            total: totalPages,
          ),
        ),
      ],
    );
  }

  String _fullUrl(String path) {
    if (path.startsWith('http')) return path;
    return '${AppConfig.apiBaseUrl}$path';
  }
}

class _CoverBackground extends StatelessWidget {
  const _CoverBackground({required this.imageUrl});
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: Icon(Icons.play_circle_outline_rounded,
              color: Colors.white38, size: 72),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl.startsWith('http')
          ? imageUrl
          : '${AppConfig.apiBaseUrl}$imageUrl',
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      ),
      errorWidget: (_, __, ___) => Container(
        color: const Color(0xFF0F172A),
        child: const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white38, size: 64),
        ),
      ),
    );
  }
}

class _ActionBar extends StatefulWidget {
  const _ActionBar({required this.post});
  final Map<String, dynamic> post;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  final _api = ApiService();
  bool _liked = false;
  int _likes = 0;
  bool _likeLoading = false;

  @override
  void initState() {
    super.initState();
    final raw = widget.post['likes_count'] ?? widget.post['likes'] ?? 0;
    _likes = raw is int ? raw : int.tryParse('$raw') ?? 0;
    _liked = widget.post['is_liked_by_me'] == true;
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;
    final id = widget.post['id'];
    if (id == null) return;
    setState(() => _likeLoading = true);
    // Optimistic update
    setState(() {
      _liked = !_liked;
      _likes += _liked ? 1 : -1;
    });
    try {
      final token = context.read<SessionStore>().token;
      final result = await _api.post(
        '/api/video-likes/toggle/',
        {'product_id': id},
        token: token,
      );
      if (!mounted) return;
      final total = result['total_likes'];
      setState(() {
        _liked = result['liked'] == true;
        _likes = total is int ? total : int.tryParse('$total') ?? _likes;
      });
    } catch (_) {
      // Revert optimistic update on failure
      if (mounted) {
        setState(() {
          _liked = !_liked;
          _likes += _liked ? 1 : -1;
        });
      }
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  void _openComments(BuildContext context) {
    final id = widget.post['id'];
    final productId = id is int ? id : int.tryParse('$id') ?? 0;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCommentsPage(
          video: VideoPostData(
            id: productId,
            coverUrl: (widget.post['image'] ?? '').toString(),
            publisherName: (widget.post['seller_username'] ?? '').toString(),
            publisherAvatar: '',
            description: (widget.post['description'] ?? '').toString(),
            likes: _likes,
            comments: const [],
            sellerId: () {
              final s = widget.post['seller'] ?? widget.post['supplier_id'] ?? 0;
              return s is int ? s : int.tryParse('$s') ?? 0;
            }(),
            videoUrl: (widget.post['video_url'] ?? widget.post['video'] ?? '')
                .toString(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionItem(
          icon: _liked
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          label: _likes > 0 ? '$_likes' : '',
          color: _liked ? Colors.red : Colors.white,
          onTap: _toggleLike,
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: Icons.chat_bubble_outline_rounded,
          label: '',
          color: Colors.white,
          onTap: () => _openComments(context),
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: Icons.share_rounded,
          label: '',
          color: Colors.white,
          onTap: () {},
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: Icons.bookmark_border_rounded,
          label: '',
          color: Colors.white,
          onTap: () {},
        ),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostInfo extends StatelessWidget {
  const _PostInfo({
    required this.title,
    required this.description,
    required this.supplier,
    required this.price,
    required this.isVerified,
  });

  final String title;
  final String description;
  final String supplier;
  final String price;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 8, color: Colors.black54)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (supplier.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '@$supplier',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  shadows: shadow,
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified_rounded,
                    color: Colors.lightBlueAccent, size: 14),
              ],
            ],
          ),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.3,
              shadows: shadow,
            ),
          ),
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
              height: 1.4,
              shadows: shadow,
            ),
          ),
        ],
        if (price.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppPalette.primary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              '$price FCFA',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    if (total <= 1) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        '${current + 1} / $total',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─── States ───────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Chargement du fil…',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeedView extends StatelessWidget {
  const _EmptyFeedView({required this.onPublish});
  final VoidCallback onPublish;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_off_rounded,
                  color: Colors.white54, size: 38),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aucune vidéo disponible',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Publiez votre première vidéo produit pour la faire apparaître ici.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 13.5,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPublish,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Publier une vidéo'),
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

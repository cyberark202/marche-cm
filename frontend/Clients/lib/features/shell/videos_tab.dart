import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';
import '../feed/feed_api_service.dart';
import '../feed/feed_models.dart';
import '../feed/product_publication_detail_page.dart';
import '../feed/video_comments_page.dart';
import '../feed/video_post_player.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideosTab extends StatefulWidget {
  const VideosTab({super.key, this.active = false});

  /// `true` uniquement quand l'onglet Vidéos est celui affiché par le shell.
  /// Tant qu'il est `false`, on ne charge NI le feed NI aucune vidéo : le
  /// réseau/lecteur ne démarre qu'à la première entrée dans l'écran.
  final bool active;

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
  // Vrai dès la première activation de l'onglet : évite tout chargement tant
  // que l'utilisateur n'est pas entré dans l'écran vidéo.
  bool _loadStarted = false;
  // États utilisateur mutables, initialisés depuis le serveur au chargement.
  final Map<int, bool> _liked = {};
  final Map<int, int> _likeCounts = {};
  final Map<int, int> _commentCounts = {};
  final Map<int, bool> _followingSeller = {};
  // Vue comptée une seule fois par vidéo et par session de feed.
  final Set<int> _viewedIds = {};
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
    // Nouvelle vidéo publiée par un vendeur : ne rafraîchir en direct que si
    // l'acheteur est encore sur la 1re vidéo, pour ne jamais couper une
    // lecture en cours plus bas dans le feed.
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted || !_loadStarted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'products') &&
          _currentPage == 0) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideosTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chargement paresseux : on ne déclenche le feed qu'à la première fois où
    // l'onglet devient réellement visible.
    if (widget.active && !_loadStarted) {
      _load();
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadStarted = true;
      _loading = _videos.isEmpty;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final payload = await _feedApi.loadFeed(token: token);
      if (!mounted) return;
      setState(() {
        _videos = payload.videos;
        // Hydratation des états serveur (le toggle local prend le relais).
        for (final video in payload.videos) {
          _liked[video.id] = video.isLiked;
          _likeCounts[video.id] = video.likes;
          _commentCounts[video.id] = video.commentsCount;
          _followingSeller[video.sellerId] =
              _followingSeller[video.sellerId] ?? video.isFollowingSeller;
        }
        _loading = false;
      });
      if (payload.videos.isNotEmpty) {
        _trackView(payload.videos.first.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Impossible de charger les vidéos.";
        _loading = false;
      });
    }
  }

  /// Comptage de vue serveur (déduplication par session ; alimente aussi les
  /// recommandations).
  void _trackView(int productId) {
    if (!_viewedIds.add(productId)) return;
    final token = context.read<SessionStore>().token;
    _feedApi.trackProductView(productId: productId, token: token);
  }

  Future<void> _toggleLike(VideoPostData video, {bool onlyLike = false}) async {
    final alreadyLiked = _liked[video.id] ?? false;
    // Double-tap façon TikTok : ne retire jamais un like existant.
    if (onlyLike && alreadyLiked) return;
    final token = context.read<SessionStore>().token;
    setState(() {
      _liked[video.id] = !alreadyLiked;
      _likeCounts[video.id] =
          (_likeCounts[video.id] ?? 0) + (alreadyLiked ? -1 : 1);
    });
    try {
      final result = await _api.post(
          "/api/video-likes/toggle/", {"product_id": video.id}, token: token);
      if (!mounted) return;
      setState(() {
        _liked[video.id] = result["liked"] == true;
        _likeCounts[video.id] =
            int.tryParse("${result["total_likes"] ?? ""}") ??
                _likeCounts[video.id] ??
                0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked[video.id] = alreadyLiked;
        _likeCounts[video.id] =
            (_likeCounts[video.id] ?? 0) + (alreadyLiked ? 1 : -1);
      });
    }
  }

  Future<void> _toggleFollow(VideoPostData video) async {
    final myId = context.read<SessionStore>().userId;
    if (myId != null && myId == video.sellerId) return;
    final wasFollowing = _followingSeller[video.sellerId] ?? false;
    final token = context.read<SessionStore>().token;
    setState(() => _followingSeller[video.sellerId] = !wasFollowing);
    try {
      final result = await _api.post("/api/seller-follows/toggle/",
          {"seller_id": video.sellerId}, token: token);
      if (!mounted) return;
      setState(() =>
          _followingSeller[video.sellerId] = result["following"] == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _followingSeller[video.sellerId] = wasFollowing);
    }
  }

  /// Partage WhatsApp (canal dominant au Cameroun) avec repli presse-papier —
  /// même pattern que le partage produit.
  Future<void> _shareVideo(VideoPostData video) async {
    final p = video.product;
    final message = "${p.title} — ${p.priceMin} FCFA sur Market CM.\n"
        "Téléchargez l'application : ${AppConfig.siteUrl}";
    await Clipboard.setData(ClipboardData(text: message));
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse("https://wa.me/?text=${Uri.encodeComponent(message)}"),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lien copié dans le presse-papier.")),
      );
    }
  }

  void _openProduct(VideoPostData video) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductPublicationDetailPage(product: video.product),
      ),
    );
  }

  /// Commentaires en bottom sheet (la vidéo continue derrière, façon TikTok).
  Future<void> _openComments(VideoPostData video) async {
    final newCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoCommentsSheet(
        video: video,
        initialCount: _commentCounts[video.id] ?? video.commentsCount,
      ),
    );
    if (newCount != null && mounted) {
      setState(() => _commentCounts[video.id] = newCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Onglet jamais ouvert : écran noir, aucun réseau, aucune vidéo.
    if (!_loadStarted) {
      return const Scaffold(
          backgroundColor: Colors.black, body: SizedBox.shrink());
    }
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
              const Icon(LucideIcons.alertCircle,
                  color: Colors.white54, size: 48),
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
      body: RefreshIndicator(
        onRefresh: _load,
        edgeOffset: 40,
        child: PageView.builder(
          scrollDirection: Axis.vertical,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: _videos.length,
          onPageChanged: (i) {
            setState(() => _currentPage = i);
            _trackView(_videos[i].id);
          },
          itemBuilder: (context, index) {
            final video = _videos[index];
            // Préchargement TikTok : la page active joue, les voisines (±1)
            // initialisent leur player en pause — swipe instantané.
            final nearActive = (index - _currentPage).abs() <= 1;
            return _VideoPage(
              video: video,
              mountPlayer: nearActive,
              isActive: widget.active && index == _currentPage,
              isLiked: _liked[video.id] ?? false,
              likeCount: _likeCounts[video.id] ?? video.likes,
              commentCount: _commentCounts[video.id] ?? video.commentsCount,
              viewCount: video.views,
              isFollowing: _followingSeller[video.sellerId] ?? false,
              onLike: () => _toggleLike(video),
              onDoubleTapLike: () => _toggleLike(video, onlyLike: true),
              onComment: () => _openComments(video),
              onShare: () => _shareVideo(video),
              onFollow: () => _toggleFollow(video),
              onOpenProduct: () => _openProduct(video),
            );
          },
        ),
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.video,
    required this.mountPlayer,
    required this.isActive,
    required this.isLiked,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.isFollowing,
    required this.onLike,
    required this.onDoubleTapLike,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onOpenProduct,
  });

  final VideoPostData video;
  final bool mountPlayer;
  final bool isActive;
  final bool isLiked;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final bool isFollowing;
  final VoidCallback onLike;
  final VoidCallback onDoubleTapLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onOpenProduct;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  bool _showHeart = false;
  Timer? _heartTimer;

  @override
  void dispose() {
    _heartTimer?.cancel();
    super.dispose();
  }

  void _onDoubleTap() {
    widget.onDoubleTapLike();
    _heartTimer?.cancel();
    setState(() => _showHeart = true);
    _heartTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final hasVideo = video.videoUrl != null && video.videoUrl!.isNotEmpty;
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasVideo && widget.mountPlayer)
            VideoPostPlayer(
              videoUrl: video.videoUrl!,
              coverUrl: video.coverUrl,
              isActive: widget.isActive,
            )
          else
            _CoverBg(coverUrl: video.coverUrl),
          const Positioned.fill(
            child: IgnorePointer(
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
          ),
          // Cœur du double-tap like.
          IgnorePointer(
            child: Center(
              child: AnimatedScale(
                scale: _showHeart ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: _showHeart ? 1 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(Icons.favorite,
                      color: Color(0xFFFF3B5C), size: 110),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 80,
            bottom: 90,
            child: _PostInfo(
              video: video,
              isFollowing: widget.isFollowing,
              onFollow: widget.onFollow,
              onOpenProduct: widget.onOpenProduct,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 110,
            child: _ActionBar(
              isLiked: widget.isLiked,
              likeCount: widget.likeCount,
              commentCount: widget.commentCount,
              viewCount: widget.viewCount,
              onLike: widget.onLike,
              onComment: widget.onComment,
              onShare: widget.onShare,
            ),
          ),
        ],
      ),
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
  const _PostInfo({
    required this.video,
    required this.isFollowing,
    required this.onFollow,
    required this.onOpenProduct,
  });

  final VideoPostData video;
  final bool isFollowing;
  final VoidCallback onFollow;
  final VoidCallback onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final price = video.product.priceMin;
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
                  ? const Icon(LucideIcons.user, color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                video.publisherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Follow inline : suivre le vendeur sans quitter la vidéo.
            GestureDetector(
              onTap: onFollow,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isFollowing
                      ? Colors.white24
                      : const Color(0xFFFF3B5C),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isFollowing ? "Abonné" : "Suivre",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
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
        const SizedBox(height: 8),
        // Fiche produit ancrée (pattern TikTok Shop) : tap → fiche + achat.
        GestureDetector(
          onTap: onOpenProduct,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xE6FFFFFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(LucideIcons.shoppingCart,
                    size: 16, color: Color(0xFFEA580C)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    video.product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87),
                  ),
                ),
                if (price > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    "$price FCFA",
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0C7C59)),
                  ),
                ],
                const SizedBox(width: 4),
                const Icon(LucideIcons.chevronRight,
                    size: 14, color: Colors.black45),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.isLiked,
    required this.likeCount,
    required this.commentCount,
    required this.viewCount,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  final bool isLiked;
  final int likeCount;
  final int commentCount;
  final int viewCount;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  /// Compteur abrégé façon TikTok (1,2 k / 3,4 M).
  static String compact(int value) {
    if (value >= 1000000) {
      return "${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')} M";
    }
    if (value >= 1000) {
      return "${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')} k";
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionButton(
          icon: LucideIcons.heart,
          color: isLiked ? const Color(0xFFFF3B5C) : Colors.white,
          label: compact(likeCount),
          onTap: onLike,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: LucideIcons.messageCircle,
          label: compact(commentCount),
          onTap: onComment,
        ),
        const SizedBox(height: 20),
        _ActionButton(
          icon: LucideIcons.share2,
          label: "Partager",
          onTap: onShare,
        ),
        if (viewCount > 0) ...[
          const SizedBox(height: 20),
          Column(
            children: [
              const Icon(LucideIcons.eye, color: Colors.white70, size: 22),
              const SizedBox(height: 2),
              Text(compact(viewCount),
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ],
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

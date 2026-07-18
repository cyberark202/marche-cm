import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';
import '../feed/video_comments_page.dart';
import '../feed/video_post_player.dart';
import '../feed/video_publish_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideoFeedTab extends StatefulWidget {
  const VideoFeedTab({super.key, this.active = false});

  /// `true` uniquement quand l'onglet Vidéos est celui affiché par le shell.
  /// Tant qu'il est `false`, on ne charge NI le feed NI aucune vidéo : le
  /// réseau/lecteur ne démarre qu'à la première entrée dans l'écran.
  final bool active;

  @override
  State<VideoFeedTab> createState() => _VideoFeedTabState();
}

class _VideoFeedTabState extends State<VideoFeedTab> {
  final _api = ApiService();
  final _pageController = PageController();

  List<Map<String, dynamic>> _posts = const [];
  bool _loading = true;
  String? _error;
  // Vrai dès la première activation de l'onglet : rien ne se charge avant.
  bool _loadStarted = false;
  int _currentIndex = 0;
  // Vue comptée une seule fois par vidéo et par session de feed.
  final Set<int> _viewedIds = {};
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    if (widget.active) _load();
    _pageController.addListener(_onPageChange);
    // Nouvelle vidéo publiée par un autre vendeur : ne rafraîchir en direct
    // que si l'utilisateur est encore sur la 1re vidéo, pour ne jamais
    // couper une lecture en cours plus bas dans le feed.
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted || !_loadStarted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'products') &&
          _currentIndex == 0) {
        _load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant VideoFeedTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_loadStarted) {
      _load();
    }
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChange() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentIndex) {
      setState(() => _currentIndex = page);
      if (page >= 0 && page < _posts.length) _trackView(_posts[page]);
    }
  }

  /// Comptage de vue serveur (déduplication par session ; alimente aussi les
  /// recommandations).
  void _trackView(Map<String, dynamic> post) {
    final id = post['id'];
    final productId = id is int ? id : int.tryParse('$id');
    if (productId == null || !_viewedIds.add(productId)) return;
    final token = context.read<SessionStore>().token;
    _api
        .post('/api/products/track-view/', {'product_id': productId},
            token: token)
        .catchError((_) => <String, dynamic>{});
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loadStarted = true;
      _loading = _posts.isEmpty;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      // Le filtre ?has_video=true est appliqué côté serveur (les produits sans
      // vidéo n'entrent jamais dans le feed).
      final rows = await _api.getList(
        '/api/products/?has_video=true',
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _posts = rows;
        _loading = false;
      });
      if (rows.isNotEmpty) _trackView(rows.first);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Impossible de charger les vidéos.';
        });
      }
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
                  LucideIcons.plus,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: !_loadStarted
            ? const SizedBox.shrink()
            : _loading
            ? const _LoadingView()
            : _error != null
                ? _ErrorView(message: _error!, onRetry: _load)
                : _posts.isEmpty
                    ? _EmptyFeedView(onPublish: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const VideoPublishPage()),
                        );
                      })
                    : RefreshIndicator(
                        onRefresh: _load,
                        edgeOffset: 90,
                        child: PageView.builder(
                          controller: _pageController,
                          scrollDirection: Axis.vertical,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: _posts.length,
                          itemBuilder: (context, index) {
                            return _VideoPage(
                              post: _posts[index],
                              // Préchargement TikTok : la page active joue, les
                              // voisines (±1) initialisent leur player en pause.
                              mountPlayer:
                                  (index - _currentIndex).abs() <= 1,
                              isActive:
                                  widget.active && index == _currentIndex,
                              pageIndex: index,
                              totalPages: _posts.length,
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

// ─── Individual Video Page ────────────────────────────────────────────────────

class _VideoPage extends StatefulWidget {
  const _VideoPage({
    required this.post,
    required this.mountPlayer,
    required this.isActive,
    required this.pageIndex,
    required this.totalPages,
  });

  final Map<String, dynamic> post;
  final bool mountPlayer;
  final bool isActive;
  final int pageIndex;
  final int totalPages;

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  // Cle vers l'ActionBar pour declencher le like au double-tap sur la video.
  final GlobalKey<_ActionBarState> _actionBarKey = GlobalKey<_ActionBarState>();
  // Coeur anime du double-tap like.
  bool _showHeart = false;
  Timer? _heartTimer;

  @override
  void dispose() {
    _heartTimer?.cancel();
    super.dispose();
  }

  void _onDoubleTap() {
    _actionBarKey.currentState?.likeViaDoubleTap();
    _heartTimer?.cancel();
    setState(() => _showHeart = true);
    _heartTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final isActive = widget.isActive;
    final pageIndex = widget.pageIndex;
    final totalPages = widget.totalPages;
    final videoUrl = (post['video_url'] ?? post['video'] ?? '').toString();
    final poster = (post['video_poster'] ?? '').toString();
    final coverUrl =
        poster.isNotEmpty ? poster : (post['image'] ?? '').toString();
    final title = (post['title'] ?? post['name'] ?? '').toString();
    final description = (post['description'] ?? '').toString();
    final supplier = (post['seller_username'] ?? '').toString();
    final price = (post['price_for_min_qty'] ?? '').toString();
    final isVerified = post['seller_is_verified'] == true;

    return GestureDetector(
      // Double-tap n'importe ou sur la video -> like (facon TikTok).
      onDoubleTap: _onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
        // Video / cover background. Le player est monté pour la page active ET
        // ses voisines (préchargement ±1, en pause) ; au-delà, cover statique.
        if (videoUrl.isNotEmpty && widget.mountPlayer)
          VideoPostPlayer(
            videoUrl: _fullUrl(videoUrl),
            coverUrl: coverUrl.isNotEmpty ? _fullUrl(coverUrl) : '',
            isActive: isActive,
          )
        else
          _CoverBackground(imageUrl: coverUrl),

        // Coeur du double-tap like.
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
          child: _ActionBar(key: _actionBarKey, post: post),
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
      ),
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
          child: Icon(LucideIcons.playCircle,
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
          child: Icon(LucideIcons.imageOff,
              color: Colors.white38, size: 64),
        ),
      ),
    );
  }
}

class _ActionBar extends StatefulWidget {
  const _ActionBar({super.key, required this.post});
  final Map<String, dynamic> post;

  @override
  State<_ActionBar> createState() => _ActionBarState();
}

class _ActionBarState extends State<_ActionBar> {
  final _api = ApiService();
  bool _liked = false;
  int _likes = 0;
  bool _likeLoading = false;
  int _comments = 0;
  int _views = 0;
  bool _bookmarked = false;
  bool _bookmarkLoading = false;
  bool _following = false;
  bool _followLoading = false;

  int _toInt(dynamic raw) => raw is int ? raw : int.tryParse('$raw') ?? 0;

  @override
  void initState() {
    super.initState();
    // Hydratation depuis les annotations serveur du feed : compteurs réels et
    // états « déjà liké / abonné / favori » persistants entre sessions.
    _likes = _toInt(widget.post['video_likes_count'] ?? widget.post['likes_count'] ?? 0);
    _liked = widget.post['is_video_liked'] == true ||
        widget.post['is_liked_by_me'] == true;
    _comments = _toInt(widget.post['video_comments_count'] ?? 0);
    _views = _toInt(widget.post['video_views_count'] ?? 0);
    _bookmarked = widget.post['is_favorited'] == true;
    _following = widget.post['is_following_seller'] == true;
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

  /// Double-tap sur la video : like (jamais unlike), facon TikTok.
  void likeViaDoubleTap() {
    if (!_liked) _toggleLike();
  }

  Future<void> _toggleBookmark() async {
    if (_bookmarkLoading) return;
    final id = widget.post['id'];
    if (id == null) return;
    setState(() {
      _bookmarkLoading = true;
      _bookmarked = !_bookmarked;
    });
    try {
      final token = context.read<SessionStore>().token;
      final result = await _api.post(
        '/api/product-favorites/toggle/',
        {'product_id': id},
        token: token,
      );
      if (!mounted) return;
      setState(() => _bookmarked = result['favorited'] == true);
    } catch (_) {
      if (mounted) setState(() => _bookmarked = !_bookmarked);
    } finally {
      if (mounted) setState(() => _bookmarkLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followLoading) return;
    final id = widget.post['id'];
    if (id == null) return;
    setState(() {
      _followLoading = true;
      _following = !_following;
    });
    try {
      final token = context.read<SessionStore>().token;
      final result = await _api.post(
        '/api/seller-follows/toggle/',
        {'product_id': id},
        token: token,
      );
      if (!mounted) return;
      setState(() => _following = result['following'] == true);
    } catch (_) {
      if (mounted) setState(() => _following = !_following);
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  /// Partage WhatsApp (canal dominant au Cameroun) avec repli presse-papier —
  /// même pattern que le partage produit de l'app Clients.
  Future<void> _share() async {
    final title = (widget.post['title'] ?? widget.post['name'] ?? 'Produit').toString();
    final ref = (widget.post['reference_code'] ?? '').toString();
    final link =
        '${AppConfig.apiBaseUrl}/produits/${ref.isNotEmpty ? ref : widget.post['id']}';
    final message = '$title sur Market CM\n$link';
    await Clipboard.setData(ClipboardData(text: message));
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien copié dans le presse-papiers')),
      );
    }
  }

  /// Commentaires en bottom sheet (la vidéo continue derrière, façon TikTok).
  Future<void> _openComments(BuildContext context) async {
    final id = widget.post['id'];
    final productId = id is int ? id : int.tryParse('$id') ?? 0;
    final newCount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoCommentsSheet(
        productId: productId,
        initialCount: _comments,
      ),
    );
    if (newCount != null && mounted) {
      setState(() => _comments = newCount);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionItem(
          icon: LucideIcons.heart,
          label: _likes > 0 ? '$_likes' : '',
          color: _liked ? Colors.red : Colors.white,
          onTap: _toggleLike,
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: LucideIcons.messageCircle,
          label: _comments > 0 ? '$_comments' : '',
          color: Colors.white,
          onTap: () => _openComments(context),
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: LucideIcons.share2,
          label: '',
          color: Colors.white,
          onTap: _share,
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: LucideIcons.bookmark,
          label: '',
          color: _bookmarked ? AppPalette.primary : Colors.white,
          onTap: _toggleBookmark,
        ),
        const SizedBox(height: 18),
        _ActionItem(
          icon: _following
              ? LucideIcons.user
              : LucideIcons.userPlus,
          label: _following ? 'Abonne' : 'Suivre',
          color: _following ? AppPalette.primary : Colors.white,
          onTap: _toggleFollow,
        ),
        if (_views > 0) ...[
          const SizedBox(height: 18),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.eye, color: Colors.white70, size: 22),
              const SizedBox(height: 2),
              Text(
                '$_views',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black45)],
                ),
              ),
            ],
          ),
        ],
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
                const Icon(LucideIcons.badgeCheck,
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

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.alertCircle, color: Colors.white54, size: 48),
          const SizedBox(height: 12),
          Text(message,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Réessayer'),
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
              child: const Icon(LucideIcons.videoOff,
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
              icon: const Icon(LucideIcons.plus),
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

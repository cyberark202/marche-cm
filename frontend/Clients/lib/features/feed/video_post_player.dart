import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/app_config.dart';
import 'package:lucide_icons/lucide_icons.dart';

class VideoPostPlayer extends StatefulWidget {
  const VideoPostPlayer({
    super.key,
    required this.videoUrl,
    required this.coverUrl,
    this.isActive = true,
  });

  final String videoUrl;
  final String coverUrl;

  /// `true` uniquement pour la page actuellement visible du feed. Les pages
  /// voisines sont initialisees (prechargement) mais NE jouent pas, ce qui
  /// evite plusieurs videos/audios simultanes (pattern « seul le courant joue »).
  final bool isActive;

  @override
  State<VideoPostPlayer> createState() => _VideoPostPlayerState();
}

class _VideoPostPlayerState extends State<VideoPostPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  ChewieController? _chewieController;
  bool _ready = false;
  bool _failed = false;
  // La video ne joue QUE si elle est a la fois la page active du feed,
  // physiquement a l'ecran (pas couverte par une route / un autre onglet
  // IndexedStack), et l'app au premier plan. Sinon -> pause (pas de lecture en
  // arriere-plan). Geres respectivement par isActive, VisibilityDetector et le
  // cycle de vie de l'app.
  bool _onScreen = true;
  bool _appResumed = true;
  // Sur le web, l'autoplay AVEC son est bloque par le navigateur tant qu'il n'y
  // a pas eu de geste utilisateur : la video resterait figee sur la 1re frame.
  // On demarre donc en muet sur le web (l'utilisateur peut reactiver le son),
  // ce qui autorise la lecture automatique. Sur mobile, autoplay sonore est OK.
  // Le choix mute/son PERSISTE pour toute la session de scroll (facon TikTok :
  // on ne re-coupe pas le son a chaque nouvelle video du feed).
  static bool _sessionMuted = kIsWeb;
  bool _muted = _sessionMuted;
  String? _errorText;
  // Position en cours de glissement sur la barre de seek (null = pas de drag).
  double? _dragProgress;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed != _appResumed) {
      _appResumed = resumed;
      _syncPlayback();
    }
  }

  /// Source unique de verite pour lecture/pause : on ne joue que si la video est
  /// active (page courante), a l'ecran ET l'app au premier plan.
  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final shouldPlay = widget.isActive && _onScreen && _appResumed;
    if (shouldPlay) {
      if (!controller.value.isPlaying) {
        controller.play();
      }
    } else {
      if (controller.value.isPlaying) {
        controller.pause();
      }
    }
  }

  Future<void> _init() async {
    try {
      final sourceUrl = _normalizedPlayableUrl(widget.videoUrl);
      if (sourceUrl.isEmpty) {
        throw Exception("URL video vide.");
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(sourceUrl));
      await controller.initialize();
      await controller.setVolume(_muted ? 0 : 1);
      await controller.setLooping(true);

      final chewieController = ChewieController(
        videoPlayerController: controller,
        // La lecture est pilotee par _syncPlayback (active + a l'ecran + app au
        // premier plan), pas par l'autoplay de Chewie.
        autoPlay: false,
        looping: true,
        showControls: false,
        showOptions: false,
      );

      if (!mounted) {
        chewieController.dispose();
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _chewieController = chewieController;
        _ready = true;
      });
      _syncPlayback();
    } catch (e) {
      // On NE masque plus l'erreur : la cause (codec non supporte, transport,
      // CORS, 403...) est exposee en debug pour diagnostiquer encodage/transport.
      debugPrint("VideoPostPlayer init failed: $e");
      if (mounted) {
        setState(() {
          _failed = true;
          _errorText = e.toString();
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant VideoPostPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _chewieController?.dispose();
      _controller?.dispose();
      _chewieController = null;
      _controller = null;
      _ready = false;
      _failed = false;
      _muted = _sessionMuted;
      _errorText = null;
      _init();
      return;
    }
    // Meme video, seul isActive a change : on joue/pause sans recreer le
    // controleur (pattern « seul le courant joue », sans rebuffering inutile).
    // La position est CONSERVEE : revenir sur la video reprend ou on s'etait
    // arrete (reprise TikTok), tant que le player voisin reste monte.
    if (oldWidget.isActive != widget.isActive) {
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chewieController?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // VisibilityDetector : des que la video sort de l'ecran (changement
    // d'onglet IndexedStack, route poussee par-dessus, scroll), on coupe la
    // lecture -> jamais d'audio/video en arriere-plan.
    return VisibilityDetector(
      key: Key("video-vis-${widget.videoUrl}"),
      onVisibilityChanged: (info) {
        if (!mounted) return;
        final onScreen = info.visibleFraction > 0.5;
        if (onScreen != _onScreen) {
          _onScreen = onScreen;
          _syncPlayback();
        }
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_failed) {
      // En debug, on superpose la cause de l'echec pour diagnostiquer
      // l'encodage/transport sans ouvrir la console.
      if (kDebugMode && (_errorText ?? "").isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildCover(),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xCCB91C1C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "Lecture impossible: $_errorText",
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        );
      }
      return _buildCover();
    }
    if (!_ready || _controller == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildCover(),
          const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        ],
      );
    }
    final controller = _controller!;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final duration = value.duration;
        final position = value.position > duration ? duration : value.position;
        final totalMs = duration.inMilliseconds;
        final progress =
            totalMs <= 0 ? 0.0 : position.inMilliseconds / totalMs.toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: Chewie(controller: _chewieController!),
              ),
            ),
            // Indicateur de buffering : visible tant que la video se met en
            // memoire tampon et n'avance pas encore.
            if (value.isBuffering && !value.isPlaying)
              const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlayPause,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: value.isPlaying ? 0 : 1,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      LucideIcons.playCircle,
                      color: Colors.white,
                      size: 72,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xAA0F172A),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(
                    _muted ? LucideIcons.volumeX : LucideIcons.volume2,
                    color: Colors.white,
                  ),
                  tooltip: _muted ? "Activer le son" : "Couper le son",
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xC2000000)],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Barre de seek interactive : glisser pour avancer/reculer.
                    SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 3,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Color(0x66FFFFFF),
                        thumbColor: Colors.white,
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 14),
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: (_dragProgress ?? progress).clamp(0.0, 1.0),
                        onChanged: (v) => setState(() => _dragProgress = v),
                        onChangeEnd: (v) {
                          final target = duration * v;
                          controller.seekTo(target);
                          setState(() => _dragProgress = null);
                        },
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            value.isPlaying
                                ? LucideIcons.pauseCircle
                                : LucideIcons.playCircle,
                            color: Colors.white,
                            size: 30,
                          ),
                          tooltip: value.isPlaying ? "Pause" : "Lecture",
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${_formatDuration(position)} / ${_formatDuration(duration)}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    // Sur le web, la 1re video demarre en muet (politique autoplay du
    // navigateur). Un utilisateur qui tape sur la video s'attend a entendre
    // le son, pas a la mettre en pause : ce geste sert donc d'abord a
    // reactiver le son (comme TikTok/Instagram), la pause reste accessible
    // via un 2e tap une fois le son actif.
    if (_muted) {
      _toggleMute();
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final nextMuted = !_muted;
    controller.setVolume(nextMuted ? 0 : 1);
    _sessionMuted = nextMuted;
    setState(() {
      _muted = nextMuted;
    });
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds < 0 ? 0 : value.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, "0");
    final seconds = (totalSeconds % 60).toString().padLeft(2, "0");
    return "$minutes:$seconds";
  }

  Widget _buildCover() {
    final cover = widget.coverUrl.trim();
    if (cover.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF0F172A),
        child: Center(
          child: Icon(
            LucideIcons.playCircle,
            color: Colors.white70,
            size: 56,
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: _normalizedPlayableUrl(cover),
      fit: BoxFit.cover,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: Color(0xFF0F172A),
        child: Center(
          child: Icon(
            LucideIcons.imageOff,
            color: Colors.white70,
            size: 56,
          ),
        ),
      ),
    );
  }

  String _normalizedPlayableUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return "";
    }
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
      if (_isLoopback(uri.host)) {
        final origin = _apiOrigin();
        if (origin.isNotEmpty) {
          final path = uri.path.isEmpty ? "/" : uri.path;
          final query = uri.hasQuery ? "?${uri.query}" : "";
          return "$origin$path$query";
        }
      }
      return value;
    }
    if (uri != null && uri.scheme == "file") {
      final path = uri.path.trim();
      if (path.isEmpty) {
        return "";
      }
      final normalizedPath = path.startsWith("/") ? path : "/$path";
      final base = _apiBase();
      return base.isEmpty ? normalizedPath : "$base$normalizedPath";
    }
    if (uri != null && uri.scheme.isNotEmpty) {
      return "";
    }
    final relative = value.startsWith("/") ? value : "/$value";
    final mediaIndex = relative.indexOf("/media/");
    final normalizedRelative =
        mediaIndex >= 0 ? relative.substring(mediaIndex) : relative;
    final base = _apiBase();
    if (base.isEmpty) {
      return normalizedRelative;
    }
    return "$base$normalizedRelative";
  }

  String _apiBase() {
    return AppConfig.apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "");
  }

  String _apiOrigin() {
    final base = Uri.tryParse(_apiBase());
    if (base == null || base.scheme.isEmpty || base.host.isEmpty) {
      return "";
    }
    final port = base.hasPort ? ":${base.port}" : "";
    return "${base.scheme}://${base.host}$port";
  }

  bool _isLoopback(String host) {
    final value = host.toLowerCase().trim();
    return value == "127.0.0.1" || value == "localhost" || value == "0.0.0.0";
  }
}

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_config.dart';

class VideoPostPlayer extends StatefulWidget {
  const VideoPostPlayer({
    super.key,
    required this.videoUrl,
    required this.coverUrl,
  });

  final String videoUrl;
  final String coverUrl;

  @override
  State<VideoPostPlayer> createState() => _VideoPostPlayerState();
}

class _VideoPostPlayerState extends State<VideoPostPlayer> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final sourceUrl = _normalizedPlayableUrl(widget.videoUrl);
      if (sourceUrl.isEmpty) {
        throw Exception("URL video vide.");
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(sourceUrl));
      await controller.initialize();
      await controller.setVolume(1);
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _ready = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant VideoPostPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl == widget.videoUrl) {
      return;
    }
    _controller?.dispose();
    _controller = null;
    _ready = false;
    _failed = false;
    _muted = false;
    _init();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
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
                child: VideoPlayer(controller),
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
                      Icons.play_circle_fill,
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
                    _muted ? Icons.volume_off : Icons.volume_up,
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
                    LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: const Color(0x66FFFFFF),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _togglePlayPause,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
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
            Icons.play_circle_outline,
            color: Colors.white70,
            size: 56,
          ),
        ),
      );
    }
    return Image.network(
      _normalizedPlayableUrl(cover),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Color(0xFF0F172A),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
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

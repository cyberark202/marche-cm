import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Petit contrôleur d'enregistrement (logique, hors widget) partagé par la page
/// de chat. Encode en AAC/M4A (léger, accepté par le backend, type AUDIO).
class VoiceRecorder {
  final AudioRecorder _rec = AudioRecorder();
  Timer? _timer;
  final ValueNotifier<int> seconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> recording = ValueNotifier<bool>(false);
  String? _path;

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path);
    _path = path;
    seconds.value = 0;
    recording.value = true;
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => seconds.value += 1);
    return true;
  }

  /// Stoppe et renvoie le chemin du fichier (ou null si annulé/échec).
  Future<String?> stop() async {
    _timer?.cancel();
    recording.value = false;
    final path = await _rec.stop();
    return path ?? _path;
  }

  Future<void> cancel() async {
    _timer?.cancel();
    recording.value = false;
    try {
      await _rec.stop();
    } catch (_) {}
    _path = null;
  }

  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    seconds.dispose();
    recording.dispose();
  }
}

String formatSeconds(int s) {
  final m = (s ~/ 60).toString();
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}

/// Barre affichée dans le composer pendant l'enregistrement.
class VoiceRecordingBar extends StatelessWidget {
  const VoiceRecordingBar({
    super.key,
    required this.recorder,
    required this.onCancel,
    required this.onSend,
    this.accent = const Color(0xFF15803D),
  });

  final VoiceRecorder recorder;
  final VoidCallback onCancel;
  final VoidCallback onSend;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onCancel,
          icon: const Icon(LucideIcons.trash2, color: Colors.redAccent),
          tooltip: 'Annuler',
        ),
        const _PulsingDot(),
        const SizedBox(width: 8),
        ValueListenableBuilder<int>(
          valueListenable: recorder.seconds,
          builder: (_, s, __) => Text(
            formatSeconds(s),
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Colors.black54),
          ),
        ),
        const Spacer(),
        const Text('Enregistrement…',
            style: TextStyle(color: Colors.black45, fontSize: 12.5)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onSend,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: const Icon(LucideIcons.send, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
            color: Colors.redAccent, shape: BoxShape.circle),
      ),
    );
  }
}

/// Bulle de lecture d'une note vocale (play/pause + barre de progression).
class AudioMessageBubble extends StatefulWidget {
  const AudioMessageBubble({
    super.key,
    required this.url,
    this.accent = const Color(0xFF15803D),
  });

  final String url;
  final Color accent;

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _loaded = false;
  // Vitesse de lecture cyclique 1x → 1.5x → 2x (façon WhatsApp).
  static const List<double> _speeds = [1.0, 1.5, 2.0];
  double _speed = 1.0;

  Future<void> _cycleSpeed() async {
    final next =
        _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    setState(() => _speed = next);
    try {
      await _player.setSpeed(next);
    } catch (_) {
      // Certains codecs web refusent setSpeed : on garde la lecture normale.
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lecture audio impossible.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (_, snap) {
              final playing = snap.data?.playing ?? false;
              final completed =
                  snap.data?.processingState == ProcessingState.completed;
              return IconButton(
                onPressed: _toggle,
                icon: Icon(
                  playing && !completed
                      ? LucideIcons.pauseCircle
                      : LucideIcons.playCircle,
                  color: widget.accent,
                  size: 34,
                ),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (_, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final total = _player.duration ?? Duration.zero;
                final value = (total.inMilliseconds == 0)
                    ? 0.0
                    : (pos.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: value == 0 ? null : value,
                      minHeight: 3,
                      backgroundColor: Colors.black12,
                      color: widget.accent,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(LucideIcons.mic,
                            size: 12, color: Colors.black38),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            total == Duration.zero
                                ? 'Note vocale'
                                : '${formatSeconds(pos.inSeconds)} / ${formatSeconds(total.inSeconds)}',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.black45),
                          ),
                        ),
                        // Vitesse 1x/1.5x/2x, visible dès que l'audio est chargé.
                        if (total != Duration.zero)
                          GestureDetector(
                            onTap: _cycleSpeed,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _speed == 1.0
                                    ? '1x'
                                    : (_speed == 1.5 ? '1.5x' : '2x'),
                                style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black54),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

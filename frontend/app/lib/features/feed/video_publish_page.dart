import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/api_service.dart';
import '../../core/video_compression_service.dart';
import '../auth/session_store.dart';

class VideoPublishPage extends StatefulWidget {
  const VideoPublishPage({super.key});

  @override
  State<VideoPublishPage> createState() => _VideoPublishPageState();
}

class _VideoPublishPageState extends State<VideoPublishPage> {
  final ApiService _api = ApiService();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _weightKgController = TextEditingController(text: "1.000");

  PlatformFile? _videoFile;
  VideoPlayerController? _previewController;
  Duration? _duration;
  String _videoName = "";
  String? _error;
  bool _loadingPreview = false;
  bool _submitting = false;
  bool _compressing = false;
  double _compressionProgress = 0;

  String? _safePlatformFilePath(PlatformFile file) {
    if (kIsWeb) {
      return null;
    }
    try {
      final path = file.path;
      if (path == null || path.isEmpty) {
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _tagsController.dispose();
    _weightKgController.dispose();
    _previewController?.dispose();
    VideoCompressionService.cancel();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }
    final selected = picked.files.single;
    final hasPath = _safePlatformFilePath(selected) != null;
    final hasBytes = selected.bytes != null && selected.bytes!.isNotEmpty;
    if (!hasPath && !hasBytes) {
      setState(() => _error = "Impossible de lire cette video.");
      return;
    }
    setState(() {
      _videoFile = selected;
      _videoName = selected.name;
      _error = null;
    });
    await _preview();
  }

  Future<void> _preview() async {
    if (_videoFile == null) {
      setState(() => _error = "Importez d'abord une video.");
      return;
    }

    setState(() {
      _loadingPreview = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        _previewController?.dispose();
        setState(() {
          _previewController = null;
          _loadingPreview = false;
        });
        return;
      }

      final path = _safePlatformFilePath(_videoFile!);
      if (path == null || path.isEmpty) {
        setState(() {
          _loadingPreview = false;
          _error = "Impossible de previsualiser cette video.";
        });
        return;
      }
      final parsed = Uri.tryParse(path);
      late final VideoPlayerController next;
      if (parsed != null &&
          (parsed.scheme == "content" || parsed.scheme == "file")) {
        next = VideoPlayerController.contentUri(parsed);
      } else {
        next = VideoPlayerController.contentUri(Uri.file(path));
      }
      await next.initialize();
      final duration = next.value.duration;
      if (duration > const Duration(minutes: 3)) {
        next.dispose();
        setState(() {
          _duration = duration;
          _previewController?.dispose();
          _previewController = null;
          _error = "Video refusee: duree > 3 minutes.";
          _loadingPreview = false;
        });
        return;
      }
      await next.setLooping(true);
      await next.play();
      _previewController?.dispose();
      setState(() {
        _previewController = next;
        _duration = duration;
        _loadingPreview = false;
      });
    } catch (_) {
      setState(() {
        _loadingPreview = false;
        _error = "Impossible de previsualiser cette video.";
      });
    }
  }

  Future<void> _publish() async {
    if (_submitting) return;
    if (_videoFile == null) {
      setState(() => _error = "Importez une video avant publication.");
      return;
    }
    if (!kIsWeb && _previewController == null) {
      setState(() =>
          _error = "Previsualisation requise avec une video valide (< 3 min).");
      return;
    }
    if (_descriptionController.text.trim().isEmpty) {
      setState(() => _error = "La description est obligatoire.");
      return;
    }
    if (_tagsController.text.trim().isEmpty) {
      setState(() => _error = "Les tags sont obligatoires.");
      return;
    }
    final parsedWeight = double.tryParse(
      _weightKgController.text.trim().replaceAll(",", "."),
    );
    if (parsedWeight == null || parsedWeight <= 0) {
      setState(
          () => _error = "Le poids du produit (Kg) est obligatoire (> 0).");
      return;
    }

    final token = context.read<SessionStore>().token;
    setState(() {
      _submitting = true;
      _compressing = true;
      _compressionProgress = 0;
      _error = null;
    });

    PlatformFile fileToUpload;
    try {
      fileToUpload = await VideoCompressionService.compressIfNeeded(
        _videoFile!,
        onProgress: (p) {
          if (mounted) setState(() => _compressionProgress = p);
        },
      );
    } catch (_) {
      fileToUpload = _videoFile!;
    }
    if (!mounted) return;
    setState(() => _compressing = false);

    try {
      await _api.postMultipart(
        "/api/products/publish-video/",
        fields: {
          "description": _descriptionController.text.trim(),
          "tags": _tagsController.text.trim(),
          "weight_kg": parsedWeight.toStringAsFixed(3),
        },
        token: token,
        file: fileToUpload,
        fileFieldName: "video",
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Video publiee.")));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(
          e,
          fallback: "Publication echouee.",
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionStore>().role;
    final canPublish = role == UserRole.supplier || role == UserRole.wholesaler;
    if (!canPublish) {
      return Scaffold(
        appBar: AppBar(title: const Text("Publier une video")),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "Acces refuse. Seuls les comptes Fournisseur ou Grossiste peuvent publier des videos.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Publier une video")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _submitting ? null : _pickVideo,
            icon: const Icon(Icons.video_library_outlined),
            label: const Text("Importer une video"),
          ),
          if (_videoName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Fichier: $_videoName"),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: "Description"),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tagsController,
            decoration: const InputDecoration(
              labelText: "Tags",
              hintText: "ex: riz, alimentaire, gros",
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _weightKgController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Poids (Kg)",
              hintText: "ex: 12.500",
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _loadingPreview || _submitting ? null : _preview,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text("Previsualiser"),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: (_submitting || _compressing) ? null : _publish,
                icon: const Icon(Icons.publish_outlined),
                label: Text(_compressing
                    ? "Compression..."
                    : _submitting
                        ? "Publication..."
                        : "Publier"),
              ),
            ],
          ),
          if (_compressing) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.compress_outlined, size: 16, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Compression video... ${(_compressionProgress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: _compressionProgress),
                    ],
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_duration != null) ...[
            const SizedBox(height: 8),
            Text("Duree: ${_duration!.inSeconds}s / max 180s"),
          ],
          const SizedBox(height: 14),
          if (_loadingPreview) const Center(child: CircularProgressIndicator()),
          if (_previewController != null)
            AspectRatio(
              aspectRatio: _previewController!.value.aspectRatio,
              child: VideoPlayer(_previewController!),
            ),
        ],
      ),
    );
  }
}

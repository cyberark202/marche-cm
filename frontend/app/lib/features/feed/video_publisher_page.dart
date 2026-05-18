import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';
import 'feed_models.dart';

class VideoPublisherPage extends StatefulWidget {
  const VideoPublisherPage({super.key, required this.video});

  final VideoPostData video;

  @override
  State<VideoPublisherPage> createState() => _VideoPublisherPageState();
}

class _VideoPublisherPageState extends State<VideoPublisherPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _certs = const [];

  @override
  void initState() {
    super.initState();
    _loadCerts();
  }

  Future<void> _loadCerts() async {
    final token = context.read<SessionStore>().token;
    try {
      _certs = await _api.getList("/api/compliance-documents/?user_id=${widget.video.sellerId}", token: token);
    } catch (_) {
      _certs = const [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return Scaffold(
      appBar: AppBar(title: const Text("Profil vendeur")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(radius: 32, backgroundImage: NetworkImage(v.publisherAvatar)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("@${v.publisherName}", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text("Vendeur actif"),
                  ],
                ),
              ),
              FilledButton(onPressed: () {}, child: const Text("Suivre"))
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(v.coverUrl, height: 210, fit: BoxFit.cover),
          ),
          const SizedBox(height: 12),
          Text(v.description),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Certifications", style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_certs.isEmpty) const Text("Aucune certification approuvée."),
                for (final c in _certs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium, color: Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text((c["doc_type"] ?? "").toString())),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

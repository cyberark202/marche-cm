import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class CampaignsPage extends StatefulWidget {
  const CampaignsPage({super.key});

  @override
  State<CampaignsPage> createState() => _CampaignsPageState();
}

class _CampaignsPageState extends State<CampaignsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _productIdController = TextEditingController();
  final TextEditingController _targetQtyController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _campaigns = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "analytics")) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _productIdController.dispose();
    _targetQtyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      _campaigns = await _api.getList("/api/campaigns/", token: token);
    } catch (_) {
      _campaigns = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/campaigns/",
        {
          "product": int.tryParse(_productIdController.text) ?? 0,
          "target_quantity": int.tryParse(_targetQtyController.text) ?? 0,
        },
        token: token,
      );
      _productIdController.clear();
      _targetQtyController.clear();
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Campagnes groupées")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _productIdController, decoration: const InputDecoration(labelText: "ID produit"))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _targetQtyController, decoration: const InputDecoration(labelText: "Quantité cible"))),
              const SizedBox(width: 8),
              FilledButton(onPressed: _create, child: const Text("Créer"))
            ],
          ),
          const SizedBox(height: 10),
          for (final c in _campaigns)
            Card(
              child: ListTile(
                title: Text("Campagne #${c["id"]}"),
                subtitle: Text("Produit ${c["product"]} | ${c["current_quantity"]}/${c["target_quantity"]}"),
              ),
            )
        ],
      ),
    );
  }
}

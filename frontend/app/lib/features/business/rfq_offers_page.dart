import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class RfqOffersPage extends StatefulWidget {
  const RfqOffersPage({super.key});

  @override
  State<RfqOffersPage> createState() => _RfqOffersPageState();
}

class _RfqOffersPageState extends State<RfqOffersPage> {
  final ApiService _api = ApiService();
  final TextEditingController _rfqIdController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _offers = const [];

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
    _rfqIdController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      _offers = await _api.getList("/api/rfq-offers/", token: token);
    } catch (_) {
      _offers = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _create() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/rfq-offers/",
        {
          "rfq": int.tryParse(_rfqIdController.text) ?? 0,
          "price": double.tryParse(_priceController.text) ?? 0,
          "lead_time_days": 3,
        },
        token: token,
      );
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Offres RFQ")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(child: TextField(controller: _rfqIdController, decoration: const InputDecoration(labelText: "ID RFQ"))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _priceController, decoration: const InputDecoration(labelText: "Prix"), keyboardType: TextInputType.number)),
              const SizedBox(width: 8),
              FilledButton(onPressed: _create, child: const Text("Poster"))
            ],
          ),
          const SizedBox(height: 12),
          for (final offer in _offers)
            Card(
              child: ListTile(
                title: Text("Offre #${offer["id"]}"),
                subtitle: Text("RFQ: ${offer["rfq"]} | Prix: ${offer["price"]} | ETA: ${offer["lead_time_days"]} j"),
              ),
            )
        ],
      ),
    );
  }
}

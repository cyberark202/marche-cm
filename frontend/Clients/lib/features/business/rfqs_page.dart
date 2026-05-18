import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class RfqsPage extends StatefulWidget {
  const RfqsPage({super.key});

  @override
  State<RfqsPage> createState() => _RfqsPageState();
}

class _RfqsPageState extends State<RfqsPage> {
  final ApiService _api = ApiService();
  final TextEditingController _productController = TextEditingController();
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _rfqs = const [];
  String _defaultCountryCode = "";

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
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
    _productController.dispose();
    _qtyController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      _rfqs = await _api.getList("/api/rfqs/", token: token);
    } catch (_) {
      _rfqs = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final defaultCity = BackendUiConfigService.instance
          .readString(config, ["defaults", "rfq_city"]);
      final defaultCountry = BackendUiConfigService.instance
          .readString(config, ["defaults", "rfq_country_code"]);
      if (!mounted) return;
      setState(() => _defaultCountryCode = defaultCountry);
      if (_cityController.text.trim().isEmpty && defaultCity.isNotEmpty) {
        _cityController.text = defaultCity;
      }
    } catch (_) {}
  }

  Future<void> _create() async {
    final token = context.read<SessionStore>().token;
    try {
      final payload = <String, dynamic>{
        "product_name": _productController.text.trim(),
        "quantity": int.tryParse(_qtyController.text) ?? 0,
        "destination_city": _cityController.text.trim(),
      };
      if (_defaultCountryCode.trim().isNotEmpty) {
        payload["country_code"] = _defaultCountryCode.trim().toUpperCase();
      }
      await _api.post(
        "/api/rfqs/",
        payload,
        token: token,
      );
      await _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("RFQ - Demandes de devis")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          TextField(controller: _productController, decoration: const InputDecoration(labelText: "Produit")),
          const SizedBox(height: 8),
          TextField(controller: _qtyController, decoration: const InputDecoration(labelText: "Quantité"), keyboardType: TextInputType.number),
          const SizedBox(height: 8),
          TextField(controller: _cityController, decoration: const InputDecoration(labelText: "Ville destination")),
          const SizedBox(height: 8),
          FilledButton(onPressed: _create, child: const Text("Créer RFQ")),
          const SizedBox(height: 12),
          for (final rfq in _rfqs)
            Card(
              child: ListTile(
                title: Text("RFQ #${rfq["id"]} - ${rfq["product_name"]}"),
                subtitle: Text("Qté: ${rfq["quantity"]} | ${rfq["destination_city"]}"),
              ),
            ),
        ],
      ),
    );
  }
}

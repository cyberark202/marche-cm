import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

class RfqComparePage extends StatefulWidget {
  const RfqComparePage({super.key});

  @override
  State<RfqComparePage> createState() => _RfqComparePageState();
}

class _RfqComparePageState extends State<RfqComparePage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _rfqs = const [];
  List<Map<String, dynamic>> _offers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      _rfqs = await _api.getList("/api/rfqs/", token: token);
      _offers = await _api.getList("/api/rfq-offers/", token: token);
    } catch (_) {
      _rfqs = const [];
      _offers = const [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text("Comparateur RFQ")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (final rfq in _rfqs) ...[
            Text("RFQ #${rfq["id"]} - ${rfq["product_name"]}", style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ..._offers.where((o) => o["rfq"] == rfq["id"]).map(
                  (offer) => Card(
                    child: ListTile(
                      title: Text("Offre #${offer["id"]} • vendeur ${offer["seller"]}"),
                      subtitle: Text("Prix: ${offer["price"]} | Délai: ${offer["lead_time_days"]} j"),
                      trailing: FilledButton.tonal(onPressed: () {}, child: const Text("Négocier")),
                    ),
                  ),
                ),
            const SizedBox(height: 10),
          ]
        ],
      ),
    );
  }
}

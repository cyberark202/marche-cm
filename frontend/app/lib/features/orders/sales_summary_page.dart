import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_ui.dart';
import '../auth/session_store.dart';

class SalesSummaryPage extends StatefulWidget {
  const SalesSummaryPage({super.key});

  @override
  State<SalesSummaryPage> createState() => _SalesSummaryPageState();
}

class _SalesSummaryPageState extends State<SalesSummaryPage> {
  final ApiService _api = ApiService();
  Map<String, dynamic>? _payload;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final payload =
          await _api.getObject('/api/orders/sales-summary/', token: token);
      if (!mounted) return;
      setState(() {
        _payload = payload;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(e,
            fallback: "Impossible de charger les montants.");
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _money(dynamic raw, {String currency = "FCFA"}) {
    final value = (raw ?? "0.00").toString().trim();
    return "$value $currency";
  }

  int _asInt(dynamic raw) => int.tryParse((raw ?? "0").toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final payload = _payload ?? const <String, dynamic>{};
    final currency = (payload["currency"] ?? "FCFA").toString();
    final myAccount =
        (payload["my_account"] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final mySales = (payload["my_sales"] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final myPurchases =
        (payload["my_purchases"] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final overallSales =
        (payload["overall_sales"] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final isAdminScope = (payload["scope"] ?? "").toString() == "all_accounts";
    final accounts = ((payload["accounts"] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((entry) => entry.cast<String, dynamic>())
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Montants des ventes"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: AppPageBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const SizedBox(height: 6),
              const AppHeaderPanel(
                title: "Suivi financier des ventes",
                subtitle:
                    "Visualisez rapidement les montants vendus par compte et les commandes finalisees.",
                trailing: Icon(Icons.bar_chart_outlined),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                _SectionCard(
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else ...[
                _SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Compte: ${myAccount["username"] ?? "-"}",
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Reference: ${myAccount["reference_code"] ?? "-"} | Role: ${myAccount["role"] ?? "-"}",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        title: "Mes ventes",
                        value:
                            _money(mySales["total_amount"], currency: currency),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiCard(
                        title: "Ventes finalisees",
                        value: _money(mySales["completed_amount"],
                            currency: currency),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _KpiCard(
                        title: "Cmd ventes",
                        value: "${_asInt(mySales["orders_count"])}",
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _KpiCard(
                        title: "Mes achats",
                        value: _money(myPurchases["total_amount"],
                            currency: currency),
                      ),
                    ),
                  ],
                ),
                if (isAdminScope) ...[
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            "Vue globale (admin)",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          _money(overallSales["total_amount"],
                              currency: currency),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Comptes suivis: ${accounts.length}",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (accounts.isEmpty)
                          const Text("Aucun compte a afficher.")
                        else
                          ...accounts.map(
                            (account) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                "${account["username"] ?? "-"} (${account["reference_code"] ?? "-"})",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                "Role: ${account["role"] ?? "-"} | Commandes: ${_asInt(account["orders_count"])} | Finalisees: ${_asInt(account["completed_orders_count"])}",
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _money(account["total_amount"],
                                    currency: currency),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

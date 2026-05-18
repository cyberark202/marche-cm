import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import '../logistics/dispute_detail_page.dart';
import '../logistics/shipment_disputes_page.dart';
import '../orders/sales_summary_page.dart';
import '../wallet/wallet_page.dart';
import 'managed_user_creation_page.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final ApiService _api = ApiService();
  late Future<_AdminPayload> _future;
  int _navIndex = 0;
  List<Map<String, dynamic>> _latestPendingCompliance = const [];
  List<Map<String, String>> _disputeDecisions = const [];

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _future = _load();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _disputeDecisions = BackendUiConfigService.instance
            .readChoiceList(config, ["choices", "dispute_decisions"]);
      });
    } catch (_) {}
  }

  Future<_AdminPayload> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      final dashboard =
          await _api.getObject("/api/admin/dashboard/", token: token);
      final results = await Future.wait([
        _api.getList("/api/users/", token: token),
        _api.getList("/api/users/online/", token: token),
        _api.getList("/api/orders/", token: token),
        _api.getList("/api/shipments/", token: token),
        _api.getList("/api/compliance-documents/", token: token),
        _api.getList("/api/shipment-disputes/", token: token),
      ]);
      return _AdminPayload(
        dashboard: dashboard,
        users: results[0],
        onlineUsers: results[1],
        orders: results[2],
        shipments: results[3],
        complianceDocs: results[4],
        disputes: results[5],
        fallback: false,
      );
    } catch (_) {
      return const _AdminPayload(
        dashboard: {},
        users: <Map<String, dynamic>>[],
        onlineUsers: <Map<String, dynamic>>[],
        orders: <Map<String, dynamic>>[],
        shipments: <Map<String, dynamic>>[],
        complianceDocs: <Map<String, dynamic>>[],
        disputes: <Map<String, dynamic>>[],
        fallback: false,
      );
    }
  }

  Future<void> _exportAudit() async {
    final token = context.read<SessionStore>().token;
    try {
      final csv =
          await _api.downloadText("/api/admin/audit/export/", token: token);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Audit CSV (apercu)"),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Text(
                csv.split("\n").take(25).join("\n"),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Fermer")),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    }
  }

  Future<void> _decideDispute(int id, String decision) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/shipment-disputes/$id/decide/",
        {
          "status": "RESOLVED",
          "admin_decision": decision,
          "resolution_note": "Decision admin via dashboard",
        },
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Litige resolu.")),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _reviewDocument(int id, String status) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
          "/api/compliance-documents/$id/review/", {"status": status},
          token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Document $status.")));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Revision echouee.")));
    }
  }

  void _showPendingComplianceSheet() {
    if (_latestPendingCompliance.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Aucun document en attente.")));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: _latestPendingCompliance.take(8).map((doc) {
          final id = doc["id"] as int? ?? 0;
          return ListTile(
            title: Text("Doc #$id - ${(doc["doc_type"] ?? "").toString()}"),
            subtitle: Text("Utilisateur: ${doc["user"]}"),
            trailing: Wrap(
              spacing: 6,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(context);
                    _reviewDocument(id, "APPROVED");
                  },
                  child: const Text("OK"),
                ),
                FilledButton.tonal(
                  onPressed: () {
                    Navigator.pop(context);
                    _reviewDocument(id, "REJECTED");
                  },
                  child: const Text("KO"),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onBottomNavTapped(int index) {
    setState(() => _navIndex = index);
    if (index == 0) {
      return;
    }
    if (index == 1) {
      _refresh();
      return;
    }
    if (index == 2) {
      _showPendingComplianceSheet();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ShipmentDisputesPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Supervision Admin"),
        actions: [
          IconButton(
            onPressed: _exportAudit,
            icon: const Icon(Icons.download_outlined),
            tooltip: "Exporter audit",
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          _RoleMenu(session: session),
        ],
      ),
      body: FutureBuilder<_AdminPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const AppLoadingState(label: "Chargement du dashboard...");
          }
          final payload = snapshot.data!;
          final pendingCompliance = payload.complianceDocs
              .where((d) => "${d["status"]}" == "PENDING")
              .toList();
          _latestPendingCompliance = pendingCompliance;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.2,
                children: [
                  _KpiCard(title: "Utilisateurs", value: "${payload.dashboard["users_total"] ?? payload.users.length}"),
                  _KpiCard(title: "En ligne", value: "${payload.onlineUsers.length}"),
                  _KpiCard(title: "Dossiers ouverts", value: "${payload.disputes.where((d) => "${d["status"]}" == "OPEN").length}"),
                  _KpiCard(title: "Commandes", value: "${payload.orders.length}"),
                  _KpiCard(title: "Expéditions", value: "${payload.shipments.length}"),
                  _KpiCard(title: "En attente", value: "${payload.dashboard["open_compliance"] ?? pendingCompliance.length}"),
                ],
              ),
              const SizedBox(height: 12),
              _WindowCard(
                title: "Ventes par compte",
                icon: Icons.bar_chart_outlined,
                body: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SalesSummaryPage(),
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text("Ouvrir l'ecran des ventes"),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Creation comptes metier",
                icon: Icons.person_add_alt_1_outlined,
                body: Column(
                  children: [
                    const Text(
                      "La creation des comptes metier est desormais geree sur un ecran dedie.",
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final created =
                              await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => const ManagedUserCreationPage(),
                            ),
                          );
                          if (created == true) {
                            await _refresh();
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text("Ouvrir l'ecran creation"),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Validation certifications",
                icon: Icons.fact_check_outlined,
                body: pendingCompliance.isEmpty
                    ? const Text("Aucun document en attente.")
                    : Column(
                        children: pendingCompliance.take(8).map((doc) {
                          final id = doc["id"] as int? ?? 0;
                          return Card(
                            child: ListTile(
                              title: Text(
                                  "Doc #$id - ${(doc["doc_type"] ?? "").toString()}"),
                              subtitle: Text("Utilisateur: ${doc["user"]}"),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _reviewDocument(id, "APPROVED"),
                                    child: const Text("Approuver"),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: () =>
                                        _reviewDocument(id, "REJECTED"),
                                    child: const Text("Rejeter"),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Surveillance opérationnelle",
                icon: Icons.monitor_heart_outlined,
                actions: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ShipmentDisputesPage())),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Voir tout'),
                  ),
                ],
                body: Column(
                  children: [
                    _SimpleList(
                      items: payload.onlineUsers.take(6).map((u) {
                        return _SimpleItem(
                          title: (u["username"] ?? "").toString(),
                          subtitle: "Role: ${u["role"]}",
                        );
                      }).toList(),
                    ),
                    const Divider(height: 20),
                    _SimpleList(
                      items: payload.disputes.take(6).map((d) {
                        final disputeId = d["id"] as int?;
                        return _SimpleItem(
                          title: "Dossier #$disputeId",
                          subtitle:
                              "${d["reason"] ?? "-"} | ${d["status"] ?? "-"}",
                          trailing: "${d["status"]}" == "OPEN"
                              ? Wrap(
                                  children: _disputeDecisions.take(2).map(
                                    (decision) {
                                      return TextButton(
                                        onPressed: () => _decideDispute(
                                          d["id"] as int,
                                          decision["value"]!,
                                        ),
                                        child: Text(
                                          decision["label"] ??
                                              decision["value"]!,
                                        ),
                                      );
                                    },
                                  ).toList(),
                                )
                              : null,
                          onTap: disputeId == null
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DisputeDetailPage(
                                          disputeId: disputeId),
                                    ),
                                  ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onBottomNavTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: "Accueil",
            ),
            NavigationDestination(
              icon: Icon(Icons.refresh_outlined),
              selectedIcon: Icon(Icons.refresh),
              label: "Refresh",
            ),
            NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: "Compliance",
            ),
            NavigationDestination(
              icon: Icon(Icons.gavel_outlined),
              selectedIcon: Icon(Icons.gavel),
              label: "Litiges",
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminPayload {
  const _AdminPayload({
    required this.dashboard,
    required this.users,
    required this.onlineUsers,
    required this.orders,
    required this.shipments,
    required this.complianceDocs,
    required this.disputes,
    required this.fallback,
  });

  final Map<String, dynamic> dashboard;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> onlineUsers;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> shipments;
  final List<Map<String, dynamic>> complianceDocs;
  final List<Map<String, dynamic>> disputes;
  final bool fallback;
}

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.session});
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.verified_user_outlined, size: 16),
      label: Text(session.role.name),
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
          border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800))
      ]),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.title, required this.icon, this.body, this.actions});
  final String title;
  final IconData icon;
  final Widget? body;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 4))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            if (actions != null) ...actions!,
          ]),
          if (body != null) ...[
            const SizedBox(height: 10),
            body!,
          ],
        ],
      ),
    );
  }
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({required this.items});
  final List<_SimpleItem> items;
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text("Aucune donnee.");
    }
    return Column(
      children: items
          .map((item) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(item.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(item.subtitle,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: item.trailing ??
                    (item.onTap != null
                        ? const Icon(Icons.chevron_right, size: 16)
                        : null),
                onTap: item.onTap,
              ))
          .toList(),
    );
  }
}

class _SimpleItem {
  const _SimpleItem(
      {required this.title, required this.subtitle, this.trailing, this.onTap});
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
}

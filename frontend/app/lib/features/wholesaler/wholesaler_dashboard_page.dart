import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';
import '../business/rfq_offers_page.dart';
import '../feed/video_publish_page.dart';
import '../logistics/seller_dispute_page.dart';
import '../orders/sales_summary_page.dart';
import '../profile/compliance_documents_page.dart';
import '../wallet/wallet_page.dart';

class WholesalerDashboardPage extends StatefulWidget {
  const WholesalerDashboardPage({super.key});

  @override
  State<WholesalerDashboardPage> createState() =>
      _WholesalerDashboardPageState();
}

class _WholesalerDashboardPageState extends State<WholesalerDashboardPage> {
  final ApiService _api = ApiService();
  late Future<_WholesalerPayload> _future;
  int _navIndex = 0;
  List<Map<String, dynamic>> _latestProducts = const [];
  int _defaultCampaignTargetQty = 0;
  int _defaultProductAvailableQty = 0;
  int _defaultProductUnitPrice = 0;

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
        _defaultCampaignTargetQty = BackendUiConfigService.instance
            .readInt(config, ["defaults", "campaign_target_quantity"]);
        _defaultProductAvailableQty = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_available_qty"]);
        _defaultProductUnitPrice = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_unit_price"]);
      });
    } catch (_) {}
  }

  Future<_WholesalerPayload> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList("/api/products/mine/", token: token),
        _api.getList("/api/campaigns/", token: token),
        _api.getList("/api/rfqs/", token: token),
        _api.getList("/api/rfq-offers/", token: token),
        _api.getList("/api/orders/", token: token),
        _api.getList("/api/shipments/", token: token),
        _api.getList("/api/wallets/", token: token),
        _api.getList("/api/compliance-documents/", token: token),
      ]);
      return _WholesalerPayload(
        products: results[0],
        campaigns: results[1],
        rfqs: results[2],
        offers: results[3],
        orders: results[4],
        shipments: results[5],
        wallets: results[6],
        complianceDocs: results[7],
        fallback: false,
      );
    } catch (_) {
      return const _WholesalerPayload(
        products: <Map<String, dynamic>>[],
        campaigns: <Map<String, dynamic>>[],
        rfqs: <Map<String, dynamic>>[],
        offers: <Map<String, dynamic>>[],
        orders: <Map<String, dynamic>>[],
        shipments: <Map<String, dynamic>>[],
        wallets: <Map<String, dynamic>>[],
        complianceDocs: <Map<String, dynamic>>[],
        fallback: false,
      );
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _createCampaignDialog(
      List<Map<String, dynamic>> products) async {
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ajoutez d'abord un produit.")));
      return;
    }
    int? selectedProduct = products.first["id"] as int?;
    final target =
        TextEditingController(text: _defaultCampaignTargetQty.toString());
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text("Nouvelle campagne"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: selectedProduct,
                items: products
                    .map((p) => DropdownMenuItem<int>(
                          value: p["id"] as int?,
                          child: Text(
                              "#${p["id"]} - ${(p["title"] ?? "").toString()}"),
                        ))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedProduct = v),
                decoration: const InputDecoration(labelText: "Produit"),
              ),
              TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: "Quantite cible")),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            FilledButton(
              onPressed: selectedProduct == null
                  ? null
                  : () async {
                      final token = context.read<SessionStore>().token;
                      try {
                        await _api.post(
                            "/api/campaigns/",
                            {
                              "product": selectedProduct,
                              "target_quantity": int.tryParse(target.text) ?? 0,
                              "is_open": true,
                            },
                            token: token);
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Campagne creee.")));
                        await _refresh();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(_api.toUserMessage(e,
                                fallback: "Creation campagne echouee."))));
                      }
                    },
              child: const Text("Creer"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createProductDialog() async {
    final title = TextEditingController();
    final brand = TextEditingController();
    final category = TextEditingController();
    final description = TextEditingController();
    final availableQty =
        TextEditingController(text: _defaultProductAvailableQty.toString());
    final unitPrice =
        TextEditingController(text: _defaultProductUnitPrice.toString());
    final weightKg = TextEditingController(text: "1.000");
    final colors = TextEditingController();
    PlatformFile? imageFile;
    String imageName = "";

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Nouveau produit"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                    controller: title,
                    decoration: const InputDecoration(labelText: "Titre")),
                TextField(
                    controller: brand,
                    decoration: const InputDecoration(labelText: "Marque")),
                TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: "Categorie")),
                TextField(
                    controller: description,
                    decoration:
                        const InputDecoration(labelText: "Description")),
                TextField(
                    controller: availableQty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: "Quantite disponible")),
                TextField(
                    controller: unitPrice,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: "Prix article")),
                TextField(
                    controller: weightKg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: "Poids (Kg)")),
                TextField(
                    controller: colors,
                    decoration: const InputDecoration(
                        labelText: "Couleurs (optionnel)")),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          allowMultiple: false,
                          withData: kIsWeb,
                        );
                        if (picked == null || picked.files.isEmpty) {
                          return;
                        }
                        final selected = picked.files.single;
                        final hasPath = _safePlatformFilePath(selected) != null;
                        final hasBytes = selected.bytes != null &&
                            selected.bytes!.isNotEmpty;
                        if (!hasPath && !hasBytes) {
                          return;
                        }
                        setDialogState(() {
                          imageFile = selected;
                          imageName = selected.name;
                        });
                      },
                      icon: const Icon(Icons.image_outlined),
                      label: const Text("Importer image"),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        imageName.isEmpty ? "Aucune image" : imageName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("Annuler")),
            FilledButton(
              onPressed: () async {
                final token = context.read<SessionStore>().token;
                try {
                  final categoryName = category.text.trim();
                  final parsedWeight = double.tryParse(
                    weightKg.text.trim().replaceAll(",", "."),
                  );
                  if (title.text.trim().isEmpty ||
                      brand.text.trim().isEmpty ||
                      categoryName.isEmpty ||
                      parsedWeight == null ||
                      parsedWeight <= 0) {
                    throw Exception(
                      "Titre, marque, categorie et poids (Kg > 0) sont obligatoires.",
                    );
                  }
                  await _api.postMultipart(
                    "/api/products/",
                    fields: {
                      "title": title.text.trim(),
                      "brand": brand.text.trim(),
                      "category_name": categoryName,
                      "description": description.text.trim(),
                      "available_qty":
                          (int.tryParse(availableQty.text) ?? 0).toString(),
                      "unit_price":
                          (double.tryParse(unitPrice.text) ?? 0).toString(),
                      "weight_kg": parsedWeight.toStringAsFixed(3),
                      "colors": colors.text.trim(),
                      "allows_group_campaign": "true",
                      "is_active": "true",
                    },
                    token: token,
                    file: imageFile,
                    fileFieldName: "image",
                  );
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Produit ajoute.")));
                  await _refresh();
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text(_api.toUserMessage(e,
                            fallback: "Creation produit echouee."))),
                  );
                }
              },
              child: const Text("Publier"),
            ),
          ],
        ),
      ),
    );
  }

  void _onBottomNavTapped(int index) {
    setState(() => _navIndex = index);
    if (index == 0) {
      return;
    }
    if (index == 1) {
      _createProductDialog();
      return;
    }
    if (index == 2) {
      _createCampaignDialog(_latestProducts);
      return;
    }
    if (index == 3) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const RfqOffersPage()));
      return;
    }
    if (index == 4) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const VideoPublishPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Espace Grossiste"),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SellerDisputePage()),
            ),
            icon: const Icon(Icons.gavel_outlined),
            tooltip: 'Litiges',
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
      body: FutureBuilder<_WholesalerPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payload = snapshot.data!;
          _latestProducts = payload.products;
          final openCampaigns =
              payload.campaigns.where((c) => c["is_open"] == true).length;
          final pendingCompliance = payload.complianceDocs
              .where((d) => "${d["status"]}" == "PENDING")
              .length;
          final wallet = payload.wallets.isEmpty
              ? const <String, dynamic>{}
              : payload.wallets.first;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                          title: "Produits",
                          value: "${payload.products.length}")),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _KpiCard(
                          title: "Campagnes ouvertes",
                          value: "$openCampaigns")),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _KpiCard(
                          title: "Offres RFQ",
                          value: "${payload.offers.length}")),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _KpiCard(
                          title: "Commandes",
                          value: "${payload.orders.length}")),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _KpiCard(
                          title: "Wallet",
                          value: "${wallet["balance"] ?? "0"} FCFA")),
                ],
              ),
              const SizedBox(height: 12),
              _WindowCard(
                title: "Suivi des ventes",
                icon: Icons.bar_chart_outlined,
                body: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: const Text("Ouvrir l'ecran montants des ventes"),
                  subtitle:
                      const Text("Comptabilisation de vos ventes par compte"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SalesSummaryPage()),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Certifications",
                icon: Icons.verified_user_outlined,
                body: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text("Ouvrir l'ecran certifications"),
                      subtitle:
                          Text("$pendingCompliance document(s) en attente"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ComplianceDocumentsPage(),
                        ),
                      ),
                    ),
                    _SimpleList(
                      items: payload.complianceDocs.take(4).map(
                        (doc) {
                          return _SimpleItem(
                            title: (doc["doc_type"] ?? "-").toString(),
                            subtitle: "Statut: ${doc["status"] ?? "-"}",
                          );
                        },
                      ).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Campagnes en cours",
                icon: Icons.trending_up_outlined,
                body: _SimpleList(
                  items: payload.campaigns.take(6).map((c) {
                    final current = c["current_quantity"] ?? 0;
                    final target = c["target_quantity"] ?? 0;
                    return _SimpleItem(
                      title: "Campagne #${c["id"]}",
                      subtitle:
                          "$current / $target | ${c["is_open"] == true ? "ouverte" : "fermee"}",
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Flux commandes & logistique",
                icon: Icons.inventory_outlined,
                body: Column(
                  children: [
                    _SimpleList(
                      items: payload.orders.take(5).map((o) {
                        return _SimpleItem(
                          title: "Commande #${o["id"]}",
                          subtitle:
                              "${o["status"]} | Total ${o["total_price"]}",
                        );
                      }).toList(),
                    ),
                    const Divider(height: 20),
                    _SimpleList(
                      items: payload.shipments.take(5).map((s) {
                        return _SimpleItem(
                          title: "Expedition #${s["id"]}",
                          subtitle: "Statut: ${s["status"]}",
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: "Opportunites RFQ",
                icon: Icons.search_outlined,
                body: _SimpleList(
                  items: payload.rfqs.take(6).map((rfq) {
                    return _SimpleItem(
                      title: "${rfq["product_name"]} (#${rfq["id"]})",
                      subtitle: "Statut: ${rfq["status"]}",
                    );
                  }).toList(),
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
              icon: Icon(Icons.add_business_outlined),
              selectedIcon: Icon(Icons.add_business),
              label: "Produit",
            ),
            NavigationDestination(
              icon: Icon(Icons.campaign_outlined),
              selectedIcon: Icon(Icons.campaign),
              label: "Campagne",
            ),
            NavigationDestination(
              icon: Icon(Icons.request_quote_outlined),
              selectedIcon: Icon(Icons.request_quote),
              label: "Offres",
            ),
            NavigationDestination(
              icon: Icon(Icons.smart_display_outlined),
              selectedIcon: Icon(Icons.smart_display),
              label: "Video",
            ),
          ],
        ),
      ),
    );
  }
}

class _WholesalerPayload {
  const _WholesalerPayload({
    required this.products,
    required this.campaigns,
    required this.rfqs,
    required this.offers,
    required this.orders,
    required this.shipments,
    required this.wallets,
    required this.complianceDocs,
    required this.fallback,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> campaigns;
  final List<Map<String, dynamic>> rfqs;
  final List<Map<String, dynamic>> offers;
  final List<Map<String, dynamic>> orders;
  final List<Map<String, dynamic>> shipments;
  final List<Map<String, dynamic>> wallets;
  final List<Map<String, dynamic>> complianceDocs;
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
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800))
      ]),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.title, required this.icon, this.body});
  final String title;
  final IconData icon;
  final Widget? body;
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700))
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
              ))
          .toList(),
    );
  }
}

class _SimpleItem {
  const _SimpleItem({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';

class SupplierProductsPage extends StatefulWidget {
  const SupplierProductsPage({super.key});

  @override
  State<SupplierProductsPage> createState() => _SupplierProductsPageState();
}

class _SupplierProductsPageState extends State<SupplierProductsPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _products = const [];
  bool _loading = true;
  String? _error;
  int _defaultMinQty = 0;
  int _defaultMaxQty = 0;
  int _defaultMinPrice = 0;
  int _defaultMaxPrice = 0;

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
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      _products = await _api.getList("/api/products/mine/", token: token);
      _error = null;
    } catch (e) {
      _products = const [];
      _error = _api.toUserMessage(
        e,
        fallback: "Impossible de charger vos publications.",
      );
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _defaultMinQty = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_min_qty"]);
        _defaultMaxQty = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_max_qty"]);
        _defaultMinPrice = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_min_price"]);
        _defaultMaxPrice = BackendUiConfigService.instance
            .readInt(config, ["defaults", "product_max_price"]);
      });
    } catch (_) {}
  }

  Future<void> _openCreateProductDialog() async {
    final title = TextEditingController();
    final brand = TextEditingController();
    final category = TextEditingController();
    final description = TextEditingController();
    final minQty = TextEditingController(text: _defaultMinQty.toString());
    final maxQty = TextEditingController(text: _defaultMaxQty.toString());
    final minPrice = TextEditingController(text: _defaultMinPrice.toString());
    final maxPrice = TextEditingController(text: _defaultMaxPrice.toString());
    final weightKg = TextEditingController(text: "1.000");
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
                  decoration: const InputDecoration(labelText: "Titre"),
                ),
                TextField(
                  controller: brand,
                  decoration: const InputDecoration(labelText: "Marque"),
                ),
                TextField(
                  controller: category,
                  decoration: const InputDecoration(labelText: "Categorie"),
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: "Description"),
                ),
                TextField(
                  controller: minQty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Quantite min"),
                ),
                TextField(  
                  controller: maxQty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Quantite max"),
                ),
                TextField(
                  controller: minPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Prix min"),
                ),
                TextField(
                  controller: maxPrice,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "Prix max"),
                ),
                TextField(
                  controller: weightKg,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: "Poids (Kg)"),
                ),
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
                        if (picked == null || picked.files.isEmpty) return;
                        final selected = picked.files.single;
                        final hasPath = _safePlatformFilePath(selected) != null;
                        final hasBytes = selected.bytes != null &&
                            selected.bytes!.isNotEmpty;
                        if (!hasPath && !hasBytes) return;
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
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () async {
                final token = context.read<SessionStore>().token;
                try {
                  final categoryName = category.text.trim();
                  final parsedWeight = double.tryParse(
                    weightKg.text.trim().replaceAll(",", "."),
                  );
                  final parsedMinQty = int.tryParse(minQty.text) ?? 1;
                  final parsedMaxQty = int.tryParse(maxQty.text) ?? 10;
                  final parsedMinPrice = double.tryParse(minPrice.text) ?? 0;
                  final parsedMaxPrice = double.tryParse(maxPrice.text) ?? 0;
                  if (title.text.trim().isEmpty ||
                      brand.text.trim().isEmpty ||
                      categoryName.isEmpty ||
                      parsedWeight == null ||
                      parsedWeight <= 0) {
                    throw Exception(
                      "Titre, marque, categorie et poids (Kg > 0) sont obligatoires.",
                    );
                  }
                  if (parsedMinQty > parsedMaxQty) {
                    throw Exception(
                      "Quantite invalide: la quantite min doit etre inferieure ou egale a la quantite max.",
                    );
                  }
                  if (parsedMinPrice > parsedMaxPrice) {
                    throw Exception(
                      "Prix invalide: le prix min doit etre inferieur ou egal au prix max.",
                    );
                  }
                  await _api.postMultipart(
                    "/api/products/",
                    fields: {
                      "title": title.text.trim(),
                      "brand": brand.text.trim(),
                      "category_name": categoryName,
                      "description": description.text.trim(),
                      "min_order_qty": parsedMinQty.toString(),
                      "max_order_qty": parsedMaxQty.toString(),
                      "price_for_min_qty": parsedMinPrice.toString(),
                      "price_for_max_qty": parsedMaxPrice.toString(),
                      "weight_kg": parsedWeight.toStringAsFixed(3),
                      "allows_group_campaign": "false",
                      "is_active": "true",
                    },
                    token: token,
                    file: imageFile,
                    fileFieldName: "image",
                  );
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Produit cree.")),
                  );
                  await _load();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mes produits"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateProductDialog,
        icon: const Icon(Icons.add_business),
        label: const Text("Ajouter un produit"),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                const _HeaderCard(
                  title: "Catalogue fournisseur",
                  subtitle:
                      "Publiez vos articles et gerez rapidement votre inventaire.",
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  _SectionCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Chargement incomplet"),
                      subtitle: Text(_error!),
                    ),
                  ),
                if (_products.isEmpty)
                  const _SectionCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text("Aucun produit"),
                      subtitle: Text("Ajoutez votre premier article."),
                    ),
                  ),
                ..._products.map(
                  (p) => _SectionCard(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text((p["title"] ?? "").toString()),
                      subtitle: Text(
                        "Qt min/max: ${p["min_order_qty"] ?? "-"}-${p["max_order_qty"] ?? "-"} | Prix: ${p["price_for_min_qty"] ?? "-"}-${p["price_for_max_qty"] ?? "-"} | Poids: ${p["weight_kg"] ?? "-"} kg",
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: child,
    );
  }
}

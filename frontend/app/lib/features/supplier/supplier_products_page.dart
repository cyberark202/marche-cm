import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
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
  List<Map<String, dynamic>> _filtered = const [];
  bool _loading = true;
  String? _error;
  int _defaultMinQty = 0;
  int _defaultMaxQty = 0;
  int _defaultMinPrice = 0;
  int _defaultMaxPrice = 0;
  final TextEditingController _searchCtrl = TextEditingController();

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
    _searchCtrl.addListener(_applySearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_applySearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applySearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _products;
      } else {
        _filtered = _products
            .where((p) =>
                (p['title'] ?? '').toString().toLowerCase().contains(q) ||
                (p['brand'] ?? '').toString().toLowerCase().contains(q) ||
                (p['category_name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(q))
            .toList();
      }
    });
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
    if (mounted) {
      setState(() {
        _loading = false;
        _filtered = _products;
      });
    }
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
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'Mes produits',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
          : Column(
              children: [
                // Barre de recherche
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Chercher un produit...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                        borderSide:
                            const BorderSide(color: AppPalette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                        borderSide:
                            const BorderSide(color: AppPalette.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                        borderSide: const BorderSide(
                            color: AppPalette.primary, width: 1.8),
                      ),
                    ),
                  ),
                ),

                // Erreur
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppPalette.dangerSoft,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(
                            color: AppPalette.danger
                                .withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: AppPalette.danger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(
                                color: AppPalette.danger,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Liste
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                size: 64,
                                color: AppPalette.textMuted
                                    .withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Aucun produit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Ajoutez votre premier article.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppPalette.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _filtered.length,
                          itemBuilder: (context, i) {
                            final p = _filtered[i];
                            final isActive = p['is_active'] == true;
                            final minQ =
                                p['min_order_qty']?.toString() ?? '-';
                            final maxQ =
                                p['max_order_qty']?.toString() ?? '-';
                            final minP =
                                p['price_for_min_qty']?.toString() ?? '-';
                            final maxP =
                                p['price_for_max_qty']?.toString() ?? '-';
                            final weight =
                                p['weight_kg']?.toString() ?? '-';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.md),
                                border: Border.all(
                                    color: AppPalette.borderSoft),
                                boxShadow: AppPalette.shadowSoft,
                              ),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // Icône
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppPalette.primary
                                          .withValues(alpha: 0.10),
                                      borderRadius:
                                          BorderRadius.circular(AppRadii.sm),
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2_outlined,
                                      color: AppPalette.primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Contenu
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (p['title'] ?? '').toString(),
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppPalette.text,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Qté $minQ-$maxQ | Prix $minP-$maxP FCFA | $weight kg',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppPalette.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),

                                  // Badge statut
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? AppPalette.successSoft
                                          : AppPalette.bgDeep,
                                      borderRadius: BorderRadius.circular(
                                          AppRadii.pill),
                                    ),
                                    child: Text(
                                      isActive ? 'Actif' : 'Inactif',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: isActive
                                            ? AppPalette.success
                                            : AppPalette.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

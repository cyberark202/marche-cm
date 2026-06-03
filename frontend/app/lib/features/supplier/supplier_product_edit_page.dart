import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import 'product_request_model.dart';

/// Éditer / créer un produit fournisseur (PDF 16).
class SupplierProductEditPage extends StatefulWidget {
  const SupplierProductEditPage({super.key, this.product});

  /// `null` → mode création. Sinon, contient les champs venant de
  /// `/api/products/mine/` pour pré-remplir le formulaire.
  final Map<String, dynamic>? product;

  @override
  State<SupplierProductEditPage> createState() =>
      _SupplierProductEditPageState();
}

class _SupplierProductEditPageState extends State<SupplierProductEditPage> {
  final ApiService _api = ApiService();
  final _title = TextEditingController();
  final _brand = TextEditingController();
  final _category = TextEditingController();
  final _description = TextEditingController();
  final _minQty = TextEditingController();
  final _maxQty = TextEditingController();
  final _priceMin = TextEditingController();
  final _priceMax = TextEditingController();
  final _weight = TextEditingController();
  final _stockAvailable = TextEditingController();
  final _stockReserved = TextEditingController();
  bool _busy = false;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    if (p != null) {
      _title.text = (p["title"] ?? "").toString();
      _brand.text = (p["brand"] ?? "").toString();
      _category.text =
          (p["category_name"] ?? p["category"] ?? "").toString();
      _description.text = (p["description"] ?? "").toString();
      _minQty.text = (p["min_qty"] ?? "").toString();
      _maxQty.text = (p["max_qty"] ?? "").toString();
      _priceMin.text = (p["price_min"] ?? p["price_for_max_qty"] ?? "").toString();
      _priceMax.text = (p["price_max"] ?? p["price_for_min_qty"] ?? "").toString();
      _stockAvailable.text = (p["available_qty"] ?? p["stock"] ?? "").toString();
      _stockReserved.text = (p["min_stock"] ?? "").toString();
      _weight.text = (p["weight_kg"] ?? "").toString();
    }
    for (final c in [_minQty, _maxQty, _priceMin, _priceMax]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _brand,
      _category,
      _description,
      _minQty,
      _maxQty,
      _priceMin,
      _priceMax,
      _weight,
      _stockAvailable,
      _stockReserved,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    // C-1: build the canonical payload via the shared ProductRequestModel.
    // Price mapping follows the form labels: "_priceMin" is the bulk/high-volume
    // price (=> price_for_max_qty) and "_priceMax" is the low-volume price
    // (=> price_for_min_qty).
    final stock = int.tryParse(_stockAvailable.text.trim());
    final model = ProductRequestModel(
      title: _title.text,
      brand: _brand.text,
      categoryName: _category.text,
      description: _description.text,
      minOrderQty: int.tryParse(_minQty.text.trim()) ?? 0,
      maxOrderQty: int.tryParse(_maxQty.text.trim()) ?? 0,
      priceForMinQty: num.tryParse(_priceMax.text.trim()) ?? 0,
      priceForMaxQty: num.tryParse(_priceMin.text.trim()) ?? 0,
      weightKg: num.tryParse(_weight.text.trim()) ?? 0,
      availableQty: stock != null && stock > 0 ? stock : null,
    );
    final validationError = model.validate();
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }
    setState(() => _busy = true);
    final token = context.read<SessionStore>().token;
    try {
      final body = model.toJson();
      if (_isEdit) {
        final id = widget.product!["id"];
        await _api.patch("/api/products/$id/", body, token: token);
      } else {
        await _api.post("/api/products/", body, token: token);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isEdit
                ? "Produit mis à jour."
                : "Produit créé.")),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Échec de l'enregistrement."))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<_TierRow> _computeTiers() {
    final qmin = int.tryParse(_minQty.text) ?? 0;
    final qmax = int.tryParse(_maxQty.text) ?? 0;
    final pHigh = int.tryParse(_priceMax.text) ?? 0;
    final pLow = int.tryParse(_priceMin.text) ?? 0;
    if (qmax <= qmin || pHigh <= 0) {
      return [
        _TierRow(range: "—", price: pHigh > 0 ? pHigh : pLow, discount: 0),
      ];
    }
    final span = qmax - qmin;
    final t1Max = (qmin + span * 0.25).round();
    final t2Max = (qmin + span * 0.7).round();
    final p2 = ((pHigh + pLow) ~/ 2);
    final d2 = pHigh > 0 ? (100 - (p2 * 100 / pHigh)).round() : 0;
    final d3 = pHigh > 0 ? (100 - (pLow * 100 / pHigh)).round() : 0;
    return [
      _TierRow(range: "$qmin – $t1Max", price: pHigh, discount: 0),
      _TierRow(range: "${t1Max + 1} – $t2Max", price: p2, discount: d2),
      _TierRow(range: "${t2Max + 1} – $qmax", price: pLow, discount: d3),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tiers = _computeTiers();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
                isEdit: _isEdit,
                onBack: () => Navigator.maybePop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  const _SectionLabel(label: "PHOTOS & VIDÉO"),
                  const SizedBox(height: 10),
                  _MediaGrid(),
                  const SizedBox(height: 20),
                  _Field(
                    label: "Nom du produit",
                    controller: _title,
                    hint: "Ex : Huile de palme raffinée — bidon 20 L",
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: _Field(
                              label: "Catégorie",
                              controller: _category,
                              hint: "Agroalimentaire")),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Field(
                              label: "Marque",
                              controller: _brand,
                              hint: "Tropical")),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: "Description",
                    controller: _description,
                    hint:
                        "Composition, conditionnement, certification, conseils d'usage…",
                    minLines: 4,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: "Poids unitaire (kg)",
                    controller: _weight,
                    hint: "Ex : 20",
                    numeric: true,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const _SectionLabel(label: "PRIX PAR PALIERS B2B"),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppPalette.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add,
                                size: 13, color: AppPalette.primaryDark),
                            SizedBox(width: 3),
                            Text("Palier",
                                style: TextStyle(
                                    color: AppPalette.primaryDark,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppPalette.card,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(color: AppPalette.borderSoft),
                      boxShadow: AppPalette.shadowSoft,
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _Field(
                                label: "Qty min",
                                controller: _minQty,
                                numeric: true,
                              )),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _Field(
                                label: "Qty max",
                                controller: _maxQty,
                                numeric: true,
                              )),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                          child: Row(
                            children: [
                              Expanded(
                                  child: _Field(
                                label: "Prix gros (gros volume)",
                                controller: _priceMin,
                                numeric: true,
                              )),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: _Field(
                                label: "Prix max (faible volume)",
                                controller: _priceMax,
                                numeric: true,
                              )),
                            ],
                          ),
                        ),
                        const Divider(
                            height: 1, color: AppPalette.borderSoft),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              for (final t in tiers)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 5,
                                        child: Text(
                                          t.range,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: AppPalette.text,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          "${t.price} FCFA",
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w800,
                                            color: AppPalette.text,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 7,
                                                    vertical: 2),
                                            decoration: BoxDecoration(
                                              color: t.discount > 0
                                                  ? AppPalette.successSoft
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      AppRadii.pill),
                                            ),
                                            child: Text(
                                              t.discount > 0
                                                  ? "−${t.discount}%"
                                                  : "—",
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                                color: t.discount > 0
                                                    ? AppPalette.success
                                                    : AppPalette.textFaint,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel(label: "STOCK"),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: _Field(
                        label: "Stock disponible",
                        controller: _stockAvailable,
                        numeric: true,
                      )),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _Field(
                        label: "Stock minimum",
                        controller: _stockReserved,
                        numeric: true,
                      )),
                    ],
                  ),
                ],
              ),
            ),
            _Footer(busy: _busy, onSave: _save, isEdit: _isEdit),
          ],
        ),
      ),
    );
  }
}

class _TierRow {
  const _TierRow({
    required this.range,
    required this.price,
    required this.discount,
  });
  final String range;
  final int price;
  final int discount;
}

class _Header extends StatelessWidget {
  const _Header({required this.isEdit, required this.onBack});
  final bool isEdit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isEdit ? "Éditer le produit" : "Nouveau produit",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const Text(
                  "Catalogue B2B · paliers de prix",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppPalette.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.bgSoft,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppPalette.borderSoft),
              ),
              child: Stack(
                children: [
                  const Center(
                    child: Icon(Icons.image_outlined,
                        size: 36, color: AppPalette.textFaint),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppPalette.primary,
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                      ),
                      child: const Text(
                        "PRIMARY",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.card,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: AppPalette.primary.withValues(alpha: 0.4),
                    width: 1.4,
                    style: BorderStyle.solid,
                  ),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined,
                        size: 26, color: AppPalette.primary),
                    SizedBox(height: 6),
                    Text(
                      "AJOUTER",
                      style: TextStyle(
                        color: AppPalette.primaryDark,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint = "",
    this.numeric = false,
    this.minLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool numeric;
  final int minLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppPalette.textMuted,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          minLines: minLines,
          maxLines: minLines == 1 ? 1 : minLines + 4,
          inputFormatters: numeric
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppPalette.text,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(
      {required this.busy, required this.onSave, required this.isEdit});
  final bool busy;
  final VoidCallback onSave;
  final bool isEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: AppPalette.card,
          boxShadow: AppPalette.shadowFloating,
          border: const Border(
              top: BorderSide(color: AppPalette.borderSoft, width: 1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => Navigator.maybePop(context),
                child: const Text("Annuler"),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: busy ? null : onSave,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check, size: 18),
                  label:
                      Text(isEdit ? "Enregistrer" : "Publier le produit"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

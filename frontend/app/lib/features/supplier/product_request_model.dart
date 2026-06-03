/// C-1 — Single source of truth for the supplier product creation/update
/// payload. Guarantees the Flutter client speaks the exact contract expected by
/// the backend `ProductSerializer`:
///   * `category_name` (not `category`)
///   * `min_order_qty` / `max_order_qty` (not `min_qty` / `max_qty`)
///   * `price_for_min_qty` = unit price at the MINIMUM quantity (low volume,
///     higher price); `price_for_max_qty` = unit price at the MAXIMUM quantity
///     (bulk, lower price). With a volume discount: priceForMinQty >= priceForMaxQty.
///
/// `is_active` is intentionally NOT sent: activation is server-controlled (C-2).
class ProductRequestModel {
  ProductRequestModel({
    required this.title,
    required this.brand,
    required this.categoryName,
    required this.description,
    required this.minOrderQty,
    required this.maxOrderQty,
    required this.priceForMinQty,
    required this.priceForMaxQty,
    required this.weightKg,
    this.availableQty,
  });

  final String title;
  final String brand;
  final String categoryName;
  final String description;
  final int minOrderQty;
  final int maxOrderQty;

  /// Unit price for the minimum quantity (low volume — higher unit price).
  final num priceForMinQty;

  /// Unit price for the maximum quantity (bulk — lower unit price).
  final num priceForMaxQty;
  final num weightKg;
  final int? availableQty;

  /// Returns a user-facing French error string, or `null` when valid.
  /// Mirrors the server-side validation so the user gets instant feedback.
  String? validate() {
    if (title.trim().isEmpty) return "Le nom du produit est obligatoire.";
    if (categoryName.trim().isEmpty) return "La catégorie est obligatoire.";
    if (weightKg <= 0) return "Le poids (kg) doit être supérieur à 0.";
    if (minOrderQty < 1) return "La quantité minimale doit être ≥ 1.";
    if (maxOrderQty < minOrderQty) {
      return "La quantité max doit être ≥ à la quantité min.";
    }
    if (priceForMinQty <= 0 || priceForMaxQty <= 0) {
      return "Les prix doivent être supérieurs à 0.";
    }
    if (priceForMinQty < priceForMaxQty) {
      return "Prix incohérents: le prix au faible volume doit être ≥ au prix de gros.";
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      "title": title.trim(),
      "brand": brand.trim(),
      "category_name": categoryName.trim(),
      "description": description.trim(),
      "min_order_qty": minOrderQty,
      "max_order_qty": maxOrderQty,
      "price_for_min_qty": priceForMinQty,
      "price_for_max_qty": priceForMaxQty,
      "weight_kg": weightKg,
    };
    if (availableQty != null) {
      map["available_qty"] = availableQty;
    }
    return map;
  }
}

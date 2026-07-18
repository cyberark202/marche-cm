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

  final num priceForMinQty;

  final num priceForMaxQty;
  final num weightKg;
  final int? availableQty;

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

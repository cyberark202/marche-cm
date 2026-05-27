import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../feed/feed_models.dart';
import 'buyer_store.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.products});
  final List<ProductCardData> products;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _transportProfiles = const [];
  bool _loadingProfiles = true;

  static const double _platformCommissionRate = 0.025;

  double _shippingRateForItem(CartEntry item) {
    final profile = _transportProfiles.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?["user"] == item.preferredTransitAgentId,
          orElse: () => null,
        );
    if (profile == null) return 0;
    final key =
        item.transportMode == "AIR" ? "air_price_per_kg" : "sea_price_per_kg";
    return double.tryParse("${profile[key] ?? 0}") ?? 0;
  }

  int _unitPrice(ProductCardData product, int quantity) {
    return quantity == product.maxQty ? product.priceMax : product.priceMin;
  }

  int _etaDaysForItem(CartEntry item) {
    final profile = _transportProfiles.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?["user"] == item.preferredTransitAgentId,
          orElse: () => null,
        );
    return int.tryParse("${profile?["average_eta_days"] ?? 0}") ?? 0;
  }

  double _trustForProfile(Map<String, dynamic> profile) {
    return double.tryParse(
            "${profile["trust_score"] ?? profile["rating"] ?? 4.5}") ??
        4.5;
  }

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final token = context.read<SessionStore>().token;
    try {
      _transportProfiles =
          await _api.getList("/api/transport-profiles/", token: token);
    } catch (_) {
      _transportProfiles = const [];
    } finally {
      if (mounted) setState(() => _loadingProfiles = false);
    }
  }

  Future<void> _checkout(BuyerStore store) async {
    final token = context.read<SessionStore>().token;
    final productsById = {for (final p in widget.products) p.id: p};
    for (final entry in store.cartItems) {
      if (entry.preferredTransitAgentId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Sélectionnez un transitaire pour le produit #${entry.productId}.")),
        );
        return;
      }
      if (entry.transportMode != "AIR" && entry.transportMode != "SEA") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Sélectionnez un mode de transport pour le produit #${entry.productId}.")),
        );
        return;
      }
      final product = productsById[entry.productId];
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Produit #${entry.productId} introuvable.")),
        );
        return;
      }
    }

    var itemsCount = 0;
    var productTotal = 0.0;
    var shippingTotal = 0.0;
    var maxEtaDays = 0;
    for (final entry in store.cartItems) {
      final product = productsById[entry.productId];
      if (product == null) continue;
      final unitPrice = _unitPrice(product, entry.quantity);
      final productSubtotal = unitPrice * entry.quantity;
      final shippingRate = _shippingRateForItem(entry);
      final shippingEstimate =
          product.weightKg * entry.quantity * shippingRate;
      productTotal += productSubtotal;
      shippingTotal += shippingEstimate;
      itemsCount += 1;
      final eta = _etaDaysForItem(entry);
      if (eta > maxEtaDays) maxEtaDays = eta;
    }
    final commission =
        (productTotal + shippingTotal) * _platformCommissionRate;
    final grandTotal = productTotal + shippingTotal + commission;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirmer le séquestre"),
        content: Text(
          "Articles : $itemsCount\n"
          "Produits : ${productTotal.toStringAsFixed(0)} FCFA\n"
          "Transport : ${shippingTotal.toStringAsFixed(0)} FCFA\n"
          "Commission : ${commission.toStringAsFixed(0)} FCFA\n"
          "Total à séquestrer : ${grandTotal.toStringAsFixed(0)} FCFA\n"
          "ETA : ${maxEtaDays > 0 ? '$maxEtaDays jour(s)' : 'à confirmer'}",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Séquestrer")),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    var successCount = 0;
    final failures = <String>[];
    for (final entry in store.cartItems) {
      try {
        await _api.post(
          "/api/orders/",
          {
            "product": entry.productId,
            "quantity": entry.quantity,
            "join_grouping": entry.joinGrouping,
            "preferred_transit_agent": entry.preferredTransitAgentId,
            "transport_mode": entry.transportMode,
          },
          token: token,
        );
        successCount += 1;
      } catch (e) {
        failures.add(_api.toUserMessage(
          e,
          fallback: "Échec commande produit #${entry.productId}.",
        ));
      }
    }
    if (!mounted) return;
    if (successCount > 0) store.clearCart();
    final failedCount = failures.length;
    final details = failedCount > 0 ? "\n${failures.first}" : "";
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            "Checkout terminé : $successCount succès, $failedCount échec(s).$details"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BuyerStore>();
    final mapProducts = {for (final p in widget.products) p.id: p};
    final cartItems = store.cartItems;
    final grouped = <int, List<CartEntry>>{};
    final totalQty =
        cartItems.fold<int>(0, (value, item) => value + item.quantity);
    for (final e in cartItems) {
      final sellerId = mapProducts[e.productId]?.sellerId ?? 0;
      grouped.putIfAbsent(sellerId, () => []).add(e);
    }

    var productTotal = 0.0;
    var shippingTotal = 0.0;
    for (final entry in cartItems) {
      final product = mapProducts[entry.productId];
      if (product == null) continue;
      productTotal += _unitPrice(product, entry.quantity) * entry.quantity;
      shippingTotal +=
          product.weightKg * entry.quantity * _shippingRateForItem(entry);
    }
    final commission =
        (productTotal + shippingTotal) * _platformCommissionRate;
    final grandTotal = productTotal + shippingTotal + commission;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: cartItems.isEmpty
            ? _CartEmpty(onShop: () => Navigator.maybePop(context))
            : Column(
                children: [
                  _CartHeader(itemCount: cartItems.length, totalQty: totalQty),
                  Expanded(
                    child: ListView(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        for (final entry in grouped.entries) ...[
                          _SellerHeader(
                              sellerId: entry.key,
                              displayName: () {
                                final product =
                                    mapProducts[entry.value.first.productId];
                                return product?.sellerDisplayName ??
                                    "Fournisseur #${entry.key}";
                              }(),
                              itemCount: entry.value.length),
                          const SizedBox(height: 8),
                          for (final item in entry.value)
                            _CartLineCard(
                              item: item,
                              product: mapProducts[item.productId],
                              transportProfiles: _transportProfiles,
                              loadingProfiles: _loadingProfiles,
                              shippingRate: _shippingRateForItem(item),
                              etaDays: _etaDaysForItem(item),
                              trustForProfile: _trustForProfile,
                              onQty: (v) => store.updateCart(item.productId,
                                  quantity: v),
                              onGrouping: (v) => store.updateCart(
                                  item.productId,
                                  joinGrouping: v),
                              onAgent: (v) => store.updateCart(
                                  item.productId,
                                  preferredTransitAgentId: v,
                                  clearAgent: v == null),
                              onMode: (v) => store.updateCart(
                                  item.productId,
                                  transportMode: v),
                              onRemove: () =>
                                  store.removeFromCart(item.productId),
                            ),
                          const SizedBox(height: 10),
                        ],
                        _EscrowRecap(
                          subtotal: productTotal,
                          shipping: shippingTotal,
                          commission: commission,
                          total: grandTotal,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppPalette.primarySoft,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          child: const Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 18, color: AppPalette.primaryDark),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Séquestre escrow — Les fonds sont bloqués jusqu'à la confirmation de livraison.",
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppPalette.primaryDark,
                                    height: 1.4,
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
      bottomNavigationBar: cartItems.isEmpty
          ? null
          : _CartFooter(
              total: grandTotal,
              onCheckout: () => _checkout(store),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CartHeader extends StatelessWidget {
  const _CartHeader({required this.itemCount, required this.totalQty});
  final int itemCount;
  final int totalQty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  "Panier",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Row(
              children: [
                _HeroChip(
                  label: "$itemCount article${itemCount > 1 ? 's' : ''}",
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(width: 8),
                _HeroChip(
                  label: "$totalQty unité${totalQty > 1 ? 's' : ''}",
                  icon: Icons.numbers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerHeader extends StatelessWidget {
  const _SellerHeader({
    required this.sellerId,
    required this.displayName,
    required this.itemCount,
  });
  final int sellerId;
  final String displayName;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final initials = () {
      final src = displayName.trim();
      if (src.isEmpty) return "·";
      final parts = src.split(RegExp(r"\s+"));
      if (parts.length == 1) {
        return parts.first
            .substring(0, parts.first.length.clamp(0, 2))
            .toUpperCase();
      }
      return (parts[0].isNotEmpty ? parts[0][0] : "") +
          (parts[1].isNotEmpty ? parts[1][0] : "");
    }();

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: AppPalette.gradientPrimary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppPalette.text,
            ),
          ),
        ),
        Text(
          "$itemCount article${itemCount > 1 ? 's' : ''}",
          style: const TextStyle(
            fontSize: 11.5,
            color: AppPalette.textMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.item,
    required this.product,
    required this.transportProfiles,
    required this.loadingProfiles,
    required this.shippingRate,
    required this.etaDays,
    required this.trustForProfile,
    required this.onQty,
    required this.onGrouping,
    required this.onAgent,
    required this.onMode,
    required this.onRemove,
  });

  final CartEntry item;
  final ProductCardData? product;
  final List<Map<String, dynamic>> transportProfiles;
  final bool loadingProfiles;
  final double shippingRate;
  final int etaDays;
  final double Function(Map<String, dynamic>) trustForProfile;
  final ValueChanged<int> onQty;
  final ValueChanged<bool> onGrouping;
  final ValueChanged<int?> onAgent;
  final ValueChanged<String?> onMode;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final unitPrice = p == null
        ? 0
        : (item.quantity == p.maxQty ? p.priceMax : p.priceMin);
    final productSubtotal = unitPrice * item.quantity;
    final shippingEstimate =
        (p?.weightKg ?? 0) * item.quantity * shippingRate;
    final lineTotal = productSubtotal + shippingEstimate;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppPalette.textMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.title ?? "Produit #${item.productId}",
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppPalette.text,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "$unitPrice FCFA / unité · ${item.quantity} unité${item.quantity > 1 ? 's' : ''}",
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppPalette.dangerSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close,
                      size: 16, color: AppPalette.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppPalette.bgSoft,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              children: [
                const Text("Qté",
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12.5)),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 500,
                    value: item.quantity.toDouble().clamp(1, 500),
                    onChanged: (v) => onQty(v.round()),
                  ),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    "${item.quantity}",
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "TRANSITAIRE",
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: AppPalette.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          if (loadingProfiles)
            const LinearProgressIndicator()
          else if (transportProfiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                "Aucun transitaire disponible pour le moment.",
                style: TextStyle(
                    fontSize: 12, color: AppPalette.textMuted),
              ),
            )
          else
            Column(
              children: [
                for (final profile in transportProfiles.take(3))
                  _TransitOption(
                    profile: profile,
                    selected: item.preferredTransitAgentId ==
                        profile["user"],
                    trust: trustForProfile(profile),
                    onSelect: () => onAgent(profile["user"] as int?),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  label: "Avion",
                  icon: Icons.flight,
                  selected: item.transportMode == "AIR",
                  onTap: () => onMode("AIR"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeChip(
                  label: "Bateau",
                  icon: Icons.directions_boat_outlined,
                  selected: item.transportMode == "SEA",
                  onTap: () => onMode("SEA"),
                ),
              ),
            ],
          ),
          if (p?.allowsGrouping ?? false) ...[
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: item.joinGrouping,
              onChanged: (v) => onGrouping(v ?? false),
              title: const Text(
                "Intégrer au regroupage (réduction frais)",
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline,
                    size: 14, color: AppPalette.primaryDark),
                const SizedBox(width: 6),
                const Text(
                  "Sous-total ligne",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.primaryDark,
                  ),
                ),
                const Spacer(),
                Text(
                  "${lineTotal.toStringAsFixed(0)} FCFA",
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.primaryDark,
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

class _TransitOption extends StatelessWidget {
  const _TransitOption({
    required this.profile,
    required this.selected,
    required this.trust,
    required this.onSelect,
  });

  final Map<String, dynamic> profile;
  final bool selected;
  final double trust;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final name = (profile["company_name"] ?? "Transitaire").toString();
    final eta =
        int.tryParse("${profile["average_eta_days"] ?? 0}") ?? 0;
    final airPrice =
        double.tryParse("${profile["air_price_per_kg"] ?? 0}") ?? 0;
    final seaPrice =
        double.tryParse("${profile["sea_price_per_kg"] ?? 0}") ?? 0;
    final priceLabel =
        airPrice > 0 ? "${airPrice.toStringAsFixed(0)} F/kg ✈" : "${seaPrice.toStringAsFixed(0)} F/kg 🚢";

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppPalette.primarySoft : AppPalette.bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? AppPalette.primary : AppPalette.borderSoft,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? AppPalette.primary
                      : AppPalette.borderSoft,
                  width: 2,
                ),
                color: selected ? AppPalette.primary : Colors.transparent,
              ),
              child: selected
                  ? const Icon(Icons.check,
                      color: Colors.white, size: 12)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppPalette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppPalette.accent, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        trust.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        eta > 0 ? "$eta jours" : "ETA à confirmer",
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              priceLabel,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: AppPalette.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppPalette.primary : AppPalette.bg,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? AppPalette.primary : AppPalette.borderSoft,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? Colors.white : AppPalette.textMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppPalette.text,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EscrowRecap extends StatelessWidget {
  const _EscrowRecap({
    required this.subtotal,
    required this.shipping,
    required this.commission,
    required this.total,
  });

  final double subtotal;
  final double shipping;
  final double commission;
  final double total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        children: [
          _RecapLine(label: "Sous-total produits", value: subtotal),
          const SizedBox(height: 6),
          _RecapLine(label: "Transitaire", value: shipping),
          const SizedBox(height: 6),
          _RecapLine(label: "Commission plateforme (2,5%)", value: commission),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: AppPalette.borderSoft),
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Total à séquestrer",
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppPalette.text,
                  ),
                ),
              ),
              Text(
                "${total.toStringAsFixed(0)} FCFA",
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primaryDark,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecapLine extends StatelessWidget {
  const _RecapLine({required this.label, required this.value});
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppPalette.textMuted,
            ),
          ),
        ),
        Text(
          "${value.toStringAsFixed(0)} FCFA",
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppPalette.text,
          ),
        ),
      ],
    );
  }
}

class _CartFooter extends StatelessWidget {
  const _CartFooter({required this.total, required this.onCheckout});
  final double total;
  final VoidCallback onCheckout;

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "TOTAL À SÉQUESTRER",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    "${total.toStringAsFixed(0)} FCFA",
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.primaryDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: onCheckout,
                icon: const Icon(Icons.lock_outline, size: 18),
                label: const Text("Séquestrer & payer"),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartEmpty extends StatelessWidget {
  const _CartEmpty({required this.onShop});
  final VoidCallback onShop;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shopping_cart_outlined,
                  color: AppPalette.primaryDark, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              "Votre panier est vide",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppPalette.text,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Ajoutez des produits depuis le catalogue pour commencer.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppPalette.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onShop,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text("Voir le catalogue"),
            ),
          ],
        ),
      ),
    );
  }
}

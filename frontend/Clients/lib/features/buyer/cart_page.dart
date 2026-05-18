import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_ui.dart';
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
                  "Selectionnez un transitaire pour le produit #${entry.productId}.")),
        );
        return;
      }
      if (entry.transportMode != "AIR" && entry.transportMode != "SEA") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Selectionnez un mode de transport pour le produit #${entry.productId}.")),
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
      final shippingEstimate = product.weightKg * entry.quantity * shippingRate;
      productTotal += productSubtotal;
      shippingTotal += shippingEstimate;
      itemsCount += 1;
      final eta = _etaDaysForItem(entry);
      if (eta > maxEtaDays) {
        maxEtaDays = eta;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Resume avant checkout"),
        content: Text(
          "Articles: $itemsCount\n"
          "Montant produits: ${productTotal.toStringAsFixed(2)} FCFA\n"
          "Transport estime: ${shippingTotal.toStringAsFixed(2)} FCFA\n"
          "Total a payer: ${(productTotal + shippingTotal).toStringAsFixed(2)} FCFA\n"
          "ETA estimee: ${maxEtaDays > 0 ? '$maxEtaDays jour(s)' : 'a confirmer'}",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

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
          fallback: "Echec commande produit #${entry.productId}.",
        ));
      }
    }
    if (!mounted) return;
    if (successCount > 0) {
      store.clearCart();
    }
    final failedCount = failures.length;
    final details = failedCount > 0 ? "\n${failures.first}" : "";
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Checkout termine: $successCount succes, $failedCount echec(s).$details",
        ),
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

    return Scaffold(
      appBar: AppBar(title: const Text("Panier B2B")),
      body: AppPageBackground(
        child: cartItems.isEmpty
            ? const Center(child: Text("Panier vide"))
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const AppHeaderPanel(
                    title: "Panier multi-fournisseurs",
                    subtitle:
                        "Configurez les quantites, transitaires et mode de transport avant checkout.",
                    trailing: Icon(Icons.shopping_cart_checkout_outlined),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppMetricTile(
                          label: "Produits",
                          value: "${cartItems.length}",
                          icon: Icons.inventory_2_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppMetricTile(
                          label: "Quantite totale",
                          value: "$totalQty",
                          icon: Icons.numbers_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final entry in grouped.entries) ...[
                    Text("Fournisseur ${entry.key}",
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    for (final item in entry.value)
                      AppSectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                mapProducts[item.productId]?.title ??
                                    "Produit #${item.productId}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text("Qté"),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Slider(
                                    min: 1,
                                    max: 200,
                                    value:
                                        item.quantity.toDouble().clamp(1, 200),
                                    onChanged: (v) => store.updateCart(
                                        item.productId,
                                        quantity: v.round()),
                                  ),
                                ),
                                Text(item.quantity.toString()),
                              ],
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: item.joinGrouping,
                              onChanged: (v) => store.updateCart(item.productId,
                                  joinGrouping: v ?? false),
                              title: const Text("Intégrer au regroupage"),
                            ),
                            if (_loadingProfiles)
                              const LinearProgressIndicator()
                            else
                              DropdownButtonFormField<int>(
                                initialValue: item.preferredTransitAgentId,
                                decoration: const InputDecoration(
                                    labelText: "Transitaire souhaité"),
                                items: _transportProfiles
                                    .map((e) => DropdownMenuItem<int>(
                                        value: e["user"] as int?,
                                        child: Text(
                                            "${e["company_name"]} (${e["user"]})")))
                                    .toList(),
                                onChanged: (v) => store.updateCart(
                                    item.productId,
                                    preferredTransitAgentId: v,
                                    clearAgent: v == null),
                              ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: item.transportMode,
                              decoration: const InputDecoration(
                                  labelText: "Mode de transport"),
                              items: const [
                                DropdownMenuItem(
                                    value: "AIR", child: Text("Avion")),
                                DropdownMenuItem(
                                    value: "SEA", child: Text("Bateau")),
                              ],
                              onChanged: (v) => store.updateCart(
                                item.productId,
                                transportMode: v,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Builder(
                              builder: (_) {
                                final product = mapProducts[item.productId];
                                if (product == null) {
                                  return const SizedBox.shrink();
                                }
                                final unitPrice =
                                    _unitPrice(product, item.quantity);
                                final productSubtotal =
                                    unitPrice * item.quantity;
                                final shippingRate = _shippingRateForItem(item);
                                final shippingEstimate = product.weightKg *
                                    item.quantity *
                                    shippingRate;
                                final totalPayable =
                                    productSubtotal + shippingEstimate;
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: const Color(0xFFE5E7EB)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          "Montant produit: ${productSubtotal.toStringAsFixed(2)} FCFA"),
                                      Text(
                                          "Frais transport estimés: ${shippingEstimate.toStringAsFixed(2)} FCFA"),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Total à payer: ${totalPayable.toStringAsFixed(2)} FCFA",
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    store.removeFromCart(item.productId),
                                child: const Text("Retirer",
                                    style: TextStyle(color: Color(0xFFDC2626))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: cartItems.isEmpty ? null : () => _checkout(store),
          icon: const Icon(Icons.payments_outlined),
          label: const Text("Checkout multi-fournisseurs"),
        ),
      ),
    );
  }
}

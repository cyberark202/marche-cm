import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/cm_components.dart';
import '../auth/session_store.dart';
import '../feed/feed_models.dart';
import 'buyer_store.dart';
import 'package:lucide_icons/lucide_icons.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key, required this.products});
  final List<ProductCardData> products;

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final ApiService _api = ApiService();
  bool _submitting = false;

  int _unitPrice(ProductCardData product, int quantity) {
    return quantity == product.maxQty ? product.priceMax : product.priceMin;
  }

  Future<void> _checkout(BuyerStore store) async {
    if (_submitting) return;
    final token = context.read<SessionStore>().token;
    final productsById = {for (final p in widget.products) p.id: p};
    for (final entry in store.cartItems) {
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
    for (final entry in store.cartItems) {
      final product = productsById[entry.productId];
      if (product == null) continue;
      productTotal += _unitPrice(product, entry.quantity) * entry.quantity;
      itemsCount += 1;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirmer le séquestre"),
        content: Text(
          "Articles : $itemsCount\n"
          "Produits : ${productTotal.toStringAsFixed(0)} FCFA\n"
          "Livraison : calculée à la commande (150 FCFA/km, selon la distance)\n\n"
          "Vous mandatez Marché CM pour séquestrer le prix des produits et les "
          "frais de livraison via le prestataire de paiement agréé, et les "
          "libérer à la confirmation de livraison. Marché CM est intermédiaire "
          "et n'est pas partie au contrat de vente.",
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
    setState(() => _submitting = true);

    try {
      for (final entry in store.cartItems) {
        await _api.post(
          "/api/cart/",
          {"product": entry.productId, "quantity": entry.quantity},
          token: token,
        );
      }
      final result = await _api.post("/api/cart/checkout/", {}, token: token);
      if (!mounted) return;
      final count = (result["count"] ?? 0) as int;
      store.clearCart();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Séquestre confirmé : $count commande(s) créée(s).")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_api.toUserMessage(
            e,
            fallback: "Échec du séquestre. Aucune commande créée, réessayez.",
          )),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
    for (final entry in cartItems) {
      final product = mapProducts[entry.productId];
      if (product == null) continue;
      productTotal += _unitPrice(product, entry.quantity) * entry.quantity;
    }
    final grandTotal = productTotal;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: CmResponsive.center(
        maxWidth: 820,
        child: SafeArea(
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
                              onQty: (v) => store.updateCart(item.productId,
                                  quantity: v),
                              onGrouping: (v) => store.updateCart(
                                  item.productId,
                                  joinGrouping: v),
                              onRemove: () =>
                                  store.removeFromCart(item.productId),
                            ),
                          const SizedBox(height: 10),
                        ],
                        _EscrowRecap(
                          subtotal: productTotal,
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
                              Icon(LucideIcons.lock,
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
      ),
      bottomNavigationBar: cartItems.isEmpty
          ? null
          : _CartFooter(
              total: grandTotal,
              submitting: _submitting,
              onCheckout: () => _checkout(store),
            ),
    );
  }
}


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
                icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
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
                  icon: LucideIcons.package,
                ),
                const SizedBox(width: 8),
                _HeroChip(
                  label: "$totalQty unité${totalQty > 1 ? 's' : ''}",
                  icon: LucideIcons.hash,
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
    required this.onQty,
    required this.onGrouping,
    required this.onRemove,
  });

  final CartEntry item;
  final ProductCardData? product;
  final ValueChanged<int> onQty;
  final ValueChanged<bool> onGrouping;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final unitPrice = p == null
        ? 0
        : (item.quantity == p.maxQty ? p.priceMax : p.priceMin);
    final lineTotal = unitPrice * item.quantity;

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
                child: const Icon(LucideIcons.package,
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
                  child: const Icon(LucideIcons.x,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppPalette.bgSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: const Row(
              children: [
                Icon(LucideIcons.truck,
                    size: 15, color: AppPalette.textMuted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Livraison calculée à la commande (150 FCFA/km, selon la distance). Le livreur est assigné après l'achat.",
                    style: TextStyle(
                        fontSize: 11.5,
                        color: AppPalette.textMuted,
                        fontWeight: FontWeight.w500,
                        height: 1.35),
                  ),
                ),
              ],
            ),
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
                const Icon(LucideIcons.lock,
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

class _EscrowRecap extends StatelessWidget {
  const _EscrowRecap({
    required this.subtotal,
    required this.total,
  });

  final double subtotal;
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
          const Text(
            "Livraison : 150 FCFA/km (selon la distance) ajoutée à la commande. "
            "Commission plateforme prélevée côté vendeur/livreur — non incluse.",
            style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: AppPalette.textMuted,
            ),
          ),
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
  const _CartFooter({
    required this.total,
    required this.onCheckout,
    this.submitting = false,
  });
  final double total;
  final VoidCallback onCheckout;
  final bool submitting;

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
                onPressed: submitting ? null : onCheckout,
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.lock, size: 18),
                label: Text(submitting ? "Traitement…" : "Séquestrer & payer"),
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
              decoration: const BoxDecoration(
                color: AppPalette.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.shoppingCart,
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
              icon: const Icon(LucideIcons.store),
              label: const Text("Voir le catalogue"),
            ),
          ],
        ),
      ),
    );
  }
}

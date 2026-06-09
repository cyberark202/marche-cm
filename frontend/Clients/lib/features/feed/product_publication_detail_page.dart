import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../auth/session_store.dart';
import '../chat/chat_hub_page.dart';
import 'feed_models.dart';

class ProductPublicationDetailPage extends StatefulWidget {
  const ProductPublicationDetailPage({super.key, required this.product});

  final ProductCardData product;

  @override
  State<ProductPublicationDetailPage> createState() =>
      _ProductPublicationDetailPageState();
}

class _ProductPublicationDetailPageState
    extends State<ProductPublicationDetailPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _certifications = const [];
  Map<String, dynamic> _reviewsPayload = const {};
  bool _contacting = false;

  @override
  void initState() {
    super.initState();
    _loadCertifications();
    _loadReviews();
  }

  Future<void> _loadCertifications() async {
    final token = context.read<SessionStore>().token;
    try {
      final certs = await _api.getList(
          "/api/compliance-documents/?user_id=${widget.product.sellerId}",
          token: token);
      if (mounted) setState(() => _certifications = certs);
    } catch (_) {
      if (mounted) setState(() => _certifications = const []);
    }
  }

  Future<void> _loadReviews() async {
    final token = context.read<SessionStore>().token;
    try {
      final reviews = await _api.getObject(
        "/api/products/${widget.product.id}/reviews/",
        token: token,
      );
      if (!mounted) return;
      setState(() => _reviewsPayload = reviews);
    } catch (_) {
      if (!mounted) return;
      setState(() => _reviewsPayload = const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final avgRating =
        double.tryParse("${_reviewsPayload["average_rating"] ?? 0}") ?? 0;
    final reviewsCount =
        int.tryParse("${_reviewsPayload["reviews_count"] ?? 0}") ?? 0;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: CustomScrollView(
        slivers: [
          _ProductHeroSliver(product: p),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      const _MetaPill(
                          icon: Icons.workspace_premium_outlined,
                          label: "GROS B2B",
                          tone: _PillTone.primary),
                      _MetaPill(
                          icon: Icons.public,
                          label:
                              "ORIGINE ${p.sellerCountryCode.isEmpty ? "CM" : p.sellerCountryCode.toUpperCase()}",
                          tone: _PillTone.neutral),
                      if (p.allowsGrouping)
                        const _MetaPill(
                            icon: Icons.merge_type,
                            label: "REGROUPAGE",
                            tone: _PillTone.accent),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    p.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      letterSpacing: -0.3,
                      color: AppPalette.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppPalette.accent, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        avgRating > 0
                            ? avgRating.toStringAsFixed(1)
                            : p.sellerTrustScore.toStringAsFixed(1),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "· $reviewsCount avis",
                        style: const TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 10),
                      const _Bullet(),
                      const SizedBox(width: 10),
                      Text(
                        p.category,
                        style: const TextStyle(
                            color: AppPalette.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SupplierCard(product: p),
                  const SizedBox(height: AppSpacing.md),
                  _PricingTiersCard(product: p),
                  const SizedBox(height: AppSpacing.md),
                  _DescriptionCard(description: p.description),
                  const SizedBox(height: AppSpacing.md),
                  _CertificationsCard(certifications: _certifications),
                  const SizedBox(height: AppSpacing.md),
                  _ReviewsCard(payload: _reviewsPayload),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _StickyBottomBar(
        product: p,
        contacting: _contacting,
        onBuy: () => _openOrderSheet(context),
        onContact: _contactSeller,
      ),
    );
  }

  Future<void> _contactSeller() async {
    final token = context.read<SessionStore>().token;
    if (token == null || token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Connectez-vous pour contacter le fournisseur.")),
      );
      return;
    }

    setState(() => _contacting = true);
    try {
      final payload = await _api.post(
        "/api/products/${widget.product.id}/contact-seller/",
        const {},
        token: token,
      );
      final roomId = int.tryParse("${payload["room_id"] ?? ""}");
      if (!mounted) return;
      if (roomId == null) {
        throw Exception("Salon de discussion introuvable.");
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text("Discussions")),
            body: ChatHubPage(initialRoomId: roomId),
          ),
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Le fournisseur a reçu votre message d'intérêt.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Impossible de contacter le fournisseur."))),
      );
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  void _openOrderSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (_) => _OrderSheet(product: widget.product),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HERO — image plein cadre + bouton retour rond + indicateur favori
// ─────────────────────────────────────────────────────────────────────────────

class _ProductHeroSliver extends StatelessWidget {
  const _ProductHeroSliver({required this.product});
  final ProductCardData product;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 320,
      backgroundColor: AppPalette.primaryDark,
      foregroundColor: Colors.white,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _GlassIconButton(
          icon: Icons.arrow_back,
          onTap: () => Navigator.maybePop(context),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _GlassIconButton(
            icon: Icons.share_outlined,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Lien produit copié.")),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
          child: _GlassIconButton(
            icon: Icons.favorite_border,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Ajouté aux favoris.")),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (product.imageUrl.trim().isEmpty)
              Container(color: AppPalette.primaryDark)
            else
              CachedNetworkImage(
                imageUrl: product.imageUrl,
                fit: BoxFit.cover,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                errorWidget: (_, __, ___) =>
                    Container(color: AppPalette.primaryDark),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Color(0xCC0F1F1A),
                    Color(0x66000000),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Positioned(
              left: 18,
              bottom: 18,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      product.referenceCode.isEmpty
                          ? "PRD-${product.id}"
                          : product.referenceCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, color: Colors.white, size: 19),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CARTE FOURNISSEUR
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.product});
  final ProductCardData product;

  @override
  Widget build(BuildContext context) {
    final initials = () {
      final src = product.sellerDisplayName.trim();
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppPalette.gradientPrimary,
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: AppPalette.shadowSoft,
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        product.sellerDisplayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppPalette.text,
                        ),
                      ),
                    ),
                    if (product.sellerVerified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppPalette.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                size: 11, color: AppPalette.primaryDark),
                            SizedBox(width: 2),
                            Text(
                              "KYC",
                              style: TextStyle(
                                color: AppPalette.primaryDark,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  () {
                    final loc = product.sellerCity.trim().isNotEmpty
                        ? product.sellerCity
                        : product.sellerLocationLabel;
                    final base = loc.isEmpty ? "Fournisseur" : "Grossiste · $loc";
                    return "$base · Réponse rapide";
                  }(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppPalette.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: null,
            tooltip: "Discuter",
            icon: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  color: AppPalette.primaryDark, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PALIERS DE PRIX B2B
// ─────────────────────────────────────────────────────────────────────────────

class _PricingTiersCard extends StatelessWidget {
  const _PricingTiersCard({required this.product});
  final ProductCardData product;

  List<_Tier> _buildTiers() {
    final priceTop = product.priceMax;
    final priceBot = product.priceMin;
    final qtyMin = product.minQty;
    final qtyMax = product.maxQty;

    if (priceTop <= 0 || qtyMax <= qtyMin || qtyMin <= 0) {
      return [
        _Tier(
            range: "À partir de $qtyMin",
            price: priceTop > 0 ? priceTop : priceBot,
            discount: 0),
      ];
    }
    final span = qtyMax - qtyMin;
    final t1Max = (qtyMin + span * 0.25).round();
    final t2Max = (qtyMin + span * 0.7).round();
    final p1 = priceTop;
    final p2 = ((priceTop + priceBot) ~/ 2);
    final p3 = priceBot;
    final disc2 = priceTop > 0 ? (100 - (p2 * 100 / priceTop)).round() : 0;
    final disc3 = priceTop > 0 ? (100 - (p3 * 100 / priceTop)).round() : 0;
    return [
      _Tier(range: "$qtyMin – $t1Max", price: p1, discount: 0),
      _Tier(range: "${t1Max + 1} – $t2Max", price: p2, discount: disc2),
      _Tier(range: "${t2Max + 1} – $qtyMax", price: p3, discount: disc3),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tiers = _buildTiers();
    final fromPrice = product.priceMin;
    final hasRange = product.priceMax > product.priceMin;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "PRIX À PARTIR DE",
            style: TextStyle(
              fontSize: 10,
              color: AppPalette.textMuted,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "$fromPrice",
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppPalette.primaryDark,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  "FCFA / unité",
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (hasRange) ...[
            const SizedBox(height: 4),
            Text(
              "Fourchette : ${product.priceMin} – ${product.priceMax} FCFA",
              style: const TextStyle(
                  fontSize: 12, color: AppPalette.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: AppPalette.bgSoft,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Column(
              children: [
                for (var i = 0; i < tiers.length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1,
                        thickness: 1,
                        color: AppPalette.borderSoft),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text(
                            "${tiers[i].range} unités",
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
                            "${tiers[i].price} FCFA",
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: tiers[i].discount > 0
                                    ? AppPalette.successSoft
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Text(
                                tiers[i].discount > 0
                                    ? "−${tiers[i].discount}%"
                                    : "—",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: tiers[i].discount > 0
                                      ? AppPalette.primaryDark
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tier {
  const _Tier({
    required this.range,
    required this.price,
    required this.discount,
  });
  final String range;
  final int price;
  final int discount;
}

// ─────────────────────────────────────────────────────────────────────────────
// DESCRIPTION
// ─────────────────────────────────────────────────────────────────────────────

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.description});
  final String description;

  @override
  Widget build(BuildContext context) {
    final txt = description.trim().isEmpty
        ? "Aucune description détaillée fournie par le fournisseur."
        : description;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Description",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppPalette.text,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            txt,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppPalette.text,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CERTIFICATIONS (logique préservée, visuel raffiné)
// ─────────────────────────────────────────────────────────────────────────────

class _CertificationsCard extends StatelessWidget {
  const _CertificationsCard({required this.certifications});
  final List<Map<String, dynamic>> certifications;

  String _resolveUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return "";
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return value;
    }
    final normalized = value.startsWith("/") ? value : "/$value";
    return "${AppConfig.apiBaseUrl}$normalized";
  }

  bool _looksLikeImage(String raw) {
    final value = raw.toLowerCase();
    return value.endsWith(".png") ||
        value.endsWith(".jpg") ||
        value.endsWith(".jpeg") ||
        value.endsWith(".webp") ||
        value.endsWith(".gif") ||
        value.endsWith(".bmp");
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppPalette.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Icons.workspace_premium,
                    color: AppPalette.primaryDark, size: 17),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "Certifications visibles",
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppPalette.text,
                  ),
                ),
              ),
              Text(
                "${certifications.length}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (certifications.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppPalette.bgSoft,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Text(
                "Aucune certification approuvée pour ce fournisseur.",
                style: TextStyle(
                    fontSize: 12.5, color: AppPalette.textMuted),
              ),
            ),
          for (final c in certifications)
            Container(
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: AppPalette.bg,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: AppPalette.borderSoft),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(builder: (_) {
                    final previewUrl =
                        _resolveUrl((c["preview_url"] ?? "").toString());
                    final fileUrl = _resolveUrl(
                        (c["file_url"] ?? c["file"] ?? "").toString());
                    final imageUrl = previewUrl.isNotEmpty
                        ? previewUrl
                        : (_looksLikeImage(fileUrl) ? fileUrl : "");
                    if (imageUrl.isEmpty) {
                      return Container(
                        height: 96,
                        width: double.infinity,
                        decoration: const BoxDecoration(
                          color: AppPalette.bgSoft,
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(AppRadii.md)),
                        ),
                        child: const Center(
                          child: Icon(Icons.description_outlined,
                              color: AppPalette.textMuted),
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadii.md)),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          height: 96,
                          color: AppPalette.bgSoft,
                          alignment: Alignment.center,
                          child: const Text("Aperçu indisponible"),
                        ),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_outlined,
                            color: AppPalette.success, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            (c["doc_type"] ?? "").toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: AppPalette.text,
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AVIS (logique préservée)
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewsCard extends StatelessWidget {
  const _ReviewsCard({required this.payload});
  final Map<String, dynamic> payload;

  @override
  Widget build(BuildContext context) {
    final average = double.tryParse("${payload["average_rating"] ?? 0}") ?? 0;
    final count = int.tryParse("${payload["reviews_count"] ?? 0}") ?? 0;
    final rows = ((payload["reviews"] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
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
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppPalette.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppPalette.accent, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      average.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: AppPalette.accentDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "Avis vérifiés · $count",
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: AppPalette.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text(
              "Aucun avis vérifié pour ce produit.",
              style: TextStyle(
                  fontSize: 12.5, color: AppPalette.textMuted),
            )
          else
            ...rows.take(3).map(
                  (row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              "${row["buyer_username"] ?? "Acheteur"}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.star_rounded,
                                size: 13, color: AppPalette.accent),
                            const SizedBox(width: 2),
                            Text(
                              "${row["rating"] ?? "-"}",
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (row["comment"] ?? "").toString().trim().isEmpty
                              ? "Aucun commentaire."
                              : (row["comment"] ?? "").toString(),
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppPalette.text,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA bottom
// ─────────────────────────────────────────────────────────────────────────────

class _StickyBottomBar extends StatelessWidget {
  const _StickyBottomBar({
    required this.product,
    required this.contacting,
    required this.onBuy,
    required this.onContact,
  });

  final ProductCardData product;
  final bool contacting;
  final VoidCallback onBuy;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: AppPalette.shadowFloating,
          border: const Border(
              top: BorderSide(color: AppPalette.borderSoft, width: 1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BuyEscrowNote(),
            const SizedBox(height: 8),
            Row(
              children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "À partir de",
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppPalette.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  Text(
                    "${product.priceMin} FCFA",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.primaryDark,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: contacting ? null : onContact,
                icon: contacting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.chat_bubble_outline, size: 18),
                label: Text(contacting ? "..." : "Chat"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.primaryDark,
                  side: const BorderSide(
                      color: AppPalette.primary, width: 1.4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: onBuy,
                icon: const Icon(Icons.shopping_bag, size: 18),
                label: const Text("Acheter"),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 0),
                ),
              ),
            ),
          ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyEscrowNote extends StatelessWidget {
  const _BuyEscrowNote();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.shield_outlined, size: 13, color: AppPalette.textMuted),
        SizedBox(width: 6),
        Expanded(
          child: Text(
            "Paiement sous séquestre. Marché CM est intermédiaire : le contrat de vente vous lie directement au vendeur.",
            style: TextStyle(
                fontSize: 10.5, color: AppPalette.textMuted, height: 1.3),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// META PILLS
// ─────────────────────────────────────────────────────────────────────────────

enum _PillTone { primary, neutral, accent }

class _MetaPill extends StatelessWidget {
  const _MetaPill(
      {required this.icon, required this.label, required this.tone});
  final IconData icon;
  final String label;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (tone) {
      case _PillTone.primary:
        bg = AppPalette.primarySoft;
        fg = AppPalette.primaryDark;
      case _PillTone.neutral:
        bg = AppPalette.bgSoft;
        fg = AppPalette.text;
      case _PillTone.accent:
        bg = AppPalette.accentSoft;
        fg = AppPalette.accentDark;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: AppPalette.textFaint,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER SHEET (logique 1:1 préservée, visuel raffiné)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.product});
  final ProductCardData product;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final ApiService _api = ApiService();
  final TextEditingController _quantityController = TextEditingController();
  bool _joinGrouping = false;
  int? _transitAgentId;
  String _transportMode = "AIR";
  List<Map<String, dynamic>> _transportProfiles = const [];
  bool _loadingProfiles = true;

  @override
  void initState() {
    super.initState();
    _quantityController.text = widget.product.minQty.toString();
    _loadProfiles();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final token = context.read<SessionStore>().token;
    try {
      _transportProfiles =
          await _api.getList("/api/transport-profiles/", token: token);
      if (_transitAgentId == null && _transportProfiles.isNotEmpty) {
        _transitAgentId = _transportProfiles.first["user"] as int?;
      }
    } catch (_) {
      _transportProfiles = const [];
    }
    if (mounted) setState(() => _loadingProfiles = false);
  }

  Future<void> _submitOrder() async {
    final token = context.read<SessionStore>().token;
    final qty = int.tryParse(_quantityController.text.trim()) ?? 0;
    if (_transitAgentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Sélectionnez un transitaire.")),
      );
      return;
    }
    try {
      await _api.post(
        "/api/orders/",
        {
          "product": widget.product.id,
          "quantity": qty,
          "join_grouping": _joinGrouping,
          "preferred_transit_agent": _transitAgentId,
          "transport_mode": _transportMode,
        },
        token: token,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "Commande créée : ${widget.product.title} (ID ${widget.product.id})")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _api.toUserMessage(e,
                fallback:
                    "Échec commande. Vérifiez quantité, regroupage et transitaire."),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final qty = int.tryParse(_quantityController.text.trim()) ?? p.minQty;
    final unitPrice = qty == p.maxQty ? p.priceMax : p.priceMin;
    final productSubtotal = (qty <= 0 ? 0 : qty) * unitPrice;
    final selectedProfile =
        _transportProfiles.cast<Map<String, dynamic>?>().firstWhere(
              (profile) => profile?["user"] == _transitAgentId,
              orElse: () => null,
            );
    final shippingRate = (() {
      if (selectedProfile == null) return 0.0;
      final key =
          _transportMode == "AIR" ? "air_price_per_kg" : "sea_price_per_kg";
      return double.tryParse("${selectedProfile[key] ?? 0}") ?? 0;
    })();
    final shippingEstimate = ((p.weightKg > 0 ? p.weightKg : 0) *
        (qty <= 0 ? 0 : qty) *
        shippingRate);
    final payableTotal = productSubtotal + shippingEstimate;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppPalette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              "Commande — ${p.title}",
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: AppPalette.text),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: "Quantité (${p.minQty}–${p.maxQty})",
                prefixIcon: const Icon(Icons.numbers),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _transportMode,
              items: const [
                DropdownMenuItem(value: "AIR", child: Text("Transport — Avion")),
                DropdownMenuItem(value: "SEA", child: Text("Transport — Bateau")),
              ],
              onChanged: (value) =>
                  setState(() => _transportMode = value ?? _transportMode),
              decoration: const InputDecoration(
                labelText: "Mode de transport",
                prefixIcon: Icon(Icons.local_shipping_outlined),
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingProfiles)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _transitAgentId,
                items: _transportProfiles
                    .map(
                      (profile) => DropdownMenuItem<int>(
                        value: profile["user"] as int?,
                        child: Text(
                            "${profile["company_name"]} (agent ${profile["user"]})"),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _transitAgentId = v),
                decoration: const InputDecoration(
                  labelText: "Transitaire souhaité",
                  prefixIcon: Icon(Icons.directions_boat_outlined),
                ),
              ),
            const SizedBox(height: 10),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _joinGrouping,
              onChanged: p.allowsGrouping
                  ? (v) => setState(() => _joinGrouping = v ?? false)
                  : null,
              title: Text(p.allowsGrouping
                  ? "Intégrer au regroupage"
                  : "Regroupage non disponible"),
              dense: true,
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RecapRow(
                      label: "Montant produit",
                      value: "${productSubtotal.toStringAsFixed(2)} FCFA"),
                  const SizedBox(height: 4),
                  _RecapRow(
                      label: "Transport estimé",
                      value: "${shippingEstimate.toStringAsFixed(2)} FCFA"),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child:
                        Divider(height: 1, color: AppPalette.borderSoft),
                  ),
                  _RecapRow(
                    label: "Total à séquestrer",
                    value: "${payableTotal.toStringAsFixed(2)} FCFA",
                    emphasis: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Annuler"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _submitOrder,
                    icon: const Icon(Icons.lock_outline, size: 18),
                    label: const Text("Séquestrer"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecapRow extends StatelessWidget {
  const _RecapRow({
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: emphasis ? 13.5 : 12.5,
              fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
              color: emphasis ? AppPalette.text : AppPalette.textMuted,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: emphasis ? 15 : 13,
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w700,
            color: emphasis ? AppPalette.primaryDark : AppPalette.text,
          ),
        ),
      ],
    );
  }
}

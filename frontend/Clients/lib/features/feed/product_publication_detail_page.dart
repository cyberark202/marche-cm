import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
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
      if (mounted) {
        setState(() => _certifications = const []);
      }
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
    final product = widget.product;
    return Scaffold(
      appBar: AppBar(title: const Text("Détails de publication")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
                aspectRatio: 1.3,
                child: Image.network(product.imageUrl, fit: BoxFit.cover)),
          ),
          const SizedBox(height: 14),
          Text(product.title,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(product.description.isEmpty
              ? "Aucune description détaillée fournie."
              : product.description),
          const SizedBox(height: 16),
          _InfoCard(
            title: "Informations produit",
            rows: [
              "Catégorie: ${product.category}",
              "Marque: ${product.brand}",
              "Quantité min-max: ${product.minQty} - ${product.maxQty}",
              "Prix min (petite qté): ${product.priceMin} FCFA",
              "Prix max (grosse qté): ${product.priceMax} FCFA",
              "Poids: ${product.weightKg > 0 ? product.weightKg.toStringAsFixed(3) : "-"} Kg",
              "Reference publication: ${product.referenceCode.isEmpty ? "PRD-${product.id}" : product.referenceCode}",
            ],
          ),
          const SizedBox(height: 12),
          _SupplierCard(
            sellerId: product.sellerId,
            sellerReferenceCode: product.sellerReferenceCode,
            displayName: product.sellerDisplayName,
            avatarUrl: product.sellerAvatarUrl,
            countryCode: product.sellerCountryCode,
            city: product.sellerCity,
            locationLabel: product.sellerLocationLabel,
            verified: product.sellerVerified,
            trustScore: product.sellerTrustScore,
          ),
          const SizedBox(height: 12),
          _CertificationsCard(certifications: _certifications),
          const SizedBox(height: 12),
          _ReviewsCard(payload: _reviewsPayload),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _openOrderSheet(context),
                  icon: const Icon(Icons.shopping_bag_outlined),
                  label: const Text("Commander"),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _contacting ? null : _contactSeller,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(_contacting ? "Envoi..." : "Contacter"),
                ),
              ),
            ],
          )
        ],
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
            content: Text("Le fournisseur a recu votre message d'interet.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Impossible de contacter le fournisseur."))),
      );
    } finally {
      if (mounted) {
        setState(() => _contacting = false);
      }
    }
  }

  void _openOrderSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _OrderSheet(product: widget.product),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});
  final String title;
  final List<String> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
                padding: const EdgeInsets.only(bottom: 6), child: Text(row)),
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.sellerId,
    required this.sellerReferenceCode,
    required this.displayName,
    required this.avatarUrl,
    required this.countryCode,
    required this.city,
    required this.locationLabel,
    required this.verified,
    required this.trustScore,
  });

  final int sellerId;
  final String sellerReferenceCode;
  final String displayName;
  final String avatarUrl;
  final String countryCode;
  final String city;
  final String locationLabel;
  final bool verified;
  final double trustScore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFEFFCF1),
          borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarUrl.trim().isEmpty
                ? NetworkImage("https://i.pravatar.cc/200?u=$sellerId")
                : NetworkImage(avatarUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  "Fournisseur ${sellerReferenceCode.isEmpty ? "USR-$sellerId" : sellerReferenceCode} • $countryCode",
                ),
                if (city.trim().isNotEmpty ||
                    locationLabel.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    city.trim().isNotEmpty
                        ? "Localisation: $city"
                        : "Localisation: $locationLabel",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 3),
                Text("Trust score: $trustScore/5"),
              ],
            ),
          ),
          Icon(verified ? Icons.verified : Icons.warning_amber_rounded,
              color:
                  verified ? const Color(0xFF16A34A) : const Color(0xFFF59E0B))
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Certifications visibles",
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text("Aperçu: première page validée",
              style: TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 8),
          if (certifications.isEmpty)
            const Text("Aucune certification approuvée."),
          for (final c in certifications)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (_) {
                      final previewUrl =
                          _resolveUrl((c["preview_url"] ?? "").toString());
                      final fileUrl = _resolveUrl(
                          (c["file_url"] ?? c["file"] ?? "").toString());
                      final imageUrl = previewUrl.isNotEmpty
                          ? previewUrl
                          : (_looksLikeImage(fileUrl) ? fileUrl : "");
                      if (imageUrl.isEmpty) {
                        return Container(
                          height: 110,
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF3F4F6),
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.description_outlined,
                                  color: Color(0xFF6B7280)),
                              SizedBox(width: 8),
                              Text("Aperçu indisponible"),
                            ],
                          ),
                        );
                      }
                      return ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        child: Image.network(
                          imageUrl,
                          height: 130,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, _, __) => Container(
                            height: 110,
                            color: const Color(0xFFF3F4F6),
                            alignment: Alignment.center,
                            child: const Text("Erreur chargement aperçu"),
                          ),
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    child: Row(
                      children: [
                        const Icon(Icons.workspace_premium,
                            color: Color(0xFF16A34A), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            (c["doc_type"] ?? "").toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                "Avis verifies: ${average.toStringAsFixed(1)}/5 ($count)",
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            const Text("Aucun avis verifie pour ce produit.")
          else
            ...rows.take(3).map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${row["buyer_username"] ?? "Acheteur"} • ${row["rating"] ?? "-"} / 5",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (row["comment"] ?? "").toString().trim().isEmpty
                              ? "Aucun commentaire"
                              : (row["comment"] ?? "").toString(),
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
        const SnackBar(content: Text("Selectionnez un transitaire.")),
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
                "Commande créée: ${widget.product.title} (ID backend: ${widget.product.id})")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _api.toUserMessage(
              e,
              fallback:
                  "Echec commande. Verifiez quantite, regroupage et transitaire.",
            ),
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
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Commande produit: ${p.title}",
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text("Nom produit (frontend): ${p.title}"),
          Text("ID produit (backend): ${p.id}"),
          const SizedBox(height: 10),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: "Quantité (${p.minQty}-${p.maxQty})",
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _joinGrouping,
            onChanged: p.allowsGrouping
                ? (v) => setState(() => _joinGrouping = v ?? false)
                : null,
            title: Text(p.allowsGrouping
                ? "Intégrer au regroupage"
                : "Regroupage non disponible"),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _transportMode,
            items: const [
              DropdownMenuItem(
                  value: "AIR", child: Text("Transport par avion")),
              DropdownMenuItem(
                  value: "SEA", child: Text("Transport par bateau")),
            ],
            onChanged: (value) =>
                setState(() => _transportMode = value ?? _transportMode),
            decoration: const InputDecoration(
              labelText: "Mode de transport",
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingProfiles)
            const LinearProgressIndicator()
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
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    "Montant produit: ${productSubtotal.toStringAsFixed(2)} FCFA"),
                Text(
                    "Frais transport estimés: ${shippingEstimate.toStringAsFixed(2)} FCFA"),
                const SizedBox(height: 4),
                Text(
                  "Total à payer: ${payableTotal.toStringAsFixed(2)} FCFA",
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Annuler"))),
              const SizedBox(width: 8),
              Expanded(
                  child: FilledButton(
                      onPressed: _submitOrder,
                      child: const Text("Valider commande"))),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

class InnovationHubPage extends StatefulWidget {
  const InnovationHubPage({super.key});

  @override
  State<InnovationHubPage> createState() => _InnovationHubPageState();
}

class _InnovationHubPageState extends State<InnovationHubPage> {
  final ApiService _api = ApiService();

  final TextEditingController _orderId = TextEditingController();
  final TextEditingController _rfqId = TextEditingController();
  final TextEditingController _offerId = TextEditingController();
  final TextEditingController _counterPrice =
      TextEditingController(text: "1000");
  final TextEditingController _counterLead = TextEditingController(text: "3");
  final TextEditingController _counterNote = TextEditingController();
  final TextEditingController _productId = TextEditingController();
  final TextEditingController _alertProductId = TextEditingController();
  final TextEditingController _variantsJson =
      TextEditingController(text: '["taille:S","taille:M","taille:L"]');
  final TextEditingController _bundlesJson =
      TextEditingController(text: '["pack x5","pack x10"]');
  final TextEditingController _alertTargetPrice =
      TextEditingController(text: "900");
  final TextEditingController _shipmentId = TextEditingController();
  final TextEditingController _disputeId = TextEditingController();
  final TextEditingController _disputeNote =
      TextEditingController(text: "Escalade automatique");
  final TextEditingController _approvalAmount =
      TextEditingController(text: "50000");
  final TextEditingController _approvalReason =
      TextEditingController(text: "Depense entreprise");
  final TextEditingController _loyaltyPoints =
      TextEditingController(text: "100");
  final TextEditingController _apiKeyName =
      TextEditingController(text: "Partner ERP");
  final TextEditingController _webhookTopic =
      TextEditingController(text: "orders");
  final TextEditingController _webhookUrl =
      TextEditingController(text: "https://example.com/webhook");
  final TextEditingController _webhookTestId = TextEditingController();

  bool _busy = false;
  final Map<String, dynamic> _results = {};

  String? get _token => context.read<SessionStore>().token;

  @override
  void dispose() {
    _orderId.dispose();
    _rfqId.dispose();
    _offerId.dispose();
    _counterPrice.dispose();
    _counterLead.dispose();
    _counterNote.dispose();
    _productId.dispose();
    _alertProductId.dispose();
    _variantsJson.dispose();
    _bundlesJson.dispose();
    _alertTargetPrice.dispose();
    _shipmentId.dispose();
    _disputeId.dispose();
    _disputeNote.dispose();
    _approvalAmount.dispose();
    _approvalReason.dispose();
    _loyaltyPoints.dispose();
    _apiKeyName.dispose();
    _webhookTopic.dispose();
    _webhookUrl.dispose();
    _webhookTestId.dispose();
    super.dispose();
  }

  Future<void> _run(String key, Future<dynamic> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final output = await job();
      if (!mounted) return;
      setState(() => _results[key] = output);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$key: OK")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _results[key] = {"error": e.toString()});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text("$key: ${e.toString().replaceFirst("Exception: ", "")}")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int _readInt(TextEditingController ctrl) =>
      int.tryParse(ctrl.text.trim()) ?? 0;
  double _readDouble(TextEditingController ctrl) =>
      double.tryParse(ctrl.text.trim()) ?? 0;

  List<dynamic> _parseJsonList(TextEditingController ctrl) {
    final raw = ctrl.text.trim();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw Exception("JSON doit etre une liste.");
    }
    return decoded;
  }

  String _pretty(Object? data) =>
      const JsonEncoder.withIndent("  ").convert(data);

  bool _isSeller(UserRole role) =>
      role == UserRole.supplier || role == UserRole.wholesaler;

  bool _isBusiness(UserRole role) =>
      _isSeller(role) || role == UserRole.transitAgent;

  bool _canEscrow(UserRole role) =>
      role == UserRole.generalAdmin ||
      role == UserRole.buyer ||
      _isSeller(role) ||
      role == UserRole.transitAgent;

  bool _canRfqCompare(UserRole role) =>
      role == UserRole.generalAdmin || role == UserRole.buyer;

  bool _canCounterOffer(UserRole role) =>
      role == UserRole.generalAdmin ||
      role == UserRole.buyer ||
      role == UserRole.supplier ||
      role == UserRole.wholesaler;

  bool _canEditCatalog(UserRole role) =>
      role == UserRole.generalAdmin || _isSeller(role);

  bool _canPriceAlerts(UserRole role) =>
      role == UserRole.generalAdmin || role == UserRole.buyer;

  bool _canWalletApproval(UserRole role) =>
      role == UserRole.generalAdmin || _isBusiness(role);

  bool _canRecommendationReasons(UserRole role) =>
      role == UserRole.generalAdmin || role == UserRole.buyer;

  bool _canSellerDashboard(UserRole role) =>
      role == UserRole.generalAdmin || _isSeller(role);

  bool _canPartnerApi(UserRole role) =>
      role == UserRole.generalAdmin || _isBusiness(role);

  void _showHint(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _requirePositiveInt(TextEditingController ctrl, String label) {
    final value = int.tryParse(ctrl.text.trim());
    if (value == null || value <= 0) {
      _showHint("$label invalide.");
      return false;
    }
    return true;
  }

  bool _requirePositiveDouble(TextEditingController ctrl, String label) {
    final value = double.tryParse(ctrl.text.trim());
    if (value == null || value <= 0) {
      _showHint("$label invalide.");
      return false;
    }
    return true;
  }

  bool _requireMinText(TextEditingController ctrl, String label, int minChars) {
    if (ctrl.text.trim().length < minChars) {
      _showHint("$label doit contenir au moins $minChars caracteres.");
      return false;
    }
    return true;
  }

  bool _requireJsonList(TextEditingController ctrl, String label) {
    try {
      _parseJsonList(ctrl);
      return true;
    } catch (_) {
      _showHint("$label doit etre un JSON de type liste.");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final role = session.role;
    final canEscrow = _canEscrow(role);
    final canRfqCompare = _canRfqCompare(role);
    final canCounterOffer = _canCounterOffer(role);
    final canCatalog = _canEditCatalog(role);
    final canPriceAlerts = _canPriceAlerts(role);
    final canShipmentTimeline = canEscrow;
    final canDisputeEscalation = canEscrow;
    final canWalletApproval = _canWalletApproval(role);
    final canRecommendations = _canRecommendationReasons(role);
    final canSellerDashboard = _canSellerDashboard(role);
    final canPartnerApi = _canPartnerApi(role);
    final hasActionableModules = canEscrow ||
        canRfqCompare ||
        canCounterOffer ||
        canCatalog ||
        canPriceAlerts ||
        canWalletApproval ||
        canRecommendations ||
        canSellerDashboard ||
        canPartnerApi;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Innovation Hub (15 features)"),
        actions: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: session.appLocale.languageCode,
              items: const [
                DropdownMenuItem(value: "fr", child: Text("FR")),
                DropdownMenuItem(value: "en", child: Text("EN")),
              ],
              onChanged: (value) {
                if (value == null) return;
                session.setLocale(value);
              },
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(
            "Modules disponibles pour le role ${role.name}. Les modules non autorises sont masques.",
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (canEscrow) _buildEscrow(),
          if (canRfqCompare) _buildRfqCompare(),
          if (canCounterOffer) _buildCounterOffer(),
          if (canCatalog) _buildVariantsBundles(),
          if (canPriceAlerts) _buildPriceAlerts(),
          if (canShipmentTimeline) _buildShipmentTimeline(),
          if (canDisputeEscalation) _buildDisputeEscalation(),
          _buildOnboardingChecklist(),
          if (canWalletApproval) _buildWalletApproval(),
          if (canRecommendations) _buildRecommendationReasons(),
          if (canSellerDashboard) _buildSellerDashboard(),
          _buildLoyalty(),
          _buildOfflineInfo(),
          _buildI18nInfo(),
          if (canPartnerApi) _buildPartnerApi(),
          if (!hasActionableModules)
            _section(
              "Acces limite",
              "Aucun module actionnable pour ce role.",
              const [
                Text(
                  "Connectez-vous avec un compte acheteur, vendeur, transitaire ou admin pour acceder aux actions avancees.",
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _resultBox(String key) {
    final data = _results[key];
    if (data == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: SelectableText(_pretty(data)),
    );
  }

  Widget _section(String title, String subtitle, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildEscrow() {
    return _section(
      "1) Escrow multi-parties",
      "Preview de repartition vendeur/transitaire/plateforme",
      [
        TextField(
            controller: _orderId,
            decoration: const InputDecoration(labelText: "Order ID")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_orderId, "Order ID")) return;
                  _run(
                    "escrow_split",
                    () => _api.getObject(
                      "/api/innovation/escrow-split/?order_id=${_readInt(_orderId)}",
                      token: _token,
                    ),
                  );
                },
          child: const Text("Calculer split"),
        ),
        _resultBox("escrow_split"),
      ],
    );
  }

  Widget _buildRfqCompare() {
    return _section(
      "2) Comparateur d'offres RFQ",
      "Classement automatique et recommandation",
      [
        TextField(
            controller: _rfqId,
            decoration: const InputDecoration(labelText: "RFQ ID")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_rfqId, "RFQ ID")) return;
                  _run(
                    "rfq_compare",
                    () => _api.getObject(
                      "/api/innovation/rfq-compare/?rfq_id=${_readInt(_rfqId)}",
                      token: _token,
                    ),
                  );
                },
          child: const Text("Comparer"),
        ),
        _resultBox("rfq_compare"),
      ],
    );
  }

  Widget _buildCounterOffer() {
    return _section(
      "3) Negociation structuree",
      "Creation de contre-offres RFQ",
      [
        TextField(
            controller: _offerId,
            decoration: const InputDecoration(labelText: "RFQ Offer ID")),
        TextField(
            controller: _counterPrice,
            decoration: const InputDecoration(labelText: "Prix cible")),
        TextField(
            controller: _counterLead,
            decoration: const InputDecoration(labelText: "Delai (jours)")),
        TextField(
            controller: _counterNote,
            decoration: const InputDecoration(labelText: "Note")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_offerId, "RFQ Offer ID")) return;
                  if (!_requirePositiveDouble(_counterPrice, "Prix cible")) {
                    return;
                  }
                  if (!_requirePositiveInt(_counterLead, "Delai")) return;
                  _run(
                    "counter_offer_create",
                    () => _api.post(
                      "/api/rfq-counter-offers/",
                      {
                        "rfq_offer": _readInt(_offerId),
                        "target_price": _readDouble(_counterPrice),
                        "lead_time_days": _readInt(_counterLead),
                        "note": _counterNote.text.trim(),
                      },
                      token: _token,
                    ),
                  );
                },
          child: const Text("Creer contre-offre"),
        ),
        _resultBox("counter_offer_create"),
      ],
    );
  }

  Widget _buildVariantsBundles() {
    return _section(
      "4) Variantes & bundles catalogue",
      "Edition des options produit (JSON)",
      [
        TextField(
            controller: _productId,
            decoration: const InputDecoration(labelText: "Product ID")),
        TextField(
          controller: _variantsJson,
          minLines: 2,
          maxLines: 4,
          decoration:
              const InputDecoration(labelText: "variant_options (JSON list)"),
        ),
        TextField(
          controller: _bundlesJson,
          minLines: 2,
          maxLines: 4,
          decoration:
              const InputDecoration(labelText: "bundle_items (JSON list)"),
        ),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_productId, "Product ID")) return;
                  if (!_requireJsonList(_variantsJson, "variant_options")) {
                    return;
                  }
                  if (!_requireJsonList(_bundlesJson, "bundle_items")) return;
                  _run(
                    "product_variants_bundles",
                    () => _api.patch(
                      "/api/products/${_readInt(_productId)}/",
                      {
                        "variant_options": _parseJsonList(_variantsJson),
                        "bundle_items": _parseJsonList(_bundlesJson),
                      },
                      token: _token,
                    ),
                  );
                },
          child: const Text("Mettre a jour"),
        ),
        _resultBox("product_variants_bundles"),
      ],
    );
  }

  Widget _buildPriceAlerts() {
    return _section(
      "5) Alertes prix/disponibilite",
      "Creation + evaluation immediate",
      [
        Row(
          children: [
            Expanded(
              child: TextField(
                  controller: _alertProductId,
                  decoration: const InputDecoration(labelText: "Product ID")),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                  controller: _alertTargetPrice,
                  decoration: const InputDecoration(labelText: "Prix cible")),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (!_requirePositiveInt(_alertProductId, "Product ID")) {
                        return;
                      }
                      if (!_requirePositiveDouble(
                          _alertTargetPrice, "Prix cible")) {
                        return;
                      }
                      _run(
                        "price_alert_create",
                        () => _api.post(
                          "/api/price-alerts/",
                          {
                            "product": _readInt(_alertProductId),
                            "target_price": _readDouble(_alertTargetPrice),
                            "notify_on_back_in_stock": true,
                            "is_active": true,
                          },
                          token: _token,
                        ),
                      );
                    },
              child: const Text("Creer alerte"),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                        "price_alert_evaluate",
                        () => _api.post("/api/price-alerts/evaluate/", {},
                            token: _token),
                      ),
              child: const Text("Evaluer maintenant"),
            ),
          ],
        ),
        _resultBox("price_alert_create"),
        _resultBox("price_alert_evaluate"),
      ],
    );
  }

  Widget _buildShipmentTimeline() {
    return _section(
      "6) Suivi expedition avance",
      "Timeline + ETA dynamique",
      [
        TextField(
            controller: _shipmentId,
            decoration: const InputDecoration(labelText: "Shipment ID")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_shipmentId, "Shipment ID")) return;
                  _run(
                    "shipment_timeline",
                    () => _api.getObject(
                      "/api/innovation/shipment-timeline/?shipment_id=${_readInt(_shipmentId)}",
                      token: _token,
                    ),
                  );
                },
          child: const Text("Charger timeline"),
        ),
        _resultBox("shipment_timeline"),
      ],
    );
  }

  Widget _buildDisputeEscalation() {
    return _section(
      "7) Litiges avec escalation",
      "Escalade rapide d'un litige",
      [
        TextField(
            controller: _disputeId,
            decoration: const InputDecoration(labelText: "Dispute ID")),
        TextField(
            controller: _disputeNote,
            decoration: const InputDecoration(labelText: "Note")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_disputeId, "Dispute ID")) return;
                  if (!_requireMinText(_disputeNote, "Note", 8)) return;
                  _run(
                    "dispute_escalate",
                    () => _api.post(
                      "/api/innovation/disputes/${_readInt(_disputeId)}/escalate/",
                      {"note": _disputeNote.text.trim()},
                      token: _token,
                    ),
                  );
                },
          child: const Text("Escalader"),
        ),
        _resultBox("dispute_escalate"),
      ],
    );
  }

  Widget _buildOnboardingChecklist() {
    return _section(
      "8) Onboarding/KYC guide",
      "Checklist de progression par role",
      [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    "onboarding_checklist",
                    () => _api.getObject(
                        "/api/innovation/onboarding/checklist/",
                        token: _token),
                  ),
          child: const Text("Charger checklist"),
        ),
        _resultBox("onboarding_checklist"),
      ],
    );
  }

  Widget _buildWalletApproval() {
    return _section(
      "9) Wallet entreprise",
      "Demande d'approbation de depense",
      [
        TextField(
            controller: _approvalAmount,
            decoration: const InputDecoration(labelText: "Montant")),
        TextField(
            controller: _approvalReason,
            decoration: const InputDecoration(labelText: "Motif")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveDouble(_approvalAmount, "Montant")) {
                    return;
                  }
                  if (!_requireMinText(_approvalReason, "Motif", 8)) return;
                  _run(
                    "wallet_approval_request",
                    () => _api.post(
                      "/api/wallet-approval-requests/",
                      {
                        "amount": _readDouble(_approvalAmount),
                        "reason": _approvalReason.text.trim(),
                      },
                      token: _token,
                    ),
                  );
                },
          child: const Text("Soumettre demande"),
        ),
        _resultBox("wallet_approval_request"),
      ],
    );
  }

  Widget _buildRecommendationReasons() {
    return _section(
      "10) Recommandations explicables",
      "Top produits + raisons de recommandation",
      [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    "recommendation_reasons",
                    () => _api.getObject(
                        "/api/innovation/recommendations/reasons/",
                        token: _token),
                  ),
          child: const Text("Analyser"),
        ),
        _resultBox("recommendation_reasons"),
      ],
    );
  }

  Widget _buildSellerDashboard() {
    return _section(
      "11) Dashboard vendeur",
      "Revenus, commandes, top produits, repeat buyers",
      [
        FilledButton(
          onPressed: _busy
              ? null
              : () => _run(
                    "seller_dashboard",
                    () => _api.getObject("/api/innovation/seller-dashboard/",
                        token: _token),
                  ),
          child: const Text("Charger dashboard"),
        ),
        _resultBox("seller_dashboard"),
      ],
    );
  }

  Widget _buildLoyalty() {
    final isAdmin = context.watch<SessionStore>().role == UserRole.generalAdmin;
    return _section(
      "12) Fidelite",
      "Points + tiers + historique",
      [
        TextField(
            controller: _loyaltyPoints,
            decoration: const InputDecoration(labelText: "Points")),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            if (isAdmin)
              FilledButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (!_requirePositiveInt(_loyaltyPoints, "Points")) {
                          return;
                        }
                        _run(
                          "loyalty_earn",
                          () => _api.post(
                            "/api/loyalty/account/",
                            {
                              "action": "EARN",
                              "points": _readInt(_loyaltyPoints),
                              "reason": "Action marketing",
                            },
                            token: _token,
                          ),
                        );
                      },
                child: const Text("Crediter"),
              ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () {
                      if (!_requirePositiveInt(_loyaltyPoints, "Points")) {
                        return;
                      }
                      _run(
                        "loyalty_redeem",
                        () => _api.post(
                          "/api/loyalty/account/",
                          {
                            "action": "REDEEM",
                            "points": _readInt(_loyaltyPoints),
                            "reason": "Remise commande",
                          },
                          token: _token,
                        ),
                      );
                    },
              child: const Text("Debiter"),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      "loyalty_account",
                      () => _api.getObject("/api/loyalty/account/",
                          token: _token)),
              child: const Text("Rafraichir"),
            ),
          ],
        ),
        _resultBox("loyalty_earn"),
        _resultBox("loyalty_redeem"),
        _resultBox("loyalty_account"),
      ],
    );
  }

  Widget _buildOfflineInfo() {
    return _section(
      "13) Mode hors-ligne",
      "Le feed utilise maintenant un cache local automatique en cas d'erreur reseau.",
      [
        const Text(
          "Test rapide: charge le feed en ligne une fois, coupe internet, puis rouvre le feed.\n"
          "Le badge 'Mode hors-ligne actif' apparaitra avec les donnees en cache.",
        ),
      ],
    );
  }

  Widget _buildI18nInfo() {
    return _section(
      "14) Internationalisation",
      "Support FR/EN active + switch de langue dans l'entete.",
      [
        const Text(
            "Le MaterialApp est configure avec les locales FR/EN et delegates Flutter."),
      ],
    );
  }

  Widget _buildPartnerApi() {
    return _section(
      "15) API partenaires + webhooks",
      "Creation de cles API, subscription webhook, test d'envoi",
      [
        TextField(
            controller: _apiKeyName,
            decoration: const InputDecoration(labelText: "Nom cle API")),
        const SizedBox(height: 6),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requireMinText(_apiKeyName, "Nom cle API", 3)) return;
                  _run(
                    "partner_api_key",
                    () => _api.post(
                      "/api/partner-api-keys/",
                      {"name": _apiKeyName.text.trim()},
                      token: _token,
                    ),
                  );
                },
          child: const Text("Creer cle API"),
        ),
        const SizedBox(height: 8),
        TextField(
            controller: _webhookTopic,
            decoration: const InputDecoration(labelText: "Topic webhook")),
        TextField(
            controller: _webhookUrl,
            decoration: const InputDecoration(labelText: "Webhook URL")),
        const SizedBox(height: 6),
        FilledButton.tonal(
          onPressed: _busy
              ? null
              : () {
                  if (!_requireMinText(_webhookTopic, "Topic webhook", 3)) {
                    return;
                  }
                  if (!_requireMinText(_webhookUrl, "Webhook URL", 10)) return;
                  if (!_webhookUrl.text
                      .trim()
                      .toLowerCase()
                      .startsWith("https://")) {
                    _showHint("Webhook URL doit commencer par https://");
                    return;
                  }
                  _run(
                    "webhook_create",
                    () => _api.post(
                      "/api/webhook-subscriptions/",
                      {
                        "topic": _webhookTopic.text.trim(),
                        "endpoint_url": _webhookUrl.text.trim(),
                        "secret": "secret-demo",
                        "is_active": true,
                      },
                      token: _token,
                    ),
                  );
                },
          child: const Text("Creer webhook"),
        ),
        TextField(
            controller: _webhookTestId,
            decoration: const InputDecoration(labelText: "Webhook ID (test)")),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () {
                  if (!_requirePositiveInt(_webhookTestId, "Webhook ID")) {
                    return;
                  }
                  _run(
                    "webhook_send_test",
                    () => _api.post(
                      "/api/webhook-subscriptions/${_readInt(_webhookTestId)}/send_test/",
                      {},
                      token: _token,
                    ),
                  );
                },
          child: const Text("Envoyer test"),
        ),
        _resultBox("partner_api_key"),
        _resultBox("webhook_create"),
        _resultBox("webhook_send_test"),
      ],
    );
  }
}

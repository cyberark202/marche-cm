import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';
import '../buyer/buyer_store.dart';
import '../buyer/cart_page.dart';
import '../buyer/notifications_page.dart';
import '../buyer/rfq_compare_page.dart';
import '../business/rfqs_page.dart';
import '../feed/feed_api_service.dart';
import '../feed/feed_models.dart';
import '../feed/product_publication_detail_page.dart';

enum _SortMode { relevance, priceAsc, priceDesc, trust }

class ShopTab extends StatefulWidget {
  const ShopTab({super.key});

  @override
  State<ShopTab> createState() => _ShopTabState();
}

class _ShopTabState extends State<ShopTab> {
  late Future<FeedPayload> _feedFuture;
  final FeedApiService _feedApi = FeedApiService();
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  static const String _filterDraftKey = "feed_filters_draft_v1";

  String _selectedCategory = "Tous";
  String _search = "";
  String _imageSearchLabel = "";
  Set<String> _imageSearchKeywords = const {};
  Set<String> _imageSearchBlockedKeywords = const {};
  Set<int>? _imageSearchProductIds;
  bool _onlyVerified = false;
  String _selectedCountry = "Tous";
  _SortMode _sortMode = _SortMode.relevance;
  List<Map<String, String>> _sortChoices = const [];
  String _searchHint = "Rechercher un produit...";
  double? _priceMinFilter;
  double? _priceMaxFilter;
  Set<int> _favoriteProductIds = const {};
  List<Map<String, dynamic>> _savedFilters = const [];

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _restoreFilterDraft();
    _loadPersonalizationData();
    _feedFuture = _feedApi.loadFeed(token: context.read<SessionStore>().token);
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final topic = (event["topic"] ?? "").toString();
      if (topic == "products" || topic == "analytics" || topic == "orders") {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final sortChoices = BackendUiConfigService.instance
          .readChoiceList(config, ["choices", "feed_sort_modes"]);
      final blocked = BackendUiConfigService.instance
          .readStringList(config, ["choices", "feed_image_blocked_keywords"])
          .toSet();
      final hint = BackendUiConfigService.instance
          .readString(config, ["defaults", "feed_search_hint"]);
      if (!mounted) return;
      setState(() {
        _sortChoices = sortChoices;
        _imageSearchBlockedKeywords = blocked;
        if (hint.isNotEmpty) _searchHint = hint;
        if (sortChoices.isNotEmpty) {
          _sortMode = _sortModeFromKey(sortChoices.first["value"]!);
        }
      });
    } catch (_) {}
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _feedFuture =
          _feedApi.loadFeed(token: context.read<SessionStore>().token);
    });
    _loadPersonalizationData();
  }

  Future<void> _loadPersonalizationData() async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    try {
      final results = await Future.wait([
        _api.getList("/api/product-favorites/", token: token),
        _api.getList("/api/product-filters/", token: token),
      ]);
      final favorites = results[0]
          .map((r) => int.tryParse("${r["product"] ?? ""}"))
          .whereType<int>()
          .toSet();
      if (!mounted) return;
      setState(() {
        _favoriteProductIds = favorites;
        _savedFilters = results[1];
      });
    } catch (_) {}
  }

  Future<void> _persistFilterDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _filterDraftKey,
      jsonEncode({
        "selectedCategory": _selectedCategory,
        "selectedCountry": _selectedCountry,
        "search": _search,
        "imageSearchLabel": _imageSearchLabel,
        "imageSearchKeywords": _imageSearchKeywords.toList(),
        "onlyVerified": _onlyVerified,
        "sortMode": _sortModeKey(_sortMode),
        "priceMinFilter": _priceMinFilter,
        "priceMaxFilter": _priceMaxFilter,
      }),
    );
  }

  Future<void> _restoreFilterDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_filterDraftKey);
    if (raw == null || raw.trim().isEmpty) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    if (!mounted) return;
    setState(() {
      final cat = (decoded["selectedCategory"] ?? "").toString();
      final country = (decoded["selectedCountry"] ?? "").toString();
      if (cat.isNotEmpty) _selectedCategory = cat;
      if (country.isNotEmpty) _selectedCountry = country;
      _search = (decoded["search"] ?? "").toString();
      _searchCtrl.text = _search;
      _imageSearchLabel = (decoded["imageSearchLabel"] ?? "").toString();
      _onlyVerified = (decoded["onlyVerified"] ?? false) == true;
      final sort = (decoded["sortMode"] ?? "").toString();
      if (sort.isNotEmpty) _sortMode = _sortModeFromKey(sort);
      _priceMinFilter = double.tryParse("${decoded["priceMinFilter"] ?? ""}");
      _priceMaxFilter = double.tryParse("${decoded["priceMaxFilter"] ?? ""}");
      _imageSearchKeywords =
          ((decoded["imageSearchKeywords"] as List?) ?? const [])
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toSet();
    });
  }

  Future<void> _toggleFavorite(ProductCardData product) async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    final already = _favoriteProductIds.contains(product.id);
    setState(() {
      if (already) {
        _favoriteProductIds =
            _favoriteProductIds.where((id) => id != product.id).toSet();
      } else {
        _favoriteProductIds = {..._favoriteProductIds, product.id};
      }
    });
    try {
      await _api.post("/api/product-favorites/toggle/", {"product_id": product.id},
          token: token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (already) {
          _favoriteProductIds = {..._favoriteProductIds, product.id};
        } else {
          _favoriteProductIds =
              _favoriteProductIds.where((id) => id != product.id).toSet();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e, fallback: "Action favoris échouée."))),
      );
    }
  }

  Future<void> _saveCurrentFilter() async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sauvegarder ce filtre"),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(labelText: "Nom du filtre"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Sauvegarder")),
        ],
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true || !mounted || name.isEmpty) return;
    try {
      await _api.post("/api/product-filters/", {
        "name": name,
        "query": _search,
        "category": _selectedCategory == "Tous" ? "" : _selectedCategory,
        "country_code": _selectedCountry == "Tous" ? "" : _selectedCountry,
        "min_price": _priceMinFilter,
        "max_price": _priceMaxFilter,
        "only_verified": _onlyVerified,
        "sort_mode": _sortModeKey(_sortMode),
      }, token: token);
      await _loadPersonalizationData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Filtre sauvegardé.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e, fallback: "Sauvegarde impossible."))),
      );
    }
  }

  void _applySavedFilter(Map<String, dynamic> filter) {
    setState(() {
      final category = (filter["category"] ?? "").toString().trim();
      final country = (filter["country_code"] ?? "").toString().trim();
      _selectedCategory = category.isEmpty ? "Tous" : category;
      _selectedCountry = country.isEmpty ? "Tous" : country;
      _search = (filter["query"] ?? "").toString();
      _searchCtrl.text = _search;
      _onlyVerified = (filter["only_verified"] ?? false) == true;
      _sortMode = _sortModeFromKey((filter["sort_mode"] ?? "relevance").toString());
      _priceMinFilter = double.tryParse("${filter["min_price"] ?? ""}");
      _priceMaxFilter = double.tryParse("${filter["max_price"] ?? ""}");
    });
    unawaited(_persistFilterDraft());
  }

  Future<void> _deleteSavedFilter(int id) async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    try {
      await _api.delete("/api/product-filters/$id/", token: token);
      await _loadPersonalizationData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e, fallback: "Suppression impossible."))),
      );
    }
  }

  Future<void> _searchByImage() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final fileName = picked.files.single.name;
    final keywords = RegExp(r"[a-zA-Z0-9]{3,}")
        .allMatches(fileName.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => !_imageSearchBlockedKeywords.contains(t))
        .toSet();
    final token = context.read<SessionStore>().token;
    final matches =
        await _feedApi.imageSearch(query: keywords.join(" "), token: token);
    if (!mounted) return;
    setState(() {
      _imageSearchLabel = fileName;
      _imageSearchKeywords = keywords;
      _imageSearchProductIds = matches.map((e) => e.id).toSet();
    });
    unawaited(_persistFilterDraft());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(keywords.isEmpty
              ? "Aucun mot clé détecté dans l'image."
              : "Recherche image: ${keywords.join(', ')} (${matches.length} résultat(s))")),
    );
  }

  void _clearImageSearch() {
    setState(() {
      _imageSearchLabel = "";
      _imageSearchKeywords = const {};
      _imageSearchProductIds = null;
    });
    unawaited(_persistFilterDraft());
  }

  Future<void> _onProductOpened(ProductCardData product) async {
    final store = context.read<BuyerStore>();
    final session = context.read<SessionStore>();
    store.recordProductView(
      productId: product.id,
      title: product.title,
      brand: product.brand,
      priceMin: product.priceMin,
      priceMax: product.priceMax,
      locality: product.sellerCountryCode,
    );
    await _feedApi.trackProductView(productId: product.id, token: session.token);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => ProductPublicationDetailPage(product: product)),
    );
    if (!mounted) return;
    _reload();
  }

  List<ProductCardData> _filteredProducts(
    List<ProductCardData> products,
    BuyerStore store,
    double selMin,
    double selMax,
  ) {
    Iterable<ProductCardData> result =
        products.where((p) => (p.videoUrl ?? "").trim().isEmpty);
    if (_selectedCategory != "Tous") {
      result = result.where(
          (p) => p.category.toLowerCase() == _selectedCategory.toLowerCase());
    }
    if (_selectedCountry != "Tous") {
      result = result.where(
          (p) => p.sellerCountryCode.toUpperCase() == _selectedCountry.toUpperCase());
    }
    if (_onlyVerified) {
      result = result.where((p) => p.sellerVerified);
    }
    result = result
        .where((p) => p.priceMax.toDouble() >= selMin && p.priceMax.toDouble() <= selMax);
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where((p) =>
          p.title.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.sellerDisplayName.toLowerCase().contains(q));
    }
    if (_imageSearchKeywords.isNotEmpty) {
      result = result.where((p) {
        final hay =
            "${p.title} ${p.brand} ${p.category} ${p.description}".toLowerCase();
        return _imageSearchKeywords.any(hay.contains);
      });
    }
    if (_imageSearchProductIds != null) {
      result = result.where((p) => _imageSearchProductIds!.contains(p.id));
    }
    final list = result.toList();
    list.sort((a, b) {
      final sa = store.preferenceScoreFor(
          productId: a.id, title: a.title, brand: a.brand,
          priceMin: a.priceMin, priceMax: a.priceMax, locality: a.sellerCountryCode);
      final sb = store.preferenceScoreFor(
          productId: b.id, title: b.title, brand: b.brand,
          priceMin: b.priceMin, priceMax: b.priceMax, locality: b.sellerCountryCode);
      final diff = sb.compareTo(sa);
      if (diff != 0) return diff;
      return switch (_sortMode) {
        _SortMode.priceAsc => a.priceMax.compareTo(b.priceMax),
        _SortMode.priceDesc => b.priceMin.compareTo(a.priceMin),
        _SortMode.trust => b.sellerTrustScore.compareTo(a.sellerTrustScore),
        _SortMode.relevance => b.sellerTrustScore.compareTo(a.sellerTrustScore),
      };
    });
    return list;
  }

  ({double min, double max}) _priceBounds(List<ProductCardData> products) {
    if (products.isEmpty) return (min: 0, max: 0);
    var lo = products.first.priceMin.toDouble();
    var hi = products.first.priceMax.toDouble();
    for (final p in products) {
      lo = math.min(lo, p.priceMin.toDouble());
      hi = math.max(hi, p.priceMax.toDouble());
    }
    return (min: lo, max: math.max(lo, hi));
  }

  int get _activeFiltersCount => [
        _selectedCategory != 'Tous',
        _selectedCountry != 'Tous',
        _onlyVerified,
        _imageSearchLabel.isNotEmpty,
        _priceMinFilter != null,
      ].where((v) => v).length;

  _SortMode _sortModeFromKey(String key) => switch (key) {
        "priceAsc" => _SortMode.priceAsc,
        "priceDesc" => _SortMode.priceDesc,
        "trust" => _SortMode.trust,
        _ => _SortMode.relevance,
      };

  String _sortModeKey(_SortMode m) => switch (m) {
        _SortMode.priceAsc => "priceAsc",
        _SortMode.priceDesc => "priceDesc",
        _SortMode.trust => "trust",
        _SortMode.relevance => "relevance",
      };

  String _resolveImageUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return "";
    if (v.startsWith("http://") || v.startsWith("https://")) return v;
    return "${AppConfig.apiBaseUrl}${v.startsWith("/") ? v : "/$v"}";
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BuyerStore>();
    final session = context.watch<SessionStore>();
    final cartCount = store.cartItems.length;
    final unread = store.unreadNotificationsCount;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _buildHeader(session, store, cartCount, unread),
          Expanded(
            child: FutureBuilder<FeedPayload>(
              future: _feedFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_outlined,
                            size: 48, color: Colors.black38),
                        const SizedBox(height: 12),
                        const Text("Catalogue temporairement indisponible."),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _reload,
                            child: const Text("Réessayer")),
                      ],
                    ),
                  );
                }
                final payload = snapshot.data!;
                final allProducts = payload.products
                    .where((p) => (p.videoUrl ?? "").trim().isEmpty)
                    .toList();
                final bounds = _priceBounds(allProducts);
                final selMin = _priceMinFilter ?? bounds.min;
                final selMax = _priceMaxFilter ?? bounds.max;
                final products =
                    _filteredProducts(allProducts, store, selMin, selMax);
                final categories = <String>{
                  "Tous",
                  ...allProducts.map((p) => p.category)
                };
                final countries = <String>{
                  "Tous",
                  ...allProducts.map((p) => p.sellerCountryCode.toUpperCase())
                };
                final activeFilters = [
                  _selectedCategory != "Tous",
                  _selectedCountry != "Tous",
                  _onlyVerified,
                  _imageSearchLabel.isNotEmpty,
                  (_priceMinFilter != null &&
                      (_priceMinFilter! - bounds.min).abs() > 0.5),
                ].where((v) => v).length;

                return CustomScrollView(
                  slivers: [
                    if (payload.usingFallback)
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: const Color(0xFFF97316)),
                          ),
                          child: const Text(
                            "Mode hors-ligne actif — données du cache local.",
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _buildFilters(
                        categories: categories,
                        countries: countries,
                        bounds: bounds,
                        selMin: selMin,
                        selMax: selMax,
                        activeFilters: activeFilters,
                        store: store,
                        allProducts: allProducts,
                        payload: payload,
                      ),
                    ),
                    if (products.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.search_off,
                                    size: 56, color: Colors.black26),
                                const SizedBox(height: 12),
                                Text(
                                  allProducts.isEmpty
                                      ? "Aucun produit disponible"
                                      : "Aucun résultat",
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  allProducts.isEmpty
                                      ? "Le catalogue sera alimenté dès qu'un vendeur publie."
                                      : "Ajustez vos filtres ou réinitialisez.",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                                if (activeFilters > 0) ...[
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: () => setState(() {
                                      _selectedCategory = "Tous";
                                      _selectedCountry = "Tous";
                                      _onlyVerified = false;
                                      _priceMinFilter = null;
                                      _priceMaxFilter = null;
                                      _clearImageSearch();
                                    }),
                                    icon: const Icon(Icons.restart_alt),
                                    label: const Text("Réinitialiser filtres"),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.62,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final p = products[index];
                              return _ProductCard(
                                product: p,
                                isFavorite: _favoriteProductIds.contains(p.id),
                                imageUrl: _resolveImageUrl(p.imageUrl),
                                onTap: () => _onProductOpened(p),
                                onFavorite: () => unawaited(_toggleFavorite(p)),
                                onAddToCart: () =>
                                    context.read<BuyerStore>().addToCart(p.id),
                              );
                            },
                            childCount: products.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    SessionStore session,
    BuyerStore store,
    int cartCount,
    int unread,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF063D27), Color(0xFF0F7A4F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.white24,
                child: Icon(Icons.storefront, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Catalogue",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          letterSpacing: -0.3),
                    ),
                    Text(
                      "Marché.cm — fournisseurs vérifiés",
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Badge(
                label: Text(unread.toString()),
                isLabelVisible: unread > 0,
                child: IconButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const NotificationsPage()),
                    );
                    if (!mounted) return;
                    context.read<BuyerStore>().markAllNotificationsRead();
                  },
                  icon: const Icon(Icons.notifications_outlined,
                      color: Colors.white),
                ),
              ),
              Badge(
                label: Text(cartCount.toString()),
                isLabelVisible: cartCount > 0,
                child: IconButton(
                  onPressed: () async {
                    try {
                      final payload = await _feedFuture;
                      if (!mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => CartPage(products: payload.products)));
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text("Impossible de charger le panier.")),
                      );
                    }
                  },
                  icon: const Icon(Icons.shopping_cart_outlined,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      const Icon(Icons.search, color: Colors.black45, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) {
                            setState(() => _search = v);
                            unawaited(_persistFilterDraft());
                          },
                          decoration: InputDecoration(
                            hintText: _searchHint,
                            hintStyle: const TextStyle(fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                label: Text('$_activeFiltersCount'),
                isLabelVisible: _activeFiltersCount > 0,
                backgroundColor: Colors.red,
                child: _IconBtn(
                  icon: Icons.tune,
                  onTap: () {},
                  tooltip: "Filtres actifs",
                ),
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.camera_alt_outlined,
                onTap: _searchByImage,
                tooltip: "Recherche image",
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.compare_arrows,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RfqComparePage())),
                tooltip: "Comparer offres",
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.request_quote_outlined,
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RfqsPage())),
                tooltip: "Créer RFQ",
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters({
    required Set<String> categories,
    required Set<String> countries,
    required ({double min, double max}) bounds,
    required double selMin,
    required double selMax,
    required int activeFilters,
    required BuyerStore store,
    required List<ProductCardData> allProducts,
    required FeedPayload payload,
  }) {
    final priceRangeEnabled = bounds.max > bounds.min;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final cat = categories.elementAt(index);
              final selected = cat == _selectedCategory;
              return ChoiceChip(
                label: Text(cat,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: selected ? AppPalette.primary : null)),
                selected: selected,
                onSelected: (_) {
                  setState(() => _selectedCategory = cat);
                  unawaited(_persistFilterDraft());
                },
                selectedColor: AppPalette.primary.withValues(alpha: 0.15),
                side: BorderSide(
                    color: selected
                        ? AppPalette.primary
                        : const Color(0xFFE5E7EB)),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              PopupMenuButton<String>(
                initialValue: _selectedCountry,
                onSelected: (v) {
                  setState(() => _selectedCountry = v);
                  unawaited(_persistFilterDraft());
                },
                itemBuilder: (ctx) => countries
                    .map((c) =>
                        PopupMenuItem(value: c, child: Text("Pays: $c")))
                    .toList(),
                child: Chip(
                  label: Text("Pays: $_selectedCountry"),
                  avatar: const Icon(Icons.public, size: 16),
                ),
              ),
              const SizedBox(width: 8),
              if (_sortChoices.isNotEmpty)
                PopupMenuButton<String>(
                  initialValue: _sortModeKey(_sortMode),
                  onSelected: (v) {
                    setState(() => _sortMode = _sortModeFromKey(v));
                    unawaited(_persistFilterDraft());
                  },
                  itemBuilder: (ctx) => _sortChoices
                      .map((c) => PopupMenuItem(
                          value: c["value"],
                          child: Text("Tri: ${c["label"] ?? c["value"]}")))
                      .toList(),
                  child: Chip(
                    label: Text(_sortChoices.firstWhere(
                            (c) => c["value"] == _sortModeKey(_sortMode),
                            orElse: () =>
                                {"label": "Pertinence", "value": "relevance"})["label"]!),
                    avatar: const Icon(Icons.sort, size: 16),
                  ),
                ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text("Vérifié"),
                selected: _onlyVerified,
                avatar: const Icon(Icons.verified_outlined, size: 16),
                onSelected: (v) {
                  setState(() => _onlyVerified = v);
                  unawaited(_persistFilterDraft());
                },
              ),
              if (activeFilters > 0) ...[
                const SizedBox(width: 8),
                ActionChip(
                  label: Text("Effacer ($activeFilters)"),
                  avatar: const Icon(Icons.restart_alt, size: 16),
                  onPressed: () {
                    setState(() {
                      _selectedCategory = "Tous";
                      _selectedCountry = "Tous";
                      _onlyVerified = false;
                      _priceMinFilter = null;
                      _priceMaxFilter = null;
                    });
                    _clearImageSearch();
                    unawaited(_persistFilterDraft());
                  },
                ),
              ],
            ],
          ),
        ),
        if (_imageSearchLabel.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Chip(
                    avatar: const Icon(Icons.image_search, size: 16),
                    label: Text("Image: $_imageSearchLabel",
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
                TextButton.icon(
                  onPressed: _clearImageSearch,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text("Retirer"),
                ),
              ],
            ),
          ),
        ],
        if (priceRangeEnabled) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.tune, size: 16),
                        const SizedBox(width: 6),
                        const Text("Prix (FCFA)",
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text(
                          "${selMin.toInt()} – ${selMax.toInt()}",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  RangeSlider(
                    values: RangeValues(selMin, selMax),
                    min: bounds.min,
                    max: bounds.max,
                    divisions: 20,
                    labels: RangeLabels(
                        selMin.toInt().toString(), selMax.toInt().toString()),
                    onChanged: (v) {
                      setState(() {
                        _priceMinFilter = v.start;
                        _priceMaxFilter = v.end;
                      });
                      unawaited(_persistFilterDraft());
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _saveCurrentFilter,
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                label: const Text("Sauvegarder filtre"),
                style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              ),
              const SizedBox(width: 8),
              Text("${_savedFilters.length} filtre(s)",
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        if (_savedFilters.isNotEmpty) ...[
          const SizedBox(height: 6),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _savedFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final f = _savedFilters[i];
                final id = int.tryParse("${f["id"] ?? ""}") ?? 0;
                return InputChip(
                  label: Text((f["name"] ?? "Filtre").toString()),
                  onPressed: () => _applySavedFilter(f),
                  onDeleted: id <= 0 ? null : () => _deleteSavedFilter(id),
                  deleteIcon: const Icon(Icons.close, size: 14),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip = "",
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.isFavorite,
    required this.imageUrl,
    required this.onTap,
    required this.onFavorite,
    required this.onAddToCart,
  });

  final ProductCardData product;
  final bool isFavorite;
  final String imageUrl;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onAddToCart;

  bool get _hasPromo => product.priceMax > product.priceMin &&
      product.priceMin > 0 &&
      ((product.priceMax - product.priceMin) / product.priceMax) >= 0.05;

  int get _discountPct => _hasPromo
      ? (((product.priceMax - product.priceMin) / product.priceMax) * 100)
          .round()
      : 0;

  String _sellerInitials() {
    final src = product.sellerDisplayName.trim();
    if (src.isEmpty) return "·";
    final parts = src.split(RegExp(r"\s+"));
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length.clamp(0, 2)).toUpperCase();
    }
    return (parts[0].isNotEmpty ? parts[0][0] : "") +
        (parts[1].isNotEmpty ? parts[1][0] : "");
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadii.lg)),
                    child: AspectRatio(
                      aspectRatio: 1.05,
                      child: imageUrl.isEmpty
                          ? Container(
                              color: AppPalette.bgSoft,
                              child: const Center(
                                child: Icon(Icons.image_outlined,
                                    color: AppPalette.textFaint, size: 32),
                              ),
                            )
                          : CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: AppPalette.bgSoft,
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: AppPalette.textFaint, size: 28),
                                ),
                              ),
                            ),
                    ),
                  ),
                  if (product.sellerVerified)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppPalette.primary,
                          borderRadius:
                              BorderRadius.circular(AppRadii.pill),
                          boxShadow: AppPalette.shadowSoft,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.verified,
                                color: Colors.white, size: 10),
                            SizedBox(width: 3),
                            Text("KYC",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  if (_hasPromo)
                    Positioned(
                      top: 8,
                      right: 44,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppPalette.secondary,
                          borderRadius:
                              BorderRadius.circular(AppRadii.pill),
                          boxShadow: AppPalette.shadowSoft,
                        ),
                        child: Text(
                          "-$_discountPct%",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: onFavorite,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppPalette.shadowSoft,
                        ),
                        child: Icon(
                          isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 15,
                          color: isFavorite
                              ? AppPalette.danger
                              : AppPalette.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppPalette.primarySoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _sellerInitials(),
                            style: const TextStyle(
                                color: AppPalette.primaryDark,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            product.sellerDisplayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppPalette.textMuted,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          height: 1.25,
                          color: AppPalette.text),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            color: AppPalette.accent, size: 13),
                        const SizedBox(width: 2),
                        Text(
                          product.sellerTrustScore.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppPalette.text),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                              color: AppPalette.textFaint,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            product.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5,
                                color: AppPalette.textMuted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_hasPromo)
                                Text(
                                  "${product.priceMax} FCFA",
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppPalette.textFaint,
                                      decoration:
                                          TextDecoration.lineThrough),
                                ),
                              Text(
                                "${product.priceMin} FCFA",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppPalette.primaryDark,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: onAddToCart,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppPalette.primary,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: AppPalette.shadowSoft,
                            ),
                            child: const Icon(Icons.add_shopping_cart,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import '../buyer/buyer_store.dart';
import '../buyer/cart_page.dart';
import '../buyer/notifications_page.dart';
import '../buyer/rfq_compare_page.dart';
import '../chat/chat_hub_page.dart';
import '../orders/orders_page.dart';
import '../profile/profile_hub_page.dart';
import '../wallet/wallet_page.dart';
import '../business/rfqs_page.dart';
import 'feed_api_service.dart';
import 'feed_models.dart';
import 'product_publication_detail_page.dart';
import 'video_comments_page.dart';
import 'video_post_player.dart';

enum _SortMode { relevance, priceAsc, priceDesc, trust }

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late Future<FeedPayload> _feedFuture;
  final FeedApiService _api = FeedApiService();
  final ApiService _coreApi = ApiService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  static const String _filterDraftCacheKey = "feed_filters_draft_v1";

  int _currentIndex = 0;
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
  String _searchHint = "";
  double? _priceMinFilter;
  double? _priceMaxFilter;
  Set<int> _favoriteProductIds = const <int>{};
  List<Map<String, dynamic>> _savedFilters = const [];

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _restoreFilterDraft();
    _loadPersonalizationData();
    _feedFuture = _api.loadFeed(token: context.read<SessionStore>().token);
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final topic = (event["topic"] ?? "").toString();
      if (topic == "products" ||
          topic == "analytics" ||
          topic == "orders" ||
          topic == "wallets") {
        _reload(context.read<SessionStore>().token);
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final sortChoices = BackendUiConfigService.instance
          .readChoiceList(config, ["choices", "feed_sort_modes"]);
      final blockedKeywords = BackendUiConfigService.instance.readStringList(
          config, ["choices", "feed_image_blocked_keywords"]).toSet();
      final searchHint = BackendUiConfigService.instance
          .readString(config, ["defaults", "feed_search_hint"]);
      if (!mounted) return;
      setState(() {
        _sortChoices = sortChoices;
        _imageSearchBlockedKeywords = blockedKeywords;
        _searchHint = searchHint;
        if (sortChoices.isNotEmpty) {
          _sortMode = _sortModeFromKey(sortChoices.first["value"]!);
        }
      });
    } catch (_) {}
  }

  void _reload(String? token) {
    setState(() {
      _feedFuture = _api.loadFeed(token: token);
    });
    _loadPersonalizationData();
  }

  Future<void> _loadPersonalizationData() async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    try {
      final results = await Future.wait([
        _coreApi.getList("/api/product-favorites/", token: token),
        _coreApi.getList("/api/product-filters/", token: token),
      ]);
      final favorites = results[0]
          .map((row) => int.tryParse("${row["product"] ?? ""}"))
          .whereType<int>()
          .toSet();
      final filters = results[1];
      if (!mounted) return;
      setState(() {
        _favoriteProductIds = favorites;
        _savedFilters = filters;
      });
    } catch (_) {}
  }

  Future<void> _persistFilterDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      "selectedCategory": _selectedCategory,
      "selectedCountry": _selectedCountry,
      "search": _search,
      "imageSearchLabel": _imageSearchLabel,
      "imageSearchKeywords": _imageSearchKeywords.toList(),
      "onlyVerified": _onlyVerified,
      "sortMode": _sortModeKey(_sortMode),
      "priceMinFilter": _priceMinFilter,
      "priceMaxFilter": _priceMaxFilter,
    };
    await prefs.setString(_filterDraftCacheKey, jsonEncode(payload));
  }

  Future<void> _restoreFilterDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_filterDraftCacheKey);
    if (raw == null || raw.trim().isEmpty) return;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;

    final selectedCategory = (decoded["selectedCategory"] ?? "").toString();
    final selectedCountry = (decoded["selectedCountry"] ?? "").toString();
    final search = (decoded["search"] ?? "").toString();
    final imageSearchLabel = (decoded["imageSearchLabel"] ?? "").toString();
    final onlyVerified = (decoded["onlyVerified"] ?? false) == true;
    final sortMode = (decoded["sortMode"] ?? "").toString();
    final priceMin = double.tryParse("${decoded["priceMinFilter"] ?? ""}");
    final priceMax = double.tryParse("${decoded["priceMaxFilter"] ?? ""}");
    final rawKeywords =
        ((decoded["imageSearchKeywords"] as List?) ?? const <dynamic>[])
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toSet();

    if (!mounted) return;
    setState(() {
      if (selectedCategory.isNotEmpty) _selectedCategory = selectedCategory;
      if (selectedCountry.isNotEmpty) _selectedCountry = selectedCountry;
      _search = search;
      _imageSearchLabel = imageSearchLabel;
      _imageSearchKeywords = rawKeywords;
      _onlyVerified = onlyVerified;
      if (sortMode.isNotEmpty) _sortMode = _sortModeFromKey(sortMode);
      _priceMinFilter = priceMin;
      _priceMaxFilter = priceMax;
    });
  }

  void _setCategory(String value) {
    setState(() => _selectedCategory = value);
    unawaited(_persistFilterDraft());
  }

  void _setCountry(String value) {
    setState(() => _selectedCountry = value);
    unawaited(_persistFilterDraft());
  }

  void _setSortMode(String value) {
    setState(() => _sortMode = _sortModeFromKey(value));
    unawaited(_persistFilterDraft());
  }

  void _setOnlyVerified(bool value) {
    setState(() => _onlyVerified = value);
    unawaited(_persistFilterDraft());
  }

  void _setPriceRange(double start, double end) {
    setState(() {
      _priceMinFilter = start;
      _priceMaxFilter = end;
    });
    unawaited(_persistFilterDraft());
  }

  void _setSearch(String value) {
    setState(() => _search = value);
    unawaited(_persistFilterDraft());
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
      await _coreApi.post(
        "/api/product-favorites/toggle/",
        {"product_id": product.id},
        token: token,
      );
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
        SnackBar(
            content: Text(_coreApi.toUserMessage(e,
                fallback: "Action favoris echouee."))),
      );
    }
  }

  Future<void> _saveCurrentFilter() async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    final nameController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Sauvegarder ce filtre"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: "Nom du filtre"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Sauvegarder"),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      nameController.dispose();
      return;
    }
    final name = nameController.text.trim();
    nameController.dispose();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Donnez un nom a ce filtre.")),
      );
      return;
    }
    try {
      await _coreApi.post(
        "/api/product-filters/",
        {
          "name": name,
          "query": _search,
          "category": _selectedCategory == "Tous" ? "" : _selectedCategory,
          "country_code": _selectedCountry == "Tous" ? "" : _selectedCountry,
          "min_price": _priceMinFilter,
          "max_price": _priceMaxFilter,
          "only_verified": _onlyVerified,
          "sort_mode": _sortModeKey(_sortMode),
        },
        token: token,
      );
      await _loadPersonalizationData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Filtre sauvegarde.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_coreApi.toUserMessage(e,
                fallback: "Sauvegarde filtre impossible."))),
      );
    }
  }

  void _applySavedFilter(Map<String, dynamic> filter) {
    setState(() {
      final category = (filter["category"] ?? "").toString().trim();
      final countryCode = (filter["country_code"] ?? "").toString().trim();
      _selectedCategory = category.isEmpty ? "Tous" : category;
      _selectedCountry = countryCode.isEmpty ? "Tous" : countryCode;
      _search = (filter["query"] ?? "").toString();
      _onlyVerified = (filter["only_verified"] ?? false) == true;
      _sortMode =
          _sortModeFromKey((filter["sort_mode"] ?? "relevance").toString());
      _priceMinFilter = double.tryParse("${filter["min_price"] ?? ""}");
      _priceMaxFilter = double.tryParse("${filter["max_price"] ?? ""}");
    });
    unawaited(_persistFilterDraft());
  }

  Future<void> _deleteSavedFilter(int id) async {
    final token = context.read<SessionStore>().token;
    if ((token ?? "").trim().isEmpty) return;
    try {
      await _coreApi.delete("/api/product-filters/$id/", token: token);
      await _loadPersonalizationData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Filtre supprime.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_coreApi.toUserMessage(e,
                fallback: "Suppression filtre impossible."))),
      );
    }
  }

  Future<void> _searchByImage() async {
    final session = context.read<SessionStore>();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (!mounted || picked == null || picked.files.isEmpty) {
      return;
    }
    final fileName = picked.files.single.name;
    final keywords = _extractImageKeywords(fileName);
    final query = keywords.join(" ");
    final matches = await _api.imageSearch(query: query, token: session.token);
    if (!mounted) return;
    setState(() {
      _imageSearchLabel = fileName;
      _imageSearchKeywords = keywords;
      _imageSearchProductIds = matches.map((e) => e.id).toSet();
    });
    unawaited(_persistFilterDraft());
    final message = keywords.isEmpty
        ? "Image chargee. Aucun mot cle detecte dans le nom du fichier."
        : "Recherche image active: ${keywords.join(", ")} (${matches.length} resultat(s))";
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    await _api.trackProductView(productId: product.id, token: session.token);
    if (!mounted) return;
    _reload(session.token);
  }

  Set<String> _extractImageKeywords(String fileName) {
    return RegExp(r"[a-zA-Z0-9]{3,}")
        .allMatches(fileName.toLowerCase())
        .map((m) => m.group(0)!)
        .where((token) => !_imageSearchBlockedKeywords.contains(token))
        .toSet();
  }

  _SortMode _sortModeFromKey(String key) {
    switch (key) {
      case "priceAsc":
        return _SortMode.priceAsc;
      case "priceDesc":
        return _SortMode.priceDesc;
      case "trust":
        return _SortMode.trust;
      default:
        return _SortMode.relevance;
    }
  }

  String _sortModeKey(_SortMode mode) {
    switch (mode) {
      case _SortMode.priceAsc:
        return "priceAsc";
      case _SortMode.priceDesc:
        return "priceDesc";
      case _SortMode.trust:
        return "trust";
      case _SortMode.relevance:
        return "relevance";
    }
  }

  void _resetFilters({required double minPrice, required double maxPrice}) {
    setState(() {
      _selectedCategory = "Tous";
      _selectedCountry = "Tous";
      _search = "";
      _imageSearchLabel = "";
      _imageSearchKeywords = const {};
      _imageSearchProductIds = null;
      _onlyVerified = false;
      _priceMinFilter = minPrice;
      _priceMaxFilter = maxPrice;
      if (_sortChoices.isNotEmpty) {
        _sortMode = _sortModeFromKey(_sortChoices.first["value"]!);
      } else {
        _sortMode = _SortMode.relevance;
      }
    });
    unawaited(_persistFilterDraft());
  }

  ({double min, double max}) _priceBounds(List<ProductCardData> products) {
    if (products.isEmpty) {
      return (min: 0, max: 0);
    }
    var minPrice = products.first.priceMin.toDouble();
    var maxPrice = products.first.priceMax.toDouble();
    for (final p in products) {
      minPrice = math.min(minPrice, p.priceMin.toDouble());
      maxPrice = math.max(maxPrice, p.priceMax.toDouble());
    }
    if (maxPrice < minPrice) {
      final swap = minPrice;
      minPrice = maxPrice;
      maxPrice = swap;
    }
    return (min: minPrice, max: maxPrice);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final buyerStore = context.watch<BuyerStore>();
    final canPublishAds = session.role == UserRole.supplier ||
        session.role == UserRole.wholesaler;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(session),
            Expanded(
              child: FutureBuilder<FeedPayload>(
                future: _feedFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const AppLoadingState(
                        label: "Chargement du feed...");
                  }
                  if (snapshot.hasError) {
                    return AppErrorState(
                      message: "Le feed est temporairement indisponible.",
                      onRetry: () => _reload(session.token),
                    );
                  }
                  if (!snapshot.hasData) {
                    return AppErrorState(
                      message: "Impossible de charger les donnees.",
                      onRetry: () => _reload(session.token),
                    );
                  }
                  final payload = snapshot.data!;
                  final catalogProducts = payload.products
                      .where((p) => (p.videoUrl ?? "").trim().isEmpty)
                      .toList();
                  final bounds = _priceBounds(catalogProducts);
                  final currentMin = _priceMinFilter ?? bounds.min;
                  final currentMax = _priceMaxFilter ?? bounds.max;
                  final products = _filteredProducts(
                      catalogProducts, buyerStore, currentMin, currentMax);
                  final pages = <Widget>[
                    _ProductsScreen(
                      products: products,
                      allProducts: catalogProducts,
                      usingOfflineFallback: payload.usingFallback,
                      imageSearchLabel: _imageSearchLabel,
                      selectedCategory: _selectedCategory,
                      selectedCountry: _selectedCountry,
                      onlyVerified: _onlyVerified,
                      sortModeKey: _sortModeKey(_sortMode),
                      sortChoices: _sortChoices,
                      searchHint: _searchHint,
                      minPriceBound: bounds.min,
                      maxPriceBound: bounds.max,
                      selectedMinPrice: currentMin,
                      selectedMaxPrice: currentMax,
                      favoriteProductIds: _favoriteProductIds,
                      savedFilters: _savedFilters,
                      onCategorySelected: _setCategory,
                      onCountrySelected: _setCountry,
                      onSortChanged: _setSortMode,
                      onOnlyVerifiedChanged: _setOnlyVerified,
                      onPriceRangeChanged: _setPriceRange,
                      onSearchChanged: _setSearch,
                      onImageSearchRequested: _searchByImage,
                      onClearImageSearch: _clearImageSearch,
                      onSaveCurrentFilter: _saveCurrentFilter,
                      onApplySavedFilter: _applySavedFilter,
                      onDeleteSavedFilter: _deleteSavedFilter,
                      onToggleFavorite: (product) =>
                          unawaited(_toggleFavorite(product)),
                      onResetFilters: () => _resetFilters(
                        minPrice: bounds.min,
                        maxPrice: bounds.max,
                      ),
                      onProductOpened: (product) =>
                          unawaited(_onProductOpened(product)),
                    ),
                    _VideosScreen(
                        videos: payload.videos, canPublishAds: canPublishAds),
                    const ChatHubPage(),
                    const OrdersPage(),
                    ProfileHubPage(onRefresh: () => _reload(session.token)),
                  ];
                  return pages[_currentIndex];
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x16000000),
                  blurRadius: 18,
                  offset: Offset(0, 8))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: NavigationBar(
              backgroundColor: Colors.white,
              selectedIndex: _currentIndex,
              onDestinationSelected: (v) => setState(() => _currentIndex = v),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.shopping_bag_outlined),
                    selectedIcon: Icon(Icons.shopping_bag),
                    label: "Produits"),
                NavigationDestination(
                    icon: Icon(Icons.smart_display_outlined),
                    selectedIcon: Icon(Icons.smart_display),
                    label: "Video"),
                NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline),
                    selectedIcon: Icon(Icons.chat_bubble),
                    label: "Messages"),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: "Orders"),
                NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: "Profile"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(SessionStore session) {
    final store = context.watch<BuyerStore>();
    final cartCount = store.cartItems.length;
    final unreadNotifications = store.unreadNotificationsCount;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 5))
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(0xFF15803D),
                  child: Icon(Icons.storefront, color: Colors.white, size: 18)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Buyer Hub",
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18)),
                      Text("Alibaba-like marketplace",
                          style:
                              TextStyle(fontSize: 11, color: Colors.black54)),
                    ]),
              ),
              Badge(
                label: Text(unreadNotifications.toString()),
                isLabelVisible: unreadNotifications > 0,
                child: IconButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const NotificationsPage()),
                    );
                    if (!mounted) return;
                    context.read<BuyerStore>().markAllNotificationsRead();
                  },
                  icon: const Icon(Icons.notifications_outlined),
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
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              CartPage(products: payload.products)));
                    } catch (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                "Impossible de charger le panier pour le moment.")),
                      );
                    }
                  },
                  icon: const Icon(Icons.shopping_cart_outlined),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletPage())),
                icon: const Icon(Icons.account_balance_wallet_outlined),
              ),
              Chip(
                avatar: const Icon(Icons.verified_user_outlined, size: 16),
                label: Text(session.role.name),
              )
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RfqsPage())),
                  icon: const Icon(Icons.request_quote_outlined),
                  label: const Text("Créer RFQ"),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RfqComparePage())),
                  icon: const Icon(Icons.compare_arrows),
                  label: const Text("Comparer offres"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<ProductCardData> _filteredProducts(
    List<ProductCardData> products,
    BuyerStore store,
    double selectedMinPrice,
    double selectedMaxPrice,
  ) {
    Iterable<ProductCardData> result =
        products.where((p) => (p.videoUrl ?? "").trim().isEmpty);
    if (_selectedCategory != "Tous") {
      result = result.where(
          (p) => p.category.toLowerCase() == _selectedCategory.toLowerCase());
    }
    if (_selectedCountry != "Tous") {
      result = result.where((p) =>
          p.sellerCountryCode.toUpperCase() == _selectedCountry.toUpperCase());
    }
    if (_onlyVerified) {
      result = result.where((p) => p.sellerVerified);
    }
    result = result.where((p) {
      final price = p.priceMax.toDouble();
      return price >= selectedMinPrice && price <= selectedMaxPrice;
    });
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      result = result.where((p) =>
          p.title.toLowerCase().contains(q) ||
          p.brand.toLowerCase().contains(q) ||
          p.sellerDisplayName.toLowerCase().contains(q));
    }
    if (_imageSearchKeywords.isNotEmpty) {
      result = result.where((p) {
        final haystack = "${p.title} ${p.brand} ${p.category} ${p.description}"
            .toLowerCase();
        return _imageSearchKeywords.any(haystack.contains);
      });
    }
    if (_imageSearchProductIds != null) {
      result = result.where((p) => _imageSearchProductIds!.contains(p.id));
    }
    final list = result.toList();
    list.sort((a, b) {
      final scoreA = store.preferenceScoreFor(
        productId: a.id,
        title: a.title,
        brand: a.brand,
        priceMin: a.priceMin,
        priceMax: a.priceMax,
        locality: a.sellerCountryCode,
      );
      final scoreB = store.preferenceScoreFor(
        productId: b.id,
        title: b.title,
        brand: b.brand,
        priceMin: b.priceMin,
        priceMax: b.priceMax,
        locality: b.sellerCountryCode,
      );
      final scoreDiff = scoreB.compareTo(scoreA);
      if (scoreDiff != 0) {
        return scoreDiff;
      }

      switch (_sortMode) {
        case _SortMode.priceAsc:
          return a.priceMax.compareTo(b.priceMax);
        case _SortMode.priceDesc:
          return b.priceMin.compareTo(a.priceMin);
        case _SortMode.trust:
          return b.sellerTrustScore.compareTo(a.sellerTrustScore);
        case _SortMode.relevance:
          return b.sellerTrustScore.compareTo(a.sellerTrustScore);
      }
    });
    return list;
  }
}

class _ProductsScreen extends StatelessWidget {
  const _ProductsScreen({
    required this.products,
    required this.allProducts,
    required this.usingOfflineFallback,
    required this.imageSearchLabel,
    required this.selectedCategory,
    required this.selectedCountry,
    required this.onlyVerified,
    required this.sortModeKey,
    required this.sortChoices,
    required this.searchHint,
    required this.minPriceBound,
    required this.maxPriceBound,
    required this.selectedMinPrice,
    required this.selectedMaxPrice,
    required this.favoriteProductIds,
    required this.savedFilters,
    required this.onCategorySelected,
    required this.onCountrySelected,
    required this.onSortChanged,
    required this.onOnlyVerifiedChanged,
    required this.onPriceRangeChanged,
    required this.onSearchChanged,
    required this.onImageSearchRequested,
    required this.onClearImageSearch,
    required this.onSaveCurrentFilter,
    required this.onApplySavedFilter,
    required this.onDeleteSavedFilter,
    required this.onToggleFavorite,
    required this.onResetFilters,
    required this.onProductOpened,
  });

  final List<ProductCardData> products;
  final List<ProductCardData> allProducts;
  final bool usingOfflineFallback;
  final String imageSearchLabel;
  final String selectedCategory;
  final String selectedCountry;
  final bool onlyVerified;
  final String sortModeKey;
  final List<Map<String, String>> sortChoices;
  final String searchHint;
  final double minPriceBound;
  final double maxPriceBound;
  final double selectedMinPrice;
  final double selectedMaxPrice;
  final Set<int> favoriteProductIds;
  final List<Map<String, dynamic>> savedFilters;
  final ValueChanged<String> onCategorySelected;
  final ValueChanged<String> onCountrySelected;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<bool> onOnlyVerifiedChanged;
  final void Function(double start, double end) onPriceRangeChanged;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onImageSearchRequested;
  final VoidCallback onClearImageSearch;
  final Future<void> Function() onSaveCurrentFilter;
  final ValueChanged<Map<String, dynamic>> onApplySavedFilter;
  final Future<void> Function(int id) onDeleteSavedFilter;
  final ValueChanged<ProductCardData> onToggleFavorite;
  final VoidCallback onResetFilters;
  final ValueChanged<ProductCardData> onProductOpened;

  @override
  Widget build(BuildContext context) {
    final categories = <String>{"Tous", ...allProducts.map((e) => e.category)};
    final countries = <String>{
      "Tous",
      ...allProducts.map((e) => e.sellerCountryCode.toUpperCase())
    };
    final priceRangeEnabled = maxPriceBound > minPriceBound;
    final hasCustomPrice = (selectedMinPrice - minPriceBound).abs() > 0.5 ||
        (selectedMaxPrice - maxPriceBound).abs() > 0.5;
    final activeFiltersCount = [
      selectedCategory != "Tous",
      selectedCountry != "Tous",
      onlyVerified,
      hasCustomPrice,
      imageSearchLabel.isNotEmpty,
    ].where((v) => v).length;
    final spotlight = products;
    final bestDeals = spotlight.take(12).toList();
    final customSelection = spotlight.length > 6
        ? spotlight.skip(3).take(12).toList()
        : spotlight.take(12).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        if (usingOfflineFallback)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF97316)),
            ),
            child: const Text(
              "Mode hors-ligne actif: affichage des donnees locales en cache.",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFF97316), width: 2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: onSearchChanged,
                  decoration: InputDecoration(
                    hintText: searchHint,
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onImageSearchRequested,
                child: Container(
                  width: 38,
                  height: 30,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF111827))),
                  child: const Icon(Icons.camera_alt_outlined, size: 18),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: imageSearchLabel.isNotEmpty ? onClearImageSearch : null,
                child: Container(
                  width: 46,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                        colors: [Color(0xFFF97316), Color(0xFFFF8A00)]),
                  ),
                  child: Icon(
                    imageSearchLabel.isNotEmpty
                        ? Icons.close
                        : Icons.auto_awesome,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (imageSearchLabel.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Chip(
                  avatar: const Icon(Icons.image_search, size: 18),
                  label: Text(
                    "Recherche image: $imageSearchLabel",
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onClearImageSearch,
                icon: const Icon(Icons.close, size: 16),
                label: const Text("Retirer"),
              )
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            if (activeFiltersCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF97316),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_list, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '$activeFiltersCount filtre(s) actif(s)',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              )
            else
              const Text(
                "Tous les produits",
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black54),
              ),
            const Spacer(),
            if (activeFiltersCount > 0)
              TextButton.icon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.restart_alt),
                label: const Text("Réinitialiser"),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            FilledButton.tonalIcon(
              onPressed: () => onSaveCurrentFilter(),
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text("Sauvegarder filtre"),
            ),
            const SizedBox(width: 8),
            Text(
              "${savedFilters.length} filtre(s)",
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        if (savedFilters.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: savedFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = savedFilters[index];
                final id = int.tryParse("${filter["id"] ?? ""}") ?? 0;
                final name = (filter["name"] ?? "Filtre").toString();
                return InputChip(
                  label: Text(name),
                  onPressed: () => onApplySavedFilter(filter),
                  onDeleted: id <= 0 ? null : () => onDeleteSavedFilter(id),
                  deleteIcon: const Icon(Icons.close, size: 16),
                );
              },
            ),
          ),
        ],
        if (priceRangeEnabled)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
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
                      const Text(
                        "Plage de prix (FCFA)",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      Text(
                        "${selectedMinPrice.toInt()} - ${selectedMaxPrice.toInt()}",
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                RangeSlider(
                  values: RangeValues(selectedMinPrice, selectedMaxPrice),
                  min: minPriceBound,
                  max: maxPriceBound,
                  divisions: 20,
                  labels: RangeLabels(
                    selectedMinPrice.toInt().toString(),
                    selectedMaxPrice.toInt().toString(),
                  ),
                  onChanged: (values) =>
                      onPriceRangeChanged(values.start, values.end),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          AppEmptyState(
            title: allProducts.isEmpty
                ? "Aucun produit disponible"
                : "Aucun resultat avec les filtres",
            subtitle: allProducts.isEmpty
                ? "Le catalogue sera alimente des qu'un vendeur publie."
                : "Ajustez vos filtres ou reinitialisez pour revoir tout le catalogue.",
            onRetry: allProducts.isEmpty ? null : onResetFilters,
            retryLabel: "Reinitialiser filtres",
            icon: Icons.search_off,
          )
        else ...[
          const Row(
            children: [
              Expanded(
                  child: _QuickAction(
                      icon: Icons.category_outlined,
                      label: "Explorer par\ncategories")),
              SizedBox(width: 8),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.track_changes, label: "Demander un\ndevis")),
              SizedBox(width: 8),
              Expanded(
                  child: _QuickAction(
                      icon: Icons.emoji_events_outlined,
                      label: "Produits au top\ndu classement")),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: spotlight.length.clamp(0, 10),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = spotlight[index];
                return _MiniProductTile(
                  item: item,
                  isFavorite: favoriteProductIds.contains(item.id),
                  onToggleFavorite: () => onToggleFavorite(item),
                  onProductOpened: onProductOpened,
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final category = categories.elementAt(index);
              return ChoiceChip(
                label: Text(category,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                selected: category == selectedCategory,
                onSelected: (_) => onCategorySelected(category),
                backgroundColor: Colors.white,
                selectedColor: const Color(0xFFFFEDD5),
                side: BorderSide(
                    color: category == selectedCategory
                        ? const Color(0xFFF97316)
                        : const Color(0xFFE5E7EB)),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PopupMenuButton<String>(
              initialValue: selectedCountry,
              onSelected: onCountrySelected,
              itemBuilder: (context) => countries
                  .map((e) => PopupMenuItem(value: e, child: Text("Pays: $e")))
                  .toList(),
              child: Chip(
                  label: Text("Pays: $selectedCountry"),
                  avatar: const Icon(Icons.public, size: 18)),
            ),
            PopupMenuButton<String>(
              initialValue: sortChoices.any((c) => c["value"] == sortModeKey)
                  ? sortModeKey
                  : null,
              onSelected: onSortChanged,
              itemBuilder: (context) => sortChoices
                  .map(
                    (choice) => PopupMenuItem<String>(
                      value: choice["value"],
                      child: Text("Tri: ${choice["label"] ?? choice["value"]}"),
                    ),
                  )
                  .toList(),
              child: const Chip(
                  label: Text("Trier"),
                  avatar: Icon(Icons.swap_vert, size: 18)),
            ),
            FilterChip(
              label: const Text("Certifie"),
              selected: onlyVerified,
              onSelected: onOnlyVerifiedChanged,
            ),
          ],
        ),
        if (products.isNotEmpty) ...[
          const SizedBox(height: 12),
          _OfferSection(
            title: "Meilleures offres",
            subtitle: "Trouvez les meilleurs prix sur Marche CM",
            products: bestDeals,
            favoriteProductIds: favoriteProductIds,
            onToggleFavorite: onToggleFavorite,
            onProductOpened: onProductOpened,
          ),
          const SizedBox(height: 12),
          _OfferSection(
            title: "Selections sur mesure",
            subtitle: "Produits recommandes selon vos recherches",
            products: customSelection,
            favoriteProductIds: favoriteProductIds,
            onToggleFavorite: onToggleFavorite,
            onProductOpened: onProductOpened,
          ),
        ],
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFF97316), size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12))),
        ],
      ),
    );
  }
}

class _MiniProductTile extends StatelessWidget {
  const _MiniProductTile({
    required this.item,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onProductOpened,
  });

  final ProductCardData item;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final ValueChanged<ProductCardData> onProductOpened;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        onProductOpened(item);
        Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ProductPublicationDetailPage(product: item)));
      },
      child: Container(
        width: 126,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Image.network(
                      item.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) => const ColoredBox(
                          color: Color(0xFFF1F5F9),
                          child: Center(
                              child: Icon(Icons.image_not_supported_outlined))),
                    ),
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        onPressed: onToggleFavorite,
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF374151),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    item.referenceCode.isEmpty
                        ? "Ref: PRD-${item.id}"
                        : "Ref: ${item.referenceCode}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferSection extends StatelessWidget {
  const _OfferSection(
      {required this.title,
      required this.subtitle,
      required this.products,
      required this.favoriteProductIds,
      required this.onToggleFavorite,
      required this.onProductOpened});

  final String title;
  final String subtitle;
  final List<ProductCardData> products;
  final Set<int> favoriteProductIds;
  final ValueChanged<ProductCardData> onToggleFavorite;
  final ValueChanged<ProductCardData> onProductOpened;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BuyerStore>();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x12000000), blurRadius: 12, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 22))),
              const Icon(Icons.arrow_forward, size: 24),
            ],
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 10),
          SizedBox(
            height: 250,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: products.length.clamp(0, 12),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = products[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    onProductOpened(item);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ProductPublicationDetailPage(product: item)));
                  },
                  child: Container(
                    width: 158,
                    decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12)),
                              child: Image.network(
                                item.imageUrl,
                                height: 124,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, _, __) => const SizedBox(
                                    height: 124,
                                    child: ColoredBox(
                                        color: Color(0xFFF1F5F9),
                                        child: Center(
                                            child: Icon(Icons
                                                .image_not_supported_outlined)))),
                              ),
                            ),
                            Positioned(
                              right: 6,
                              top: 6,
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 16,
                                  onPressed: () => onToggleFavorite(item),
                                  icon: Icon(
                                    favoriteProductIds.contains(item.id)
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: favoriteProductIds.contains(item.id)
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFF374151),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
                          child: Text(
                            "${item.priceMin} FCFA",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB91C1C)),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(
                                  item.referenceCode.isEmpty
                                      ? "Ref: PRD-${item.id}"
                                      : "Ref: ${item.referenceCode}",
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                          child: SizedBox(
                            width: double.infinity,
                            height: 30,
                            child: FilledButton.tonal(
                              onPressed: () {
                                onProductOpened(item);
                                context.read<BuyerStore>().addToCart(item.id);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("Ajoute au panier")));
                              },
                              style: FilledButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text("Ajouter"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (store.cartItems.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text("${store.cartItems.length} article(s) dans le panier",
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _VideosScreen extends StatefulWidget {
  const _VideosScreen({required this.videos, required this.canPublishAds});
  final List<VideoPostData> videos;
  final bool canPublishAds;

  @override
  State<_VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends State<_VideosScreen> {
  final ApiService _api = ApiService();
  final Map<int, bool> _likedByProductId = {};
  final Map<int, int> _likeCountByProductId = {};

  @override
  void initState() {
    super.initState();
    for (final video in widget.videos) {
      _likeCountByProductId[video.id] = video.likes;
    }
  }

  Future<void> _toggleLike(VideoPostData video) async {
    final token = context.read<SessionStore>().token;
    final wasLiked = _likedByProductId[video.id] ?? false;
    setState(() {
      _likedByProductId[video.id] = !wasLiked;
      _likeCountByProductId[video.id] =
          (_likeCountByProductId[video.id] ?? video.likes) + (wasLiked ? -1 : 1);
    });
    try {
      final result = await _api.post(
        "/api/video-likes/toggle/",
        {"product_id": video.id},
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _likedByProductId[video.id] = (result["liked"] ?? !wasLiked) == true;
        _likeCountByProductId[video.id] =
            int.tryParse("${result["total_likes"] ?? ""}") ??
                _likeCountByProductId[video.id]!;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likedByProductId[video.id] = wasLiked;
        _likeCountByProductId[video.id] =
            (_likeCountByProductId[video.id] ?? video.likes) + (wasLiked ? 1 : -1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) {
      return const AppEmptyState(
        title: "Aucune video publiee",
        subtitle: "Les publications video des vendeurs apparaitront ici.",
        icon: Icons.smart_display_outlined,
      );
    }
    return Stack(
      children: [
        PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: widget.videos.length,
          itemBuilder: (context, index) {
            final video = widget.videos[index];
            final liked = _likedByProductId[video.id] ?? false;
            final likeCount = _likeCountByProductId[video.id] ?? video.likes;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.videoUrl != null && video.videoUrl!.isNotEmpty)
                      VideoPostPlayer(
                          videoUrl: video.videoUrl!, coverUrl: video.coverUrl)
                    else
                      Image.network(video.coverUrl, fit: BoxFit.cover),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [
                              Color(0x99000000),
                              Color(0x00000000),
                              Color(0xAA000000)
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 24,
                      child: Column(
                        children: [
                          _ActionIcon(
                              icon: Icons.person_pin_circle_outlined,
                              label: "Compte",
                              onTap: () {}),
                          const SizedBox(height: 12),
                          _ActionIcon(
                            icon: liked ? Icons.favorite : Icons.favorite_border,
                            label: "$likeCount",
                            active: liked,
                            onTap: () => unawaited(_toggleLike(video)),
                          ),
                          const SizedBox(height: 12),
                          _ActionIcon(
                              icon: Icons.mode_comment_outlined,
                              label: "${video.comments.length}",
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          VideoCommentsPage(video: video)))),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 90,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("@${video.publisherName}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          const SizedBox(height: 6),
                          Text(video.description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        ),
        if (widget.canPublishAds)
          const SizedBox.shrink()
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xCC111827),
              child: Icon(icon,
                  color: active ? Colors.redAccent : Colors.white, size: 22)),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      ],
    );
  }
}

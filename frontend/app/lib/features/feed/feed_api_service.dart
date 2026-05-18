import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import 'feed_models.dart';

class FeedPayload {
  const FeedPayload({
    required this.products,
    required this.videos,
    required this.usingFallback,
  });

  final List<ProductCardData> products;
  final List<VideoPostData> videos;
  final bool usingFallback;
}

class FeedApiService {
  FeedApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _feedCacheKey = "feed_products_cache_v1";

  Future<FeedPayload> loadFeed({String? token}) async {
    try {
      final products = await _loadRecommendedOrProducts(token: token);
      if (products.isNotEmpty) {
        await _cacheProducts(products);
      }
      if (products.isEmpty) {
        final cachedProducts = await _loadCachedProducts();
        if (cachedProducts.isNotEmpty) {
          final cachedVideos = _videosFromProducts(cachedProducts);
          return FeedPayload(
            products: cachedProducts,
            videos: cachedVideos,
            usingFallback: true,
          );
        }
      }

      final videos = _videosFromProducts(products);

      return FeedPayload(
        products: products,
        videos: videos,
        usingFallback: false,
      );
    } catch (_) {
      final cachedProducts = await _loadCachedProducts();
      if (cachedProducts.isNotEmpty) {
        return FeedPayload(
          products: cachedProducts,
          videos: _videosFromProducts(cachedProducts),
          usingFallback: true,
        );
      }
      return const FeedPayload(
        products: <ProductCardData>[],
        videos: <VideoPostData>[],
        usingFallback: true,
      );
    }
  }

  List<VideoPostData> _videosFromProducts(List<ProductCardData> products) {
    return products
        .where((p) => p.videoUrl != null && p.videoUrl!.isNotEmpty)
        .map(
          (p) => VideoPostData(
            id: p.id,
            coverUrl: p.imageUrl,
            publisherName: p.sellerDisplayName,
            publisherAvatar: p.sellerAvatarUrl.isEmpty
                ? "https://i.pravatar.cc/200?u=${p.sellerReferenceCode}"
                : p.sellerAvatarUrl,
            description: p.description.isEmpty ? p.title : p.description,
            likes: 0,
            comments: const [],
            sellerId: p.sellerId,
            videoUrl: p.videoUrl,
          ),
        )
        .toList();
  }

  Future<void> _cacheProducts(List<ProductCardData> products) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(products.map(_productToMap).toList());
    await prefs.setString(_feedCacheKey, encoded);
  }

  Future<List<ProductCardData>> _loadCachedProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_feedCacheKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(_productFromMap)
          .whereType<ProductCardData>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _productToMap(ProductCardData product) {
    return {
      "id": product.id,
      "referenceCode": product.referenceCode,
      "title": product.title,
      "imageUrl": product.imageUrl,
      "category": product.category,
      "brand": product.brand,
      "minQty": product.minQty,
      "maxQty": product.maxQty,
      "priceMin": product.priceMin,
      "priceMax": product.priceMax,
      "weightKg": product.weightKg,
      "sellerId": product.sellerId,
      "sellerReferenceCode": product.sellerReferenceCode,
      "sellerDisplayName": product.sellerDisplayName,
      "sellerAvatarUrl": product.sellerAvatarUrl,
      "sellerCountryCode": product.sellerCountryCode,
      "sellerCity": product.sellerCity,
      "sellerLocationLabel": product.sellerLocationLabel,
      "sellerLatitude": product.sellerLatitude,
      "sellerLongitude": product.sellerLongitude,
      "sellerVerified": product.sellerVerified,
      "sellerTrustScore": product.sellerTrustScore,
      "allowsGrouping": product.allowsGrouping,
      "description": product.description,
      "videoUrl": product.videoUrl,
    };
  }

  ProductCardData? _productFromMap(Map<String, dynamic> json) {
    final id = _toInt(json["id"]);
    final title = (json["title"] ?? "").toString();
    if (id == null || title.isEmpty) {
      return null;
    }
    final rawImageUrl = (json["imageUrl"] ?? "").toString();
    final rawSellerAvatarUrl = (json["sellerAvatarUrl"] ?? "").toString();
    final rawVideoUrl = (json["videoUrl"] ?? "").toString();
    final resolvedVideoUrl = _resolveMediaUrl(rawVideoUrl);
    return ProductCardData(
      id: id,
      referenceCode: (json["referenceCode"] ?? "").toString(),
      title: title,
      imageUrl: _resolveMediaUrl(rawImageUrl),
      category: (json["category"] ?? "").toString(),
      brand: (json["brand"] ?? "").toString(),
      minQty: _toInt(json["minQty"]) ?? 1,
      maxQty: _toInt(json["maxQty"]) ?? 1,
      priceMin: _toInt(json["priceMin"]) ?? 0,
      priceMax: _toInt(json["priceMax"]) ?? 0,
      weightKg: _toDouble(json["weightKg"]) ?? 0,
      sellerId: _toInt(json["sellerId"]) ?? 0,
      sellerReferenceCode: (json["sellerReferenceCode"] ?? "").toString(),
      sellerDisplayName: (json["sellerDisplayName"] ?? "").toString(),
      sellerAvatarUrl: _resolveMediaUrl(rawSellerAvatarUrl),
      sellerCountryCode: (json["sellerCountryCode"] ?? "").toString(),
      sellerCity: (json["sellerCity"] ?? "").toString(),
      sellerLocationLabel: (json["sellerLocationLabel"] ?? "").toString(),
      sellerLatitude: _toDouble(json["sellerLatitude"]),
      sellerLongitude: _toDouble(json["sellerLongitude"]),
      sellerVerified: (json["sellerVerified"] ?? false) == true,
      sellerTrustScore: _toDouble(json["sellerTrustScore"]) ?? 0,
      allowsGrouping: (json["allowsGrouping"] ?? false) == true,
      description: (json["description"] ?? "").toString(),
      videoUrl: resolvedVideoUrl.isEmpty ? null : resolvedVideoUrl,
    );
  }

  ProductCardData? _toProductCard(Map<String, dynamic> json) {
    final id = _toInt(json["id"]);
    final title = (json["title"] ?? "").toString();
    if (id == null || title.isEmpty) {
      return null;
    }
    final imagePath = (json["image"] ?? "").toString();
    final videoPath = (json["video"] ?? "").toString();
    final imageUrl = _resolveMediaUrl(imagePath);
    return ProductCardData(
      id: id,
      referenceCode: (json["reference_code"] ?? "").toString(),
      title: title,
      imageUrl: imageUrl,
      category: (json["category_label"] ?? json["category"] ?? "").toString(),
      brand: (json["brand"] ?? "").toString(),
      minQty: _toInt(json["min_order_qty"]) ?? 1,
      maxQty: _toInt(json["max_order_qty"]) ?? 1,
      priceMin: _toInt(json["price_for_min_qty"]) ?? 0,
      priceMax: _toInt(json["price_for_max_qty"]) ?? 0,
      weightKg: _toDouble(json["weight_kg"]) ?? 0,
      sellerId: _toInt(json["seller"]) ?? 0,
      sellerReferenceCode: (json["seller_reference_code"] ?? "").toString(),
      sellerDisplayName: (json["seller_username"] ?? "").toString(),
      sellerAvatarUrl:
          _resolveMediaUrl((json["seller_avatar_url"] ?? "").toString()),
      sellerCountryCode: (json["seller_country_code"] ?? "").toString(),
      sellerCity: (json["seller_city"] ?? "").toString(),
      sellerLocationLabel: (json["seller_location_label"] ?? "").toString(),
      sellerLatitude: _toDouble(json["seller_location_latitude"]),
      sellerLongitude: _toDouble(json["seller_location_longitude"]),
      sellerVerified: (json["seller_is_verified"] ?? false) == true,
      sellerTrustScore: _toDouble(json["seller_trust_score"]) ?? 0,
      allowsGrouping: (json["allows_group_campaign"] ?? false) == true,
      description: (json["description"] ?? "").toString(),
      videoUrl: videoPath.isEmpty ? null : _resolveMediaUrl(videoPath),
    );
  }

  int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.toString().split(".").first);
  }

  double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    return double.tryParse(value.toString());
  }

  String _resolveMediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == "null") {
      return "";
    }
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.scheme == "http" || uri.scheme == "https")) {
      if (_isLoopbackHost(uri.host)) {
        final origin = _apiOrigin();
        if (origin.isNotEmpty) {
          final path = uri.path.isEmpty ? "/" : uri.path;
          final query = uri.hasQuery ? "?${uri.query}" : "";
          return "$origin$path$query";
        }
      }
      return value;
    }
    if (uri != null && uri.scheme == "file") {
      if (uri.path.startsWith("/media/")) {
        final apiBase = _apiBase();
        if (apiBase.isNotEmpty) {
          return "$apiBase${uri.path}";
        }
      }
      return "";
    }
    if (value.startsWith("data:")) {
      return value;
    }
    final normalized = value.startsWith("/") ? value : "/$value";
    final apiBase = _apiBase();
    if (apiBase.isEmpty) {
      return normalized;
    }
    return "$apiBase$normalized";
  }

  String _apiBase() {
    return AppConfig.apiBaseUrl.trim().replaceAll(RegExp(r"/+$"), "");
  }

  String _apiOrigin() {
    final base = Uri.tryParse(_apiBase());
    if (base == null || base.scheme.isEmpty || base.host.isEmpty) {
      return "";
    }
    final port = base.hasPort ? ":${base.port}" : "";
    return "${base.scheme}://${base.host}$port";
  }

  bool _isLoopbackHost(String host) {
    final value = host.toLowerCase().trim();
    return value == "127.0.0.1" || value == "localhost" || value == "0.0.0.0";
  }

  Future<List<ProductCardData>> imageSearch(
      {required String query, String? token}) async {
    if (query.trim().isEmpty) {
      return const [];
    }
    try {
      final uri = Uri.parse(
          "${AppConfig.apiBaseUrl}/api/products/image-search/?q=${Uri.encodeQueryComponent(query)}");
      final response = await _client.get(uri, headers: _headers(token));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final data = jsonDecode(response.body);
      if (data is! List) {
        return const [];
      }
      return data
          .whereType<Map<String, dynamic>>()
          .map((json) => _toProductCard(json))
          .whereType<ProductCardData>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> trackProductView({required int productId, String? token}) async {
    try {
      final uri = Uri.parse("${AppConfig.apiBaseUrl}/api/products/track-view/");
      await _client.post(
        uri,
        headers: _headers(token),
        body: jsonEncode({"product_id": productId}),
      );
    } catch (_) {}
  }

  Future<List<ProductCardData>> _loadRecommendedOrProducts(
      {String? token}) async {
    final recommended =
        await _fetchProducts(path: "/api/products/recommended/", token: token);
    final allProducts =
        await _fetchProducts(path: "/api/products/", token: token);
    if (recommended.isEmpty) {
      return allProducts;
    }
    if (allProducts.isEmpty) {
      return recommended;
    }

    final mergedById = <int, ProductCardData>{};
    for (final product in recommended) {
      mergedById[product.id] = product;
    }
    for (final product in allProducts) {
      final existing = mergedById[product.id];
      if (existing == null) {
        mergedById[product.id] = product;
        continue;
      }
      final existingHasVideo = (existing.videoUrl ?? "").trim().isNotEmpty;
      final incomingHasVideo = (product.videoUrl ?? "").trim().isNotEmpty;
      if (!existingHasVideo && incomingHasVideo) {
        mergedById[product.id] = product;
      }
    }

    final merged = <ProductCardData>[];
    final seen = <int>{};
    for (final product in recommended) {
      final resolved = mergedById[product.id];
      if (resolved != null && seen.add(resolved.id)) {
        merged.add(resolved);
      }
    }
    for (final product in allProducts) {
      final resolved = mergedById[product.id];
      if (resolved != null && seen.add(resolved.id)) {
        merged.add(resolved);
      }
    }
    return merged;
  }

  Future<List<ProductCardData>> _fetchProducts(
      {required String path, String? token}) async {
    try {
      final uri = Uri.parse("${AppConfig.apiBaseUrl}$path");
      final response = await _client.get(uri, headers: _headers(token));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final data = jsonDecode(response.body);
      final rows = _extractProductRows(data);
      if (rows.isEmpty) {
        return const [];
      }
      return rows
          .whereType<Map<String, dynamic>>()
          .map((json) => _toProductCard(json))
          .whereType<ProductCardData>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<dynamic> _extractProductRows(dynamic data) {
    if (data is List) {
      return data;
    }
    if (data is Map<String, dynamic>) {
      final results = data["results"];
      if (results is List) {
        return results;
      }
    }
    return const [];
  }

  Map<String, String> _headers(String? token) {
    final headers = <String, String>{"Content-Type": "application/json"};
    if (token != null && token.isNotEmpty) {
      headers["Authorization"] = "Bearer $token";
    }
    return headers;
  }
}

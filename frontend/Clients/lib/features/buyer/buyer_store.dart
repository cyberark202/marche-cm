import 'package:flutter/foundation.dart';

class BuyerNotification {
  BuyerNotification({
    required this.message,
    required this.createdAt,
    this.topic = "",
    this.remoteId,
    this.read = false,
  });

  final String message;
  final DateTime createdAt;
  final String topic;
  final int? remoteId;
  bool read;
}

class CartEntry {
  CartEntry(
      {required this.productId,
      this.quantity = 1,
      this.joinGrouping = false,
      this.preferredTransitAgentId,
      this.transportMode = "AIR"});

  final int productId;
  int quantity;
  bool joinGrouping;
  int? preferredTransitAgentId;
  String transportMode;
}

class BuyerStore extends ChangeNotifier {
  final Map<int, CartEntry> _cart = {};
  final Set<int> _favorites = {};
  final Set<int> _watchlist = {};
  final List<BuyerNotification> _notifications = [];
  final Map<int, int> _productViews = {};
  final Map<String, int> _keywordAffinity = {};
  final Map<String, int> _localityAffinity = {};
  double _preferredPriceSum = 0;
  int _preferenceSignals = 0;

  List<CartEntry> get cartItems => _cart.values.toList();
  Set<int> get favorites => _favorites;
  Set<int> get watchlist => _watchlist;
  List<BuyerNotification> get notifications =>
      List.unmodifiable(_notifications);
  int get unreadNotificationsCount =>
      _notifications.where((n) => !n.read).length;
  Map<int, int> get productViews => _productViews;

  void recordProductView({
    required int productId,
    required String title,
    required String brand,
    required int priceMin,
    required int priceMax,
    required String locality,
  }) {
    _productViews[productId] = (_productViews[productId] ?? 0) + 1;

    for (final token in _tokenize("$title $brand")) {
      _keywordAffinity[token] = (_keywordAffinity[token] ?? 0) + 1;
    }

    final normalizedLocality = locality.toUpperCase().trim();
    if (normalizedLocality.isNotEmpty) {
      _localityAffinity[normalizedLocality] =
          (_localityAffinity[normalizedLocality] ?? 0) + 1;
    }

    final productMidPrice = (priceMin + priceMax) / 2;
    if (productMidPrice > 0) {
      _preferredPriceSum += productMidPrice;
      _preferenceSignals += 1;
    }

    notifyListeners();
  }

  double preferenceScoreFor({
    required int productId,
    required String title,
    required String brand,
    required int priceMin,
    required int priceMax,
    required String locality,
  }) {
    var score = 0.0;

    final views = _productViews[productId] ?? 0;
    score += views * 6;

    for (final token in _tokenize("$title $brand")) {
      score += (_keywordAffinity[token] ?? 0) * 0.8;
    }

    score += (_localityAffinity[locality.toUpperCase().trim()] ?? 0) * 3;

    if (_preferenceSignals > 0) {
      final avgPreferredPrice = _preferredPriceSum / _preferenceSignals;
      final productMidPrice = (priceMin + priceMax) / 2;
      final spread = avgPreferredPrice <= 1 ? 1 : avgPreferredPrice * 0.45;
      final normalizedDistance =
          ((productMidPrice - avgPreferredPrice).abs() / spread).clamp(0, 1);
      final closeness = 1 - normalizedDistance;
      score += closeness * 5;
    }

    return score;
  }

  Set<String> _tokenize(String raw) {
    const blocked = {
      "de",
      "du",
      "la",
      "le",
      "les",
      "des",
      "pour",
      "avec",
      "sans",
      "sur",
      "the",
      "and",
      "pack",
      "pcs",
      "kg",
      "ml",
      "l"
    };

    return RegExp(r"[a-zA-Z0-9]{3,}")
        .allMatches(raw.toLowerCase())
        .map((m) => m.group(0)!)
        .where((token) => !blocked.contains(token))
        .toSet();
  }

  void addToCart(int productId, {int quantity = 1}) {
    final existing = _cart[productId];
    if (existing == null) {
      _cart[productId] = CartEntry(productId: productId, quantity: quantity);
    } else {
      existing.quantity += quantity;
    }
    notifyListeners();
  }

  void updateCart(int productId,
      {int? quantity,
      bool? joinGrouping,
      int? preferredTransitAgentId,
      String? transportMode,
      bool clearAgent = false}) {
    final item = _cart[productId];
    if (item == null) return;
    if (quantity != null) item.quantity = quantity;
    if (joinGrouping != null) item.joinGrouping = joinGrouping;
    if (clearAgent) {
      item.preferredTransitAgentId = null;
    } else if (preferredTransitAgentId != null) {
      item.preferredTransitAgentId = preferredTransitAgentId;
    }
    if (transportMode != null &&
        (transportMode == "AIR" || transportMode == "SEA")) {
      item.transportMode = transportMode;
    }
    notifyListeners();
  }

  void removeFromCart(int productId) {
    _cart.remove(productId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    notifyListeners();
  }

  void toggleFavorite(int productId) {
    if (_favorites.contains(productId)) {
      _favorites.remove(productId);
    } else {
      _favorites.add(productId);
    }
    notifyListeners();
  }

  void toggleWatchlist(int productId) {
    if (_watchlist.contains(productId)) {
      _watchlist.remove(productId);
    } else {
      _watchlist.add(productId);
    }
    notifyListeners();
  }

  void pushNotification(
    String message, {
    String topic = "",
    int? remoteId,
    DateTime? createdAt,
    bool read = false,
  }) {
    if (remoteId != null) {
      for (final existing in _notifications) {
        if (existing.remoteId == remoteId) {
          if (read && !existing.read) {
            existing.read = true;
            notifyListeners();
          }
          return;
        }
      }
    }
    _notifications.insert(
      0,
      BuyerNotification(
        message: message,
        topic: topic,
        remoteId: remoteId,
        createdAt: createdAt ?? DateTime.now(),
        read: read,
      ),
    );
    if (_notifications.length > 200) {
      _notifications.removeLast();
    }
    notifyListeners();
  }

  void markNotificationRead(int index) {
    if (index < 0 || index >= _notifications.length) return;
    if (_notifications[index].read) return;
    _notifications[index].read = true;
    notifyListeners();
  }

  void markNotificationReadByRemoteId(int remoteId) {
    var changed = false;
    for (final n in _notifications) {
      if (n.remoteId == remoteId && !n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void markAllNotificationsRead() {
    var changed = false;
    for (final item in _notifications) {
      if (!item.read) {
        item.read = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  void clearNotifications() {
    if (_notifications.isEmpty) return;
    _notifications.clear();
    notifyListeners();
  }

  void syncRemoteNotifications(List<Map<String, dynamic>> rows) {
    final remotes = rows.map((row) {
      final idRaw = row["id"];
      final id = idRaw is int ? idRaw : int.tryParse(idRaw.toString());
      final createdAtRaw = (row["created_at"] ?? "").toString();
      final parsedCreatedAt = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
      final title = (row["title"] ?? "").toString();
      final body = (row["body"] ?? "").toString();
      final message = title.isEmpty ? body : "$title - $body";
      return BuyerNotification(
        remoteId: id,
        message: message,
        topic: "notifications",
        createdAt: parsedCreatedAt,
        read: (row["is_read"] ?? false) == true,
      );
    }).toList();

    final locals = _notifications.where((n) => n.remoteId == null).toList();
    _notifications
      ..clear()
      ..addAll(remotes)
      ..addAll(locals);
    notifyListeners();
  }
}

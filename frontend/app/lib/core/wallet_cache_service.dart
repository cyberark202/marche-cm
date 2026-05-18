import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Schema version — bump whenever the cached shape changes to auto-invalidate.
const int _kSchemaVersion = 1;

const String _kVersionKey = 'wallet_cache_schema_v';
const String _kWalletKey = 'wallet_cache_wallet';
const String _kTxKey = 'wallet_cache_transactions';
const String _kWalletTsKey = 'wallet_cache_wallet_ts';
const String _kTxTsKey = 'wallet_cache_tx_ts';
const int _kMaxTransactions = 50;
const Duration _kStaleThreshold = Duration(hours: 1);

/// Lightweight SharedPreferences-backed cache for wallet data.
///
/// Schema-versioned: any schema bump wipes stale data automatically.
/// Max 50 transactions stored (most-recent wins on overflow).
/// Stale after 1 hour — callers should always fetch fresh data
/// and use cache only as a fallback when offline.
class WalletCacheService {
  WalletCacheService._();
  static final WalletCacheService instance = WalletCacheService._();

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _ensureSchema(SharedPreferences prefs) async {
    final stored = prefs.getInt(_kVersionKey);
    if (stored != _kSchemaVersion) {
      await prefs.remove(_kWalletKey);
      await prefs.remove(_kTxKey);
      await prefs.remove(_kWalletTsKey);
      await prefs.remove(_kTxTsKey);
      await prefs.setInt(_kVersionKey, _kSchemaVersion);
    }
  }

  // ── Wallet summary ────────────────────────────────────────────────────────

  Future<void> saveWallet(Map<String, dynamic> wallet) async {
    final prefs = await _getPrefs();
    await _ensureSchema(prefs);
    await prefs.setString(_kWalletKey, jsonEncode(wallet));
    await prefs.setInt(_kWalletTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<Map<String, dynamic>?> loadWallet({bool allowStale = false}) async {
    try {
      final prefs = await _getPrefs();
      await _ensureSchema(prefs);
      final raw = prefs.getString(_kWalletKey);
      if (raw == null) return null;
      if (!allowStale && _isStale(prefs.getInt(_kWalletTsKey))) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  // ── Transaction list ──────────────────────────────────────────────────────

  Future<void> saveTransactions(List<Map<String, dynamic>> transactions) async {
    final prefs = await _getPrefs();
    await _ensureSchema(prefs);
    final capped = transactions.length > _kMaxTransactions
        ? transactions.sublist(0, _kMaxTransactions)
        : transactions;
    await prefs.setString(_kTxKey, jsonEncode(capped));
    await prefs.setInt(_kTxTsKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<List<Map<String, dynamic>>?> loadTransactions({
    bool allowStale = false,
  }) async {
    try {
      final prefs = await _getPrefs();
      await _ensureSchema(prefs);
      final raw = prefs.getString(_kTxKey);
      if (raw == null) return null;
      if (!allowStale && _isStale(prefs.getInt(_kTxTsKey))) return null;
      final list = jsonDecode(raw) as List;
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  // ── Staleness helpers ─────────────────────────────────────────────────────

  bool _isStale(int? tsMs) {
    if (tsMs == null) return true;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(tsMs));
    return age > _kStaleThreshold;
  }

  bool get isWalletStale => true; // evaluated lazily — callers check prefs
  Future<bool> isWalletDataStale() async {
    final prefs = await _getPrefs();
    return _isStale(prefs.getInt(_kWalletTsKey));
  }

  Future<bool> isTransactionDataStale() async {
    final prefs = await _getPrefs();
    return _isStale(prefs.getInt(_kTxTsKey));
  }

  // ── Cache invalidation ────────────────────────────────────────────────────

  Future<void> invalidate() async {
    final prefs = await _getPrefs();
    await prefs.remove(_kWalletKey);
    await prefs.remove(_kTxKey);
    await prefs.remove(_kWalletTsKey);
    await prefs.remove(_kTxTsKey);
  }
}

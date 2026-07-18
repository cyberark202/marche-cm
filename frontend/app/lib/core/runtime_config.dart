import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

class RuntimeConfig {
  const RuntimeConfig({
    required this.configVersion,
    required this.latestVersion,
    required this.minSupportedVersion,
    required this.updateAvailable,
    required this.updateRequired,
    required this.downloadUrl,
    required this.updateMessage,
    required this.maintenance,
    required this.maintenanceMessage,
    required this.killSwitch,
    required this.featureFlags,
  });

  final int configVersion;
  final String latestVersion;
  final String minSupportedVersion;
  final bool updateAvailable;
  final bool updateRequired;
  final String downloadUrl;
  final Map<String, dynamic> updateMessage;
  final bool maintenance;
  final Map<String, dynamic> maintenanceMessage;
  final bool killSwitch;
  final Map<String, dynamic> featureFlags;

  bool get isBlocking => killSwitch || updateRequired || maintenance;

  bool flag(String key, {bool fallback = false}) {
    final v = featureFlags[key];
    return v is bool ? v : fallback;
  }

  String localizedUpdateMessage(String lang) => _pick(updateMessage, lang);
  String localizedMaintenanceMessage(String lang) => _pick(maintenanceMessage, lang);

  static String _pick(Map<String, dynamic> m, String lang) {
    final v = m[lang] ?? m['fr'] ?? m['en'];
    return v?.toString() ?? '';
  }

  static Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static RuntimeConfig fromJson(Map<String, dynamic> j) => RuntimeConfig(
        configVersion: (j['config_version'] as num?)?.toInt() ?? 0,
        latestVersion: (j['latest_version'] ?? '').toString(),
        minSupportedVersion: (j['min_supported_version'] ?? '0.0.0').toString(),
        updateAvailable: j['update_available'] == true,
        updateRequired: j['update_required'] == true,
        downloadUrl: (j['download_url'] ?? '').toString(),
        updateMessage: _asMap(j['update_message']),
        maintenance: j['maintenance'] == true,
        maintenanceMessage: _asMap(j['maintenance_message']),
        killSwitch: j['kill_switch'] == true,
        featureFlags: _asMap(j['feature_flags']),
      );

  Map<String, dynamic> toJson() => {
        'config_version': configVersion,
        'latest_version': latestVersion,
        'min_supported_version': minSupportedVersion,
        'update_available': updateAvailable,
        'update_required': updateRequired,
        'download_url': downloadUrl,
        'update_message': updateMessage,
        'maintenance': maintenance,
        'maintenance_message': maintenanceMessage,
        'kill_switch': killSwitch,
        'feature_flags': featureFlags,
      };
}

class RuntimeConfigService {
  RuntimeConfigService._();
  static final RuntimeConfigService instance = RuntimeConfigService._();

  static const String _cacheKey = 'runtime_config_cache_v1';

  final ValueNotifier<RuntimeConfig?> config = ValueNotifier<RuntimeConfig?>(null);

  String get _platform => kIsWeb ? 'web' : 'android';

  Future<void> loadCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null && raw.isNotEmpty) {
        config.value =
            RuntimeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
    }
  }

  Future<void> refresh() async {
    final uri = Uri.parse(
      '${AppConfig.apiBaseUrl}/api/app/runtime-config/'
      '?app=${AppConfig.appId}&platform=$_platform&version=${AppConfig.appVersion}',
    );
    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final cfg = RuntimeConfig.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
        config.value = cfg;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(cfg.toJson()));
        } catch (_) {}
      }
    } catch (_) {
    }
  }
}

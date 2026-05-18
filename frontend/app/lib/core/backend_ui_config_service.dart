import 'api_service.dart';

class BackendUiConfigService {
  BackendUiConfigService._();

  static final BackendUiConfigService instance = BackendUiConfigService._();

  final ApiService _api = ApiService();
  Map<String, dynamic>? _cache;
  DateTime? _loadedAt;

  Future<Map<String, dynamic>> load({
    String? token,
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cache != null &&
        _loadedAt != null &&
        now.difference(_loadedAt!).inMinutes < 5) {
      return _cache!;
    }
    final data = await _api.getObject("/api/ui-config/", token: token);
    _cache = data;
    _loadedAt = now;
    return data;
  }

  dynamic read(Map<String, dynamic> config, List<String> path) {
    dynamic node = config;
    for (final segment in path) {
      if (node is! Map<String, dynamic>) {
        return null;
      }
      node = node[segment];
    }
    return node;
  }

  String readString(
    Map<String, dynamic> config,
    List<String> path, {
    String fallback = "",
  }) {
    final value = read(config, path);
    if (value == null) {
      return fallback;
    }
    return value.toString();
  }

  int readInt(
    Map<String, dynamic> config,
    List<String> path, {
    int fallback = 0,
  }) {
    final value = read(config, path);
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? "") ?? fallback;
  }

  List<String> readStringList(
    Map<String, dynamic> config,
    List<String> path,
  ) {
    final value = read(config, path);
    if (value is! List) {
      return const [];
    }
    return value.map((e) => e.toString()).toList();
  }

  List<Map<String, String>> readChoiceList(
    Map<String, dynamic> config,
    List<String> path,
  ) {
    final value = read(config, path);
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((row) {
          final map = row.cast<dynamic, dynamic>();
          return {
            "value": (map["value"] ?? "").toString(),
            "label": (map["label"] ?? "").toString(),
          };
        })
        .where((row) => row["value"]!.isNotEmpty)
        .toList();
  }

  Map<String, String> readStringMap(
    Map<String, dynamic> config,
    List<String> path,
  ) {
    final value = read(config, path);
    if (value is! Map) {
      return const {};
    }
    final out = <String, String>{};
    value.forEach((key, item) {
      out[key.toString()] = item?.toString() ?? "";
    });
    return out;
  }
}

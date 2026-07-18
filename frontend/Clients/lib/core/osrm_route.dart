import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Un itineraire route (suivant les routes) renvoye par OSRM.
class RouteOption {
  const RouteOption({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.isFallback,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  /// `true` si OSRM etait injoignable : on retombe sur une ligne droite.
  final bool isFallback;

  String get distanceLabel => distanceMeters >= 1000
      ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
      : '${distanceMeters.round()} m';

  String get durationLabel {
    final mins = (durationSeconds / 60).round();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
}

/// Calcule un (ou plusieurs) itineraire(s) routier(s) entre des points via le
/// serveur public OSRM (OpenStreetMap, SANS cle API). Retombe sur une ligne
/// droite si le service est injoignable, pour ne jamais bloquer la carte.
Future<List<RouteOption>> fetchRouteOptions(
  List<LatLng> waypoints, {
  bool alternatives = false,
}) async {
  final pts = waypoints.where((p) => p.latitude != 0 || p.longitude != 0).toList();
  if (pts.length < 2) return const [];

  final coords =
      pts.map((p) => '${p.longitude},${p.latitude}').join(';');
  final uri = Uri.parse(
    'https://router.project-osrm.org/route/v1/driving/$coords'
    '?overview=full&geometries=geojson&alternatives=$alternatives',
  );
  try {
    final resp = await http.get(uri).timeout(const Duration(seconds: 8));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final routes = (data['routes'] as List?) ?? const [];
      final result = <RouteOption>[];
      for (final r in routes) {
        final coordsList =
            (r['geometry']?['coordinates'] as List?) ?? const [];
        final line = coordsList
            .whereType<List>()
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
        if (line.isNotEmpty) {
          result.add(RouteOption(
            points: line,
            distanceMeters: ((r['distance'] as num?) ?? 0).toDouble(),
            durationSeconds: ((r['duration'] as num?) ?? 0).toDouble(),
            isFallback: false,
          ));
        }
      }
      if (result.isNotEmpty) return result;
    }
  } catch (_) {
    // ignore -> fallback ligne droite
  }
  return [
    RouteOption(
      points: List<LatLng>.of(pts),
      distanceMeters: 0,
      durationSeconds: 0,
      isFallback: true,
    ),
  ];
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/osrm_route.dart';
import '../../core/websocket_service.dart';
import '../auth/session_store.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Suivi live du livreur sur une carte (OpenStreetMap, sans cle API).
///
/// LECTURE SEULE (acheteur/vendeur) : se connecte au `TrackingConsumer`
/// (`ws/tracking/{id}/`), affiche la position du livreur rediffusee par le
/// backend, les positions vendeur (enlevement) et acheteur (livraison), et
/// trace l'itineraire routier livreur -> vendeur -> acheteur. Aucun controle :
/// l'acheteur et le vendeur ne peuvent rien modifier.
class LiveDeliveryMapPage extends StatefulWidget {
  const LiveDeliveryMapPage({
    super.key,
    required this.shipmentId,
    this.initialLat,
    this.initialLng,
    this.pickupLat,
    this.pickupLng,
    this.dropoffLat,
    this.dropoffLng,
    this.title = 'Suivi du livreur',
  });

  final String shipmentId;
  final double? initialLat;
  final double? initialLng;
  final double? pickupLat; // position du vendeur (enlevement)
  final double? pickupLng;
  final double? dropoffLat; // position de l'acheteur (livraison)
  final double? dropoffLng;
  final String title;

  @override
  State<LiveDeliveryMapPage> createState() => _LiveDeliveryMapPageState();
}

class _LiveDeliveryMapPageState extends State<LiveDeliveryMapPage> {
  final MapController _map = MapController();
  WebSocketService? _ws;
  StreamSubscription<Map<String, dynamic>>? _sub;

  LatLng? _driver;
  LatLng? _pickup; // vendeur
  LatLng? _dropoff; // acheteur
  List<LatLng> _route = const [];
  DateTime? _updatedAt;
  DateTime? _lastRouteFetch;
  int _attempts = 0;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _driver = LatLng(widget.initialLat!, widget.initialLng!);
    }
    if (widget.pickupLat != null && widget.pickupLng != null) {
      _pickup = LatLng(widget.pickupLat!, widget.pickupLng!);
    }
    if (widget.dropoffLat != null && widget.dropoffLng != null) {
      _dropoff = LatLng(widget.dropoffLat!, widget.dropoffLng!);
    }
    _connect();
    _refreshRoute(force: true);
  }

  /// Trace l'itineraire routier livreur -> vendeur -> acheteur (OSRM). Throttle
  /// a 1 calcul / 20s pour ne pas marteler le service public a chaque tick GPS.
  Future<void> _refreshRoute({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastRouteFetch != null &&
        now.difference(_lastRouteFetch!).inSeconds < 20) {
      return;
    }
    _lastRouteFetch = now;
    final waypoints = <LatLng>[
      if (_driver != null) _driver!,
      if (_pickup != null) _pickup!,
      if (_dropoff != null) _dropoff!,
    ];
    if (waypoints.length < 2) return;
    final options = await fetchRouteOptions(waypoints);
    if (!mounted || options.isEmpty) return;
    setState(() => _route = options.first.points);
  }

  void _connect() {
    final token = context.read<SessionStore>().token;
    final base = AppConfig.apiBaseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    _ws = WebSocketService('$base/ws/tracking/${widget.shipmentId}/',
        token: token);
    _sub = _ws!.connect().listen(
      _onEvent,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] != 'location_update') return;
    final lat = _toDouble(e['latitude']);
    final lng = _toDouble(e['longitude']);
    if (lat == null || lng == null) return;
    if (!mounted) return;
    _attempts = 0; // connexion fonctionnelle -> on repart d'un backoff neuf
    final isFirstFix = _driver == null;
    setState(() {
      _driver = LatLng(lat, lng);
      _updatedAt = DateTime.now();
    });
    if (isFirstFix) {
      try {
        _map.move(_driver!, 14);
      } catch (_) {}
    }
    unawaited(_refreshRoute());
  }

  /// Reconnexion SILENCIEUSE en arriere-plan (backoff 2..30s, jamais 1s).
  /// L'utilisateur ne voit aucune coupure : la carte garde la derniere
  /// position connue et le socket se retablit tout seul.
  void _scheduleReconnect() {
    _sub?.cancel();
    _sub = null;
    _ws?.dispose();
    _ws = null;
    if (_reconnectTimer?.isActive == true) return;
    final delay = (1 << _attempts).clamp(2, 30);
    _attempts++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (mounted) _connect();
    });
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _ws?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: _StatusBar(hasFix: _driver != null, updatedAt: _updatedAt),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _driver ??
                  _dropoff ??
                  _pickup ??
                  const LatLng(3.848, 11.502), // Yaounde
              initialZoom: _driver != null ? 14 : 12,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cm.market.seller',
              ),
              if (_route.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 4,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_pickup != null)
                    Marker(
                      point: _pickup!,
                      width: 46,
                      height: 46,
                      child: const _EndpointPin(
                          icon: LucideIcons.store, color: Color(0xFFF97316)),
                    ),
                  if (_dropoff != null)
                    Marker(
                      point: _dropoff!,
                      width: 46,
                      height: 46,
                      child: const _EndpointPin(
                          icon: LucideIcons.home, color: Color(0xFF2563EB)),
                    ),
                  if (_driver != null)
                    Marker(
                      point: _driver!,
                      width: 54,
                      height: 54,
                      child: const _DriverPin(),
                    ),
                ],
              ),
            ],
          ),
          if (_driver == null)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('En attente de la position du livreur...'),
                ),
              ),
            ),
          const Positioned(left: 10, bottom: 10, child: _MapLegend()),
        ],
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend();

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendRow(
                color: Color(0xFF15803D),
                icon: LucideIcons.truck,
                label: 'Livreur'),
            SizedBox(height: 4),
            _LegendRow(
                color: Color(0xFFF97316),
                icon: LucideIcons.store,
                label: 'Vendeur (enlevement)'),
            SizedBox(height: 4),
            _LegendRow(
                color: Color(0xFF2563EB),
                icon: LucideIcons.home,
                label: 'Acheteur (livraison)'),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow(
      {required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.hasFix, required this.updatedAt});
  final bool hasFix;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    // Pas d'etat « Hors ligne » : les reconnexions sont silencieuses et en
    // arriere-plan. On indique seulement la fraicheur via l'horodatage.
    const color = Color(0xFF10B981);
    final label = hasFix ? 'Suivi en direct' : 'Connexion au suivi...';
    final time = updatedAt == null
        ? ''
        : ' · maj ${updatedAt!.hour.toString().padLeft(2, '0')}:'
            '${updatedAt!.minute.toString().padLeft(2, '0')}:'
            '${updatedAt!.second.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: SizedBox(width: 8, height: 8),
          ),
          const SizedBox(width: 8),
          Text('$label$time',
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }
}

class _EndpointPin extends StatelessWidget {
  const _EndpointPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _DriverPin extends StatelessWidget {
  const _DriverPin();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2),
        ],
      ),
      child: const Icon(LucideIcons.truck, color: Colors.white, size: 26),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/osrm_route.dart';
import '../../../core/security/driver_secure_storage.dart';
import '../../../core/theme/driver_theme.dart';
import '../../../core/websocket_service.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Suivi GPS du livreur. Le livreur (transit_agent assigne) :
///  1. stream sa position via geolocator,
///  2. l'envoie au TrackingConsumer (`ws/tracking/{id}/`, type `location_update`),
///  3. la voit sur une carte OpenStreetMap (flutter_map, sans cle API).
/// Le backend rediffuse alors la position a l'acheteur et au vendeur.
class TrackingPage extends StatefulWidget {
  final String shipmentId;
  const TrackingPage({super.key, required this.shipmentId});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  final MapController _mapController = MapController();
  WebSocketService? _ws;
  StreamSubscription<Position>? _posSub;
  StreamSubscription<Map<String, dynamic>>? _wsSub;

  LatLng? _pos;
  LatLng? _pickup; // vendeur (enlevement)
  LatLng? _dropoff; // acheteur (livraison)
  // Destination choisie par le livreur : 0 = vendeur, 1 = acheteur.
  int _destination = 0;
  List<RouteOption> _routes = const [];
  int _selectedRoute = 0;
  bool _routeLoading = false;
  DateTime? _lastRouteFetch;
  bool _sending = false;
  String _statusLabel = 'Initialisation du GPS...';
  String? _error;
  int _wsAttempts = 0;
  Timer? _wsReconnect;
  Timer? _wsStability;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    unawaited(_loadShipment());
    final permitted = await _ensureLocationPermission();
    if (!permitted || !mounted) return;
    await _connectWs();
    _startGpsStream();
  }

  /// Recupere les coordonnees du vendeur (enlevement) et de l'acheteur
  /// (livraison) pour tracer l'itineraire, + choisit la destination par defaut
  /// selon le statut (avant enlevement -> vendeur, sinon -> acheteur).
  Future<void> _loadShipment() async {
    try {
      final resp =
          await DriverDioClient.dio.get('/api/shipments/${widget.shipmentId}/');
      final data = resp.data;
      if (data is! Map) return;
      final pLat = _num(data['pickup_latitude']);
      final pLng = _num(data['pickup_longitude']);
      final dLat = _num(data['dropoff_latitude']);
      final dLng = _num(data['dropoff_longitude']);
      final status = '${data['status'] ?? ''}'.toUpperCase();
      if (!mounted) return;
      setState(() {
        if (pLat != null && pLng != null) _pickup = LatLng(pLat, pLng);
        if (dLat != null && dLng != null) _dropoff = LatLng(dLat, dLng);
        // Deja enleve / en transit -> on va chez l'acheteur.
        _destination =
            (status == 'PICKUP_PENDING' || status.isEmpty) ? 0 : 1;
      });
      unawaited(_recomputeRoute(force: true));
    } catch (_) {
      // Pas de coords -> la carte affiche juste la position live du livreur.
    }
  }

  double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }

  LatLng? get _target => _destination == 0 ? _pickup : _dropoff;

  Future<void> _recomputeRoute({bool force = false}) async {
    final from = _pos;
    final to = _target;
    if (from == null || to == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastRouteFetch != null &&
        now.difference(_lastRouteFetch!).inSeconds < 20) {
      return;
    }
    _lastRouteFetch = now;
    if (mounted) setState(() => _routeLoading = true);
    final options = await fetchRouteOptions([from, to], alternatives: true);
    if (!mounted) return;
    setState(() {
      _routes = options;
      _selectedRoute = 0;
      _routeLoading = false;
    });
  }

  void _selectDestination(int dest) {
    if (_destination == dest) return;
    setState(() {
      _destination = dest;
      _routes = const [];
    });
    unawaited(_recomputeRoute(force: true));
  }

  Widget _buildRouteOptions() {
    if (_routeLoading && _routes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Row(children: [
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Calcul de l\'itineraire...',
              style: TextStyle(fontSize: 12, color: DriverPalette.textSecondary)),
        ]),
      );
    }
    if (_routes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _routes.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final r = _routes[i];
            final label = r.isFallback
                ? 'Direct (approx.)'
                : 'Itineraire ${i + 1} · ${r.distanceLabel} · ${r.durationLabel}';
            return ChoiceChip(
              label: Text(label, style: const TextStyle(fontSize: 12)),
              selected: _selectedRoute == i,
              onSelected: (_) => setState(() => _selectedRoute = i),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _error = 'Activez la localisation de l\'appareil.');
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      setState(() => _error = 'Permission de localisation refusee.');
      return false;
    }
    return true;
  }

  Future<void> _connectWs() async {
    final token = await DriverSecureStorage.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      setState(() => _error = 'Session expiree. Reconnectez-vous.');
      return;
    }
    final base = AppConfig.apiBaseUrl
        .replaceFirst('http://', 'ws://')
        .replaceFirst('https://', 'wss://');
    _ws = WebSocketService('$base/ws/tracking/${widget.shipmentId}/',
        token: token);
    // On ecoute pour garder la socket vivante (et detecter une coupure) meme si
    // le livreur n'a pas besoin de recevoir sa propre position. En cas de
    // coupure on se reconnecte SILENCIEUSEMENT en arriere-plan (backoff 2..30s).
    _wsSub = _ws!.connect().listen(
      (_) {},
      onError: (_) => _scheduleWsReconnect(),
      onDone: _scheduleWsReconnect,
      cancelOnError: true,
    );
    // Reset du backoff apres une connexion stable (evite une boucle a 2s).
    _wsStability?.cancel();
    _wsStability = Timer(const Duration(seconds: 20), () => _wsAttempts = 0);
  }

  void _scheduleWsReconnect() {
    _wsStability?.cancel();
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.dispose();
    _ws = null;
    if (_wsReconnect?.isActive == true) return;
    final delay = (1 << _wsAttempts).clamp(2, 30);
    _wsAttempts++;
    _wsReconnect = Timer(Duration(seconds: delay), () {
      if (mounted) _connectWs();
    });
  }

  void _startGpsStream() {
    setState(() => _statusLabel = 'Position GPS active');
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // n'emet que tous les ~10 m
      ),
    ).listen(_onPosition, onError: (_) {
      if (mounted) setState(() => _error = 'Erreur GPS.');
    });
  }

  void _onPosition(Position p) {
    final pos = LatLng(p.latitude, p.longitude);
    if (!mounted) return;
    final isFirstFix = _pos == null;
    setState(() {
      _pos = pos;
      _sending = true;
    });
    if (isFirstFix) {
      try {
        _mapController.move(pos, 15);
      } catch (_) {}
    }
    _ws?.send({
      'type': 'location_update',
      'latitude': p.latitude,
      'longitude': p.longitude,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
    unawaited(_recomputeRoute());
  }

  @override
  void dispose() {
    _wsReconnect?.cancel();
    _wsStability?.cancel();
    _posSub?.cancel();
    _wsSub?.cancel();
    _ws?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Suivi GPS'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _error != null
                ? _ErrorView(message: _error!, onRetry: () {
                    setState(() => _error = null);
                    _start();
                  })
                : Stack(
                    children: [
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter:
                              _pos ?? const LatLng(3.848, 11.502), // Yaounde
                          initialZoom: 15,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'cm.market.driver',
                          ),
                          if (_routes.isNotEmpty &&
                              _selectedRoute < _routes.length &&
                              _routes[_selectedRoute].points.length >= 2)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: _routes[_selectedRoute].points,
                                  strokeWidth: 5,
                                  color: DriverPalette.primary,
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
                                      icon: LucideIcons.store,
                                      color: Color(0xFFF97316)),
                                ),
                              if (_dropoff != null)
                                Marker(
                                  point: _dropoff!,
                                  width: 46,
                                  height: 46,
                                  child: const _EndpointPin(
                                      icon: LucideIcons.home,
                                      color: Color(0xFF2563EB)),
                                ),
                              if (_pos != null)
                                Marker(
                                  point: _pos!,
                                  width: 54,
                                  height: 54,
                                  child: _DriverPin(),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_pos == null)
                        const Center(child: CircularProgressIndicator()),
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _sending
                          ? const Color(0xFF10B981)
                          : DriverPalette.textSecondary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_statusLabel,
                      style: const TextStyle(
                          fontSize: 13, color: DriverPalette.textSecondary)),
                  const Spacer(),
                  Text('Livraison #${widget.shipmentId}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: DriverPalette.textPrimary)),
                ]),
                if (_pickup != null || _dropoff != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (_pickup != null)
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Vendeur (enlevement)'),
                            selected: _destination == 0,
                            onSelected: (_) => _selectDestination(0),
                          ),
                        ),
                      if (_pickup != null && _dropoff != null)
                        const SizedBox(width: 8),
                      if (_dropoff != null)
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('Acheteur (livraison)'),
                            selected: _destination == 1,
                            onSelected: (_) => _selectDestination(1),
                          ),
                        ),
                    ],
                  ),
                  _buildRouteOptions(),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () =>
                        context.push('/active/otp/${widget.shipmentId}'),
                    child: const Text('Valider la livraison',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
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
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DriverPalette.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
              color: DriverPalette.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2),
        ],
      ),
      child: const Icon(LucideIcons.truck, color: Colors.white, size: 26),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(LucideIcons.mapPinOff,
                size: 56, color: DriverPalette.textSecondary),
            const SizedBox(height: 16),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: DriverPalette.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reessayer')),
          ],
        ),
      ),
    );
  }
}

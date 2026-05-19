import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';
import '../wallet/wallet_page.dart';
import 'custody_event_page.dart';
import 'dispute_create_page.dart';
import 'dispute_detail_page.dart';
import 'shipment_disputes_page.dart';

class TransitDashboardPage extends StatefulWidget {
  const TransitDashboardPage({super.key});

  @override
  State<TransitDashboardPage> createState() => _TransitDashboardPageState();
}

class _TransitDashboardPageState extends State<TransitDashboardPage> {
  final ApiService _api = ApiService();
  late Future<_TransitPayload> _future;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  int _navIndex = 0;
  String _shipmentFilter = '';
  List<Map<String, dynamic>> _latestShipments = const [];
  List<Map<String, String>> _shipmentFilters = const [];
  List<String> _shipmentUpdateStatuses = const [];
  String _defaultCountryCode = '';
  int _defaultQuoteEtaDays = 0;
  int _defaultAirPricePerKg = 0;
  int _defaultSeaPricePerKg = 0;
  Map<String, dynamic>? _latestProfile;

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _future = _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'logistics')) {
        setState(() => _future = _load());
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
      final filters = BackendUiConfigService.instance
          .readChoiceList(config, ['choices', 'shipment_filters']);
      final statuses = BackendUiConfigService.instance
          .readStringList(config, ['choices', 'shipment_update_statuses']);
      final defaultCountry = BackendUiConfigService.instance
          .readString(config, ['defaults', 'country_code']);
      final defaultEta = BackendUiConfigService.instance
          .readInt(config, ['defaults', 'shipment_quote_eta_days']);
      final defaultAirPrice = BackendUiConfigService.instance
          .readInt(config, ['defaults', 'transport_air_price_per_kg']);
      final defaultSeaPrice = BackendUiConfigService.instance
          .readInt(config, ['defaults', 'transport_sea_price_per_kg']);
      if (!mounted) return;
      setState(() {
        _shipmentFilters = filters;
        _shipmentUpdateStatuses = statuses;
        _defaultCountryCode = defaultCountry;
        _defaultQuoteEtaDays = defaultEta;
        _defaultAirPricePerKg = defaultAirPrice;
        _defaultSeaPricePerKg = defaultSeaPrice;
        if (_shipmentFilter.isEmpty && filters.isNotEmpty) {
          _shipmentFilter = filters.first['value']!;
        }
      });
    } catch (e) {
      debugPrint('[TransitDashboardPage] _loadUiConfig error: $e');
    }
  }

  Future<_TransitPayload> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList('/api/shipments/', token: token),
        _api.getList('/api/transport-quotes/', token: token),
        _api.getList('/api/transport-profiles/', token: token),
        _api.getList('/api/shipment-disputes/', token: token),
        _api.getList('/api/compliance-documents/', token: token),
      ]);
      return _TransitPayload(
        shipments: results[0],
        quotes: results[1],
        profiles: results[2],
        disputes: results[3],
        complianceDocs: results[4],
        fallback: false,
      );
    } catch (_) {
      return const _TransitPayload(
        shipments: <Map<String, dynamic>>[],
        quotes: <Map<String, dynamic>>[],
        profiles: <Map<String, dynamic>>[],
        disputes: <Map<String, dynamic>>[],
        complianceDocs: <Map<String, dynamic>>[],
        fallback: false,
      );
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _createOrUpdateProfileDialog(
      Map<String, dynamic>? existing) async {
    final company = TextEditingController(
        text: (existing?['company_name'] ?? '').toString());
    final countries = TextEditingController(
        text: (existing?['coverage_countries'] ?? _defaultCountryCode)
            .toString());
    final zones = TextEditingController(
        text: (existing?['operating_zones'] ?? '').toString());
    final vehicles = TextEditingController(
        text: (existing?['vehicle_count'] ?? 0).toString());
    final vehicleTypes = TextEditingController(
        text: (existing?['vehicle_types'] ?? '').toString());
    final maxPayload = TextEditingController(
        text: (existing?['max_payload_kg'] ?? 0).toString());
    final airPricePerKg = TextEditingController(
        text: (existing?['air_price_per_kg'] ?? _defaultAirPricePerKg)
            .toString());
    final seaPricePerKg = TextEditingController(
        text: (existing?['sea_price_per_kg'] ?? _defaultSeaPricePerKg)
            .toString());
    final averageEta = TextEditingController(
        text: (existing?['average_eta_days'] ?? 0).toString());
    final insuranceDate = TextEditingController(
        text: (existing?['insurance_valid_until'] ?? '').toString());
    bool customs = existing?['has_customs_license'] == true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null
              ? 'Creer profil transport'
              : 'Modifier profil transport'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                    controller: company,
                    decoration:
                        const InputDecoration(labelText: 'Nom entreprise')),
                TextField(
                    controller: countries,
                    decoration: const InputDecoration(
                        labelText: 'Pays couverts (ex: CM,CI)')),
                TextField(
                    controller: zones,
                    decoration: const InputDecoration(
                        labelText: 'Zones operationnelles')),
                TextField(
                  controller: vehicles,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Nombre vehicules'),
                ),
                TextField(
                    controller: vehicleTypes,
                    decoration:
                        const InputDecoration(labelText: 'Types de vehicules')),
                TextField(
                  controller: maxPayload,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Charge max (kg)'),
                ),
                TextField(
                  controller: airPricePerKg,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Prix/kg avion (FCFA)'),
                ),
                TextField(
                  controller: seaPricePerKg,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Prix/kg bateau (FCFA)'),
                ),
                TextField(
                  controller: averageEta,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'ETA moyen (jours)'),
                ),
                TextField(
                  controller: insuranceDate,
                  decoration: const InputDecoration(
                      labelText: 'Assurance valide jusqu\'au (YYYY-MM-DD)'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: customs,
                  onChanged: (v) => setDialogState(() => customs = v),
                  title: const Text('Licence douaniere'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                final token = context.read<SessionStore>().token;
                final payload = {
                  'company_name': company.text.trim(),
                  'coverage_countries': countries.text.trim(),
                  'operating_zones': zones.text.trim(),
                  'vehicle_count': int.tryParse(vehicles.text) ?? 0,
                  'vehicle_types': vehicleTypes.text.trim(),
                  'max_payload_kg': int.tryParse(maxPayload.text) ?? 0,
                  'air_price_per_kg': (double.tryParse(
                              airPricePerKg.text.trim().replaceAll(',', '.')) ??
                          0)
                      .toStringAsFixed(2),
                  'sea_price_per_kg': (double.tryParse(
                              seaPricePerKg.text.trim().replaceAll(',', '.')) ??
                          0)
                      .toStringAsFixed(2),
                  'average_eta_days': int.tryParse(averageEta.text) ?? 0,
                  'insurance_valid_until': insuranceDate.text.trim().isEmpty
                      ? null
                      : insuranceDate.text.trim(),
                  'has_customs_license': customs,
                  'is_active': true,
                };
                try {
                  if (existing == null) {
                    await _api.post('/api/transport-profiles/', payload,
                        token: token);
                  } else {
                    await _api.patch(
                        '/api/transport-profiles/${existing['id']}/', payload,
                        token: token);
                  }
                  if (!mounted || !ctx.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profil enregistre.')));
                  await _refresh();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _api.toUserMessage(
                          e,
                          fallback: 'Mise a jour profil echouee.',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterShipments(
    List<Map<String, dynamic>> shipments,
    List<Map<String, dynamic>> disputes,
  ) {
    if (_shipmentFilter == 'ALL') return shipments;
    if (_shipmentFilter == 'IN_TRANSIT') {
      return shipments.where((s) => '${s['status']}' == 'IN_TRANSIT').toList();
    }
    if (_shipmentFilter == 'PENDING') {
      return shipments
          .where((s) => '${s['status']}' == 'PICKUP_PENDING')
          .toList();
    }
    if (_shipmentFilter == 'LATE') {
      return shipments.where(_isLateShipment).toList();
    }
    if (_shipmentFilter == 'DISPUTED') {
      final openDisputedShipmentIds = disputes
          .where((d) => '${d['status']}' == 'OPEN')
          .map((d) => d['shipment'])
          .whereType<int>()
          .toSet();
      return shipments
          .where((s) => openDisputedShipmentIds.contains(s['id']))
          .toList();
    }
    return shipments;
  }

  bool _isLateShipment(Map<String, dynamic> shipment) {
    final expected = shipment['expected_delivery_at']?.toString();
    final status = '${shipment['status']}';
    if (expected == null || expected.isEmpty) return false;
    if (status == 'DELIVERED' || status == 'CANCELLED') return false;
    final parsed = DateTime.tryParse(expected);
    if (parsed == null) return false;
    return parsed.toLocal().isBefore(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace Transitaire'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
          _RoleMenu(session: session),
        ],
      ),
      body: FutureBuilder<_TransitPayload>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final payload = snapshot.data!;
          _latestShipments = payload.shipments;
          _latestProfile =
              payload.profiles.isNotEmpty ? payload.profiles.first : null;
          final filteredShipments =
              _filterShipments(payload.shipments, payload.disputes);
          final inTransit = payload.shipments
              .where((s) => "${s['status']}" == 'IN_TRANSIT')
              .length;
          final pendingQuotes =
              payload.quotes.where((q) => "${q['status']}" == 'PENDING').length;
          final pendingCompliance = payload.complianceDocs
              .where((d) => "${d['status']}" == 'PENDING')
              .length;
          final lateShipments = payload.shipments.where(_isLateShipment).length;
          final activeProfile =
              payload.profiles.isNotEmpty ? payload.profiles.first : null;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.4,
                children: [
                  _KpiCard(title: 'Missions', value: '${payload.shipments.length}'),
                  _KpiCard(title: 'En transit', value: '$inTransit'),
                  _KpiCard(title: 'Retards', value: '$lateShipments'),
                ],
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Certifications',
                icon: Icons.verified_user_outlined,
                body: _SimpleList(
                  items: [
                    _SimpleItem(
                        title: 'Documents en attente',
                        subtitle: '$pendingCompliance'),
                    ...payload.complianceDocs.take(4).map((doc) {
                      return _SimpleItem(
                        title: (doc['doc_type'] ?? '-').toString(),
                        subtitle: "Statut: ${doc['status'] ?? '-'}",
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Profil transport',
                icon: Icons.badge_outlined,
                actions: [
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _createOrUpdateProfileDialog(activeProfile),
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(activeProfile == null
                        ? 'Creer profil'
                        : 'Modifier profil'),
                  ),
                ],
                body: activeProfile == null
                    ? const Text('Aucun profil actif.')
                    : _SimpleList(
                        items: [
                          _SimpleItem(
                              title: 'Societe',
                              subtitle: (activeProfile['company_name'] ?? '-')
                                  .toString()),
                          _SimpleItem(
                              title: 'Couverture',
                              subtitle:
                                  (activeProfile['coverage_countries'] ?? '-')
                                      .toString()),
                          _SimpleItem(
                              title: 'Zones',
                              subtitle:
                                  (activeProfile['operating_zones'] ?? '-')
                                      .toString()),
                          _SimpleItem(
                            title: 'Vehicules',
                            subtitle:
                                "${activeProfile['vehicle_count'] ?? 0} (${activeProfile['vehicle_types'] ?? '-'})",
                          ),
                          _SimpleItem(
                              title: 'Capacite max',
                              subtitle:
                                  "${activeProfile['max_payload_kg'] ?? 0} kg"),
                          _SimpleItem(
                              title: 'Prix/kg avion',
                              subtitle:
                                  "${activeProfile['air_price_per_kg'] ?? 0} FCFA"),
                          _SimpleItem(
                              title: 'Prix/kg bateau',
                              subtitle:
                                  "${activeProfile['sea_price_per_kg'] ?? 0} FCFA"),
                          _SimpleItem(
                              title: 'ETA moyen',
                              subtitle:
                                  "${activeProfile['average_eta_days'] ?? 0} jours"),
                          _SimpleItem(
                              title: 'Rating',
                              subtitle: "${activeProfile['rating'] ?? 0}"),
                        ],
                      ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Missions logistiques',
                icon: Icons.local_shipping_outlined,
                actions: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._shipmentFilters.map(
                        (item) => _filterChip(
                          item['label'] ?? item['value']!,
                          item['value']!,
                        ),
                      ),
                    ],
                  ),
                ],
                body: filteredShipments.isEmpty
                    ? const Text('Aucune mission pour ce filtre.')
                    : Column(
                        children: filteredShipments.take(8).map((shipment) {
                          return Card(
                            child: ListTile(
                              title: Text("Expedition #${shipment['id']}"),
                              subtitle: Text(
                                "${shipment['pickup_address'] ?? '-'} -> ${shipment['dropoff_address'] ?? '-'}\n"
                                "Statut: ${shipment['status']}",
                              ),
                              isThreeLine: true,
                              trailing: IconButton(
                                icon: const Icon(Icons.more_horiz),
                                onPressed: () => _openShipmentActions(shipment),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Devis emis',
                icon: Icons.payments_outlined,
                body: _SimpleList(
                  items: payload.quotes.take(8).map((quote) {
                    return _SimpleItem(
                      title: "Devis #${quote['id']}",
                      subtitle:
                          "Frais: ${quote['fee']} | ETA: ${quote['eta_days']}j | ${quote['status']}",
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 10),
              _WindowCard(
                title: 'Litiges',
                icon: Icons.report_problem_outlined,
                actions: [
                  TextButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ShipmentDisputesPage())),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('Voir tout'),
                  ),
                ],
                body: _SimpleList(
                  items: payload.disputes.take(5).map((d) {
                    final disputeId = d['id'] as int?;
                    return _SimpleItem(
                      title: "Dossier #$disputeId",
                      subtitle: "${d['reason'] ?? '-'} · ${d['status'] ?? '-'}",
                      onTap: disputeId == null ? null : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DisputeDetailPage(disputeId: disputeId),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
              Text('Devis en attente: $pendingQuotes',
                  style: const TextStyle(color: Colors.black54)),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: _onBottomNavTapped,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Accueil'),
            NavigationDestination(
                icon: Icon(Icons.badge_outlined),
                selectedIcon: Icon(Icons.badge),
                label: 'Profil'),
            NavigationDestination(
                icon: Icon(Icons.refresh_outlined),
                selectedIcon: Icon(Icons.refresh),
                label: 'Refresh'),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'Mission',
            ),
            NavigationDestination(
              icon: Icon(Icons.gavel_outlined),
              selectedIcon: Icon(Icons.gavel),
              label: 'Litiges',
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    return FilterChip(
      selected: _shipmentFilter == value,
      label: Text(label),
      onSelected: (_) => setState(() => _shipmentFilter = value),
    );
  }

  void _openShipmentActions(Map<String, dynamic> shipment) {
    final shipmentId = shipment['id'] as int;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: [
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined, color: Colors.blue),
            title: const Text('Logger evenement de garde'),
            onTap: () async {
              Navigator.pop(context);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustodyEventPage(shipmentId: shipmentId),
                ),
              );
              if (result == true) _refresh();
            },
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined, color: Colors.green),
            title: const Text('Poster un devis'),
            onTap: () async {
              Navigator.pop(context);
              await _openQuoteDialog(shipment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.update_outlined, color: Colors.orange),
            title: const Text('Mettre a jour statut'),
            onTap: () async {
              Navigator.pop(context);
              await _openStatusDialog(shipment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined, color: Colors.teal),
            title: const Text('Soumettre preuve de livraison'),
            onTap: () async {
              Navigator.pop(context);
              await _openProofDialog(shipment);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined, color: Colors.red),
            title: const Text('Ouvrir un litige'),
            onTap: () async {
              Navigator.pop(context);
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DisputeCreatePage(shipmentId: shipmentId),
                ),
              );
              _refresh();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _openQuoteDialog(Map<String, dynamic> shipment) async {
    final feeController = TextEditingController();
    final etaController =
        TextEditingController(text: _defaultQuoteEtaDays.toString());
    final notesController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Devis expedition #${shipment['id']}"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Frais'),
              ),
              TextField(
                controller: etaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ETA (jours)'),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              await _postShipmentAction(
                "/api/shipments/${shipment['id']}/post_quote/",
                {
                  'fee': double.tryParse(feeController.text) ?? 0,
                  'eta_days': int.tryParse(etaController.text) ?? 0,
                  'notes': notesController.text.trim(),
                },
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _openStatusDialog(Map<String, dynamic> shipment) async {
    if (_shipmentUpdateStatuses.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Aucun statut de mise a jour disponible.')),
      );
      return;
    }
    final statuses = _shipmentUpdateStatuses;
    String selectedStatus = statuses.first;
    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Statut expedition #${shipment['id']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedStatus,
                items: statuses
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedStatus = value);
                  }
                },
                decoration: const InputDecoration(labelText: 'Nouveau statut'),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () async {
                await _postShipmentAction(
                  "/api/shipments/${shipment['id']}/update_status/",
                  {
                    'status': selectedStatus,
                    'note': noteController.text.trim()
                  },
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProofDialog(Map<String, dynamic> shipment) async {
    final otpController = TextEditingController();
    final signerController = TextEditingController();
    final latitudeController = TextEditingController();
    final longitudeController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Preuve expedition #${shipment['id']}"),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'OTP (6 chiffres)'),
              ),
              TextField(
                controller: signerController,
                decoration: const InputDecoration(labelText: 'Signe par'),
              ),
              TextField(
                controller: latitudeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
              ),
              TextField(
                controller: longitudeController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              await _postShipmentAction(
                "/api/shipments/${shipment['id']}/submit_proof/",
                {
                  'otp': otpController.text.trim(),
                  'signed_by': signerController.text.trim(),
                  'latitude': double.tryParse(latitudeController.text),
                  'longitude': double.tryParse(longitudeController.text),
                },
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  Future<void> _postShipmentAction(
      String path, Map<String, dynamic> payload) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(path, payload, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Action executee.')));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action indisponible ou invalide.')));
    }
  }

  void _onBottomNavTapped(int index) {
    setState(() => _navIndex = index);
    if (index == 0) return;
    if (index == 1) {
      _createOrUpdateProfileDialog(_latestProfile);
      return;
    }
    if (index == 2) {
      _refresh();
      return;
    }
    if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ShipmentDisputesPage()),
      );
      return;
    }
    if (_latestShipments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune mission disponible.')));
      return;
    }
    _openShipmentActions(_latestShipments.first);
  }
}

class _TransitPayload {
  const _TransitPayload({
    required this.shipments,
    required this.quotes,
    required this.profiles,
    required this.disputes,
    required this.complianceDocs,
    required this.fallback,
  });

  final List<Map<String, dynamic>> shipments;
  final List<Map<String, dynamic>> quotes;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> disputes;
  final List<Map<String, dynamic>> complianceDocs;
  final bool fallback;
}

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.session});
  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.verified_user_outlined, size: 16),
      label: Text(session.role.name),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _WindowCard extends StatelessWidget {
  const _WindowCard(
      {required this.title, required this.icon, this.body, this.actions});
  final String title;
  final IconData icon;
  final Widget? body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x11000000), blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(title)
          ]),
          if (actions != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions!),
          ],
          if (body != null) ...[
            const SizedBox(height: 10),
            body!,
          ],
        ],
      ),
    );
  }
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({required this.items});
  final List<_SimpleItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('Aucune donnee.');
    return Column(
      children: items
          .map(
            (item) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(item.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.subtitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: item.onTap != null
                  ? const Icon(Icons.chevron_right, size: 16)
                  : null,
              onTap: item.onTap,
            ),
          )
          .toList(),
    );
  }
}

class _SimpleItem {
  const _SimpleItem({required this.title, required this.subtitle, this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
}

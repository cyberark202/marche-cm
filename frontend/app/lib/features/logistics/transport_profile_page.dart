import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class TransportProfilePage extends StatefulWidget {
  const TransportProfilePage({super.key});

  @override
  State<TransportProfilePage> createState() => _TransportProfilePageState();
}

class _TransportProfilePageState extends State<TransportProfilePage> {
  final ApiService _api = ApiService();
  final TextEditingController _companyController = TextEditingController();
  final TextEditingController _coverageController = TextEditingController();
  final TextEditingController _zonesController = TextEditingController();
  final TextEditingController _vehicleCountController = TextEditingController();
  final TextEditingController _vehicleTypesController = TextEditingController();
  final TextEditingController _maxPayloadController = TextEditingController();
  final TextEditingController _airPricePerKgController =
      TextEditingController();
  final TextEditingController _seaPricePerKgController =
      TextEditingController();
  final TextEditingController _averageEtaController = TextEditingController();
  final TextEditingController _insuranceDateController =
      TextEditingController();
  bool _hasCustomsLicense = false;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _profiles = const [];
  int _defaultAirPricePerKg = 3500;
  int _defaultSeaPricePerKg = 1800;

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "logistics")) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _companyController.dispose();
    _coverageController.dispose();
    _zonesController.dispose();
    _vehicleCountController.dispose();
    _vehicleTypesController.dispose();
    _maxPayloadController.dispose();
    _airPricePerKgController.dispose();
    _seaPricePerKgController.dispose();
    _averageEtaController.dispose();
    _insuranceDateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<SessionStore>().token;
    try {
      _profiles = await _api.getList("/api/transport-profiles/", token: token);
      if (_profiles.isNotEmpty) {
        final profile = _profiles.first;
        _companyController.text = (profile["company_name"] ?? "").toString();
        _coverageController.text =
            (profile["coverage_countries"] ?? _coverageController.text)
                .toString();
        _zonesController.text = (profile["operating_zones"] ?? "").toString();
        _vehicleCountController.text =
            (profile["vehicle_count"] ?? 0).toString();
        _vehicleTypesController.text =
            (profile["vehicle_types"] ?? "").toString();
        _maxPayloadController.text =
            (profile["max_payload_kg"] ?? 0).toString();
        _airPricePerKgController.text =
            (profile["air_price_per_kg"] ?? _defaultAirPricePerKg).toString();
        _seaPricePerKgController.text =
            (profile["sea_price_per_kg"] ?? _defaultSeaPricePerKg).toString();
        _averageEtaController.text =
            (profile["average_eta_days"] ?? 0).toString();
        _insuranceDateController.text =
            (profile["insurance_valid_until"] ?? "").toString();
        _hasCustomsLicense = profile["has_customs_license"] == true;
      }
    } catch (_) {
      _profiles = const [];
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final defaultCountry = BackendUiConfigService.instance
          .readString(config, ["defaults", "country_code"]);
      final defaultAir = BackendUiConfigService.instance
          .readInt(config, ["defaults", "transport_air_price_per_kg"]);
      final defaultSea = BackendUiConfigService.instance
          .readInt(config, ["defaults", "transport_sea_price_per_kg"]);
      if (_coverageController.text.trim().isEmpty &&
          defaultCountry.isNotEmpty) {
        _coverageController.text = defaultCountry;
      }
      _defaultAirPricePerKg =
          defaultAir > 0 ? defaultAir : _defaultAirPricePerKg;
      _defaultSeaPricePerKg =
          defaultSea > 0 ? defaultSea : _defaultSeaPricePerKg;
      if (_airPricePerKgController.text.trim().isEmpty) {
        _airPricePerKgController.text = _defaultAirPricePerKg.toString();
      }
      if (_seaPricePerKgController.text.trim().isEmpty) {
        _seaPricePerKgController.text = _defaultSeaPricePerKg.toString();
      }
    } catch (_) {}
  }

  Future<void> _saveProfile() async {
    final token = context.read<SessionStore>().token;
    final payload = {
      "company_name": _companyController.text.trim(),
      "coverage_countries": _coverageController.text.trim(),
      "operating_zones": _zonesController.text.trim(),
      "vehicle_count": int.tryParse(_vehicleCountController.text) ?? 0,
      "vehicle_types": _vehicleTypesController.text.trim(),
      "max_payload_kg": int.tryParse(_maxPayloadController.text) ?? 0,
      "air_price_per_kg": (double.tryParse(
                  _airPricePerKgController.text.trim().replaceAll(",", ".")) ??
              0)
          .toStringAsFixed(2),
      "sea_price_per_kg": (double.tryParse(
                  _seaPricePerKgController.text.trim().replaceAll(",", ".")) ??
              0)
          .toStringAsFixed(2),
      "average_eta_days": int.tryParse(_averageEtaController.text) ?? 0,
      "insurance_valid_until": _insuranceDateController.text.trim().isEmpty
          ? null
          : _insuranceDateController.text.trim(),
      "has_customs_license": _hasCustomsLicense,
      "is_active": true,
    };
    try {
      if (_profiles.isEmpty) {
        await _api.post("/api/transport-profiles/", payload, token: token);
      } else {
        await _api.patch(
          "/api/transport-profiles/${_profiles.first["id"]}/",
          payload,
          token: token,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Configuration transport enregistree.")),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                _api.toUserMessage(e, fallback: "Enregistrement impossible."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfile = _profiles.isNotEmpty;
    final airText = _airPricePerKgController.text.trim().isEmpty
        ? "0 FCFA/kg"
        : "${_airPricePerKgController.text.trim()} FCFA/kg";
    final seaText = _seaPricePerKgController.text.trim().isEmpty
        ? "0 FCFA/kg"
        : "${_seaPricePerKgController.text.trim()} FCFA/kg";
    final etaText = _averageEtaController.text.trim().isEmpty
        ? "-"
        : "${_averageEtaController.text.trim()} jour(s)";

    return Scaffold(
      appBar: AppBar(title: const Text("Profil transporteur")),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AppHeaderPanel(
              title: "Configuration transport",
              subtitle:
                  "Definissez vos tarifs avion/bateau, votre couverture et vos capacites logistiques.",
              trailing: Icon(
                hasProfile ? Icons.verified_outlined : Icons.settings_outlined,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppMetricTile(
                    label: "Tarif avion",
                    value: airText,
                    icon: Icons.flight_takeoff_outlined,
                    tint: AppPalette.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppMetricTile(
                    label: "Tarif bateau",
                    value: seaText,
                    icon: Icons.directions_boat_outlined,
                    tint: AppPalette.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppMetricTile(
                    label: "ETA moyen",
                    value: etaText,
                    icon: Icons.schedule_outlined,
                    tint: AppPalette.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            AppSectionCard(
              child: Column(
                children: [
                  TextField(
                      controller: _companyController,
                      decoration:
                          const InputDecoration(labelText: "Nom societe")),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _coverageController,
                      decoration: const InputDecoration(
                          labelText: "Pays couverts (CSV)")),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _zonesController,
                      decoration: const InputDecoration(
                          labelText: "Zones operationnelles")),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _vehicleCountController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: "Nombre vehicules"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: _vehicleTypesController,
                      decoration: const InputDecoration(
                          labelText: "Types de vehicules")),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _maxPayloadController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: "Charge max (kg)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _airPricePerKgController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: "Prix/kg avion (FCFA)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _seaPricePerKgController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: "Prix/kg bateau (FCFA)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _averageEtaController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: "ETA moyen (jours)"),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _insuranceDateController,
                    decoration: const InputDecoration(
                        labelText: "Assurance valide jusqu'au (YYYY-MM-DD)"),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hasCustomsLicense,
                    onChanged: (value) =>
                        setState(() => _hasCustomsLicense = value),
                    title: const Text("Licence douaniere"),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _saveProfile,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        _profiles.isEmpty
                            ? "Creer profil"
                            : "Mettre a jour profil",
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasProfile) ...[
              const SizedBox(height: 8),
              AppSectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Resume actuel",
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    for (final p in _profiles)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text((p["company_name"] ?? "").toString()),
                        subtitle: Text(
                          "${p["coverage_countries"]} | vehicules: ${p["vehicle_count"]}\n"
                          "types: ${p["vehicle_types"] ?? "-"} | charge max: ${p["max_payload_kg"] ?? 0}kg\n"
                          "avion: ${p["air_price_per_kg"] ?? 0} FCFA/kg | bateau: ${p["sea_price_per_kg"] ?? 0} FCFA/kg",
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

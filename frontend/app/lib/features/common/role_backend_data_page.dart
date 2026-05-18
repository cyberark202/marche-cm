import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

class RoleBackendDataPage extends StatefulWidget {
  const RoleBackendDataPage({super.key});

  @override
  State<RoleBackendDataPage> createState() => _RoleBackendDataPageState();
}

class _RoleBackendDataPageState extends State<RoleBackendDataPage> {
  final ApiService _api = ApiService();
  bool _loading = true;
  String? _error;
  List<_EndpointResult> _results = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionStore>();
    final token = session.token;
    final endpoints = _endpointsForRole(session.role);
    try {
      final out = <_EndpointResult>[];
      for (final ep in endpoints) {
        try {
          if (ep.kind == _EndpointKind.list) {
            final rows = await _api.getList(ep.path, token: token);
            out.add(
              _EndpointResult(
                path: ep.path,
                success: true,
                count: rows.length,
                preview: rows.isEmpty ? null : rows.first,
              ),
            );
          } else {
            final obj = await _api.getObject(ep.path, token: token);
            out.add(
              _EndpointResult(
                path: ep.path,
                success: true,
                count: 1,
                preview: obj,
              ),
            );
          }
        } catch (e) {
          out.add(
            _EndpointResult(
              path: ep.path,
              success: false,
              error: e.toString().replaceFirst("Exception: ", ""),
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _results = out;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = "Chargement impossible.";
        _loading = false;
      });
    }
  }

  List<_EndpointSpec> _endpointsForRole(UserRole role) {
    final common = <_EndpointSpec>[
      const _EndpointSpec("/api/auth/me/", kind: _EndpointKind.object),
      const _EndpointSpec("/api/wallets/"),
      const _EndpointSpec("/api/wallets/transactions/"),
      const _EndpointSpec("/api/chat/rooms/"),
      const _EndpointSpec("/api/chat/messages/"),
      const _EndpointSpec("/api/compliance-documents/"),
    ];
    switch (role) {
      case UserRole.generalAdmin:
        return [
          ...common,
          const _EndpointSpec("/api/admin/dashboard/", kind: _EndpointKind.object),
          const _EndpointSpec("/api/users/"),
          const _EndpointSpec("/api/users/online/"),
          const _EndpointSpec("/api/orders/"),
          const _EndpointSpec("/api/shipments/"),
          const _EndpointSpec("/api/shipment-disputes/"),
          const _EndpointSpec("/api/products/"),
          const _EndpointSpec("/api/rfqs/"),
          const _EndpointSpec("/api/rfq-offers/"),
          const _EndpointSpec("/api/transport-profiles/"),
          const _EndpointSpec("/api/transport-quotes/"),
        ];
      case UserRole.supplier:
        return [
          ...common,
          const _EndpointSpec("/api/products/mine/"),
          const _EndpointSpec("/api/orders/"),
          const _EndpointSpec("/api/shipments/"),
          const _EndpointSpec("/api/rfqs/"),
          const _EndpointSpec("/api/rfq-offers/"),
          const _EndpointSpec("/api/shipment-disputes/"),
        ];
      case UserRole.wholesaler:
        return [
          ...common,
          const _EndpointSpec("/api/products/mine/"),
          const _EndpointSpec("/api/orders/"),
          const _EndpointSpec("/api/shipments/"),
          const _EndpointSpec("/api/campaigns/"),
          const _EndpointSpec("/api/rfqs/"),
          const _EndpointSpec("/api/rfq-offers/"),
          const _EndpointSpec("/api/shipment-disputes/"),
        ];
      case UserRole.transitAgent:
        return [
          ...common,
          const _EndpointSpec("/api/orders/"),
          const _EndpointSpec("/api/shipments/"),
          const _EndpointSpec("/api/shipment-disputes/"),
          const _EndpointSpec("/api/transport-profiles/"),
          const _EndpointSpec("/api/transport-quotes/"),
        ];
      case UserRole.buyer:
        return [
          ...common,
          const _EndpointSpec("/api/products/"),
          const _EndpointSpec("/api/products/recommended/"),
          const _EndpointSpec("/api/orders/"),
          const _EndpointSpec("/api/shipments/"),
          const _EndpointSpec("/api/shipment-disputes/"),
          const _EndpointSpec("/api/rfqs/"),
          const _EndpointSpec("/api/rfq-offers/"),
          const _EndpointSpec("/api/transport-profiles/"),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionStore>().role;
    return Scaffold(
      appBar: AppBar(
        title: Text("Donnees backend (${role.name})"),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: _results.map((r) {
                    return Card(
                      child: ListTile(
                        title: Text(r.path),
                        subtitle: Text(
                          r.success
                              ? "OK | count=${r.count}\n${_previewString(r.preview)}"
                              : "ERREUR | ${r.error}",
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          r.success ? Icons.check_circle : Icons.error_outline,
                          color: r.success ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                        ),
                      ),
                    );
                  }).toList(),
                ),
    );
  }

  String _previewString(Map<String, dynamic>? value) {
    if (value == null) return "{}";
    final encoded = jsonEncode(value);
    return encoded.length > 160 ? "${encoded.substring(0, 160)}..." : encoded;
  }
}

enum _EndpointKind { list, object }

class _EndpointSpec {
  const _EndpointSpec(this.path, {this.kind = _EndpointKind.list});
  final String path;
  final _EndpointKind kind;
}

class _EndpointResult {
  const _EndpointResult({
    required this.path,
    required this.success,
    this.count = 0,
    this.preview,
    this.error,
  });

  final String path;
  final bool success;
  final int count;
  final Map<String, dynamic>? preview;
  final String? error;
}

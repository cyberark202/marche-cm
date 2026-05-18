import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/realtime_events_service.dart';
import '../auth/session_store.dart';

class ComplianceDocumentsPage extends StatefulWidget {
  const ComplianceDocumentsPage({super.key});

  @override
  State<ComplianceDocumentsPage> createState() =>
      _ComplianceDocumentsPageState();
}

class _ComplianceDocumentsPageState extends State<ComplianceDocumentsPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  List<Map<String, dynamic>> _docs = const [];
  List<String> _certTypes = const [];
  bool _loading = true;
  String _selectedType = "";
  PlatformFile? _selectedFile;

  String? _safePlatformFilePath(PlatformFile file) {
    if (kIsWeb) {
      return null;
    }
    try {
      final path = file.path;
      if (path == null || path.isEmpty) {
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  bool _canAccess(UserRole role) {
    return role == UserRole.supplier ||
        role == UserRole.wholesaler ||
        role == UserRole.transitAgent;
  }

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, "compliance")) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final role = context.read<SessionStore>().role;
    if (!_canAccess(role)) {
      _docs = const [];
      if (mounted) setState(() => _loading = false);
      return;
    }
    final token = context.read<SessionStore>().token;
    try {
      _docs = await _api.getList("/api/compliance-documents/", token: token);
    } catch (_) {
      _docs = const [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final certTypes = BackendUiConfigService.instance
          .readStringList(config, ["choices", "compliance_doc_types"]);
      if (!mounted) return;
      setState(() {
        _certTypes = certTypes;
        if (_selectedType.isEmpty && certTypes.isNotEmpty) {
          _selectedType = certTypes.first;
        }
      });
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: kIsWeb,
    );
    if (result == null || result.files.isEmpty) return;
    final selected = result.files.single;
    final hasPath = _safePlatformFilePath(selected) != null;
    final hasBytes = selected.bytes != null && selected.bytes!.isNotEmpty;
    if (!hasPath && !hasBytes) return;
    setState(() => _selectedFile = selected);
  }

  Future<void> _upload() async {
    final role = context.read<SessionStore>().role;
    if (!_canAccess(role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Acces reserve aux fournisseurs, grossistes et transitaires.")),
      );
      return;
    }
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Sélectionnez un fichier certification.")));
      return;
    }
    if (_selectedType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Aucun type de certification disponible.")));
      return;
    }
    final token = context.read<SessionStore>().token;
    try {
      await _api.postMultipart(
        "/api/compliance-documents/",
        fields: {"doc_type": _selectedType},
        file: _selectedFile,
        token: token,
      );
      setState(() => _selectedFile = null);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Echec upload certification."))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<SessionStore>().role;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_canAccess(role)) {
      return Scaffold(
        appBar: AppBar(title: const Text("Mes certifications")),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                "Cet espace est reserve aux fournisseurs, grossistes et transitaires."),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text("Mes certifications")),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFEFFCF1),
                borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Uploader une certification",
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedType.isEmpty ? null : _selectedType,
                  items: _certTypes
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedType = v ?? _selectedType),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedFile == null
                            ? "Aucun fichier sélectionné"
                            : _selectedFile!.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                        onPressed: _pickFile, child: const Text("Choisir")),
                    FilledButton(
                        onPressed: _upload, child: const Text("Uploader")),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final doc in _docs)
            Card(
              child: ListTile(
                title: Text("${doc["doc_type"]}"),
                subtitle: Text("Statut: ${doc["status"]}"),
                trailing: _statusChip((doc["status"] ?? "").toString()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color = const Color(0xFFF59E0B);
    if (status == "APPROVED") color = const Color(0xFF16A34A);
    if (status == "REJECTED") color = const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Text(status,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 11)),
    );
  }
}

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/realtime_events_service.dart';
import '../auth/auth_api_service.dart';
import '../auth/session_store.dart';
import '../auth/sensitive_action_service.dart';
import '../business/campaigns_page.dart';
import '../business/rfq_offers_page.dart';
import '../business/rfqs_page.dart';
import '../common/support_center_page.dart';
import '../logistics/shipment_disputes_page.dart';
import '../logistics/transport_profile_page.dart';
import '../innovation/innovation_hub_page.dart';
import 'compliance_documents_page.dart';
import 'security_center_page.dart';
import '../wallet/wallet_page.dart';

class ProfileHubPage extends StatefulWidget {
  const ProfileHubPage({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  State<ProfileHubPage> createState() => _ProfileHubPageState();
}

class _ProfileHubPageState extends State<ProfileHubPage> {
  final ApiService _api = ApiService();
  final AuthApiService _authApi = AuthApiService();
  final SensitiveActionService _sensitiveActionService =
      SensitiveActionService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  Map<String, dynamic> _me = const {};
  List<Map<String, dynamic>> _onlineUsers = const [];
  List<Map<String, dynamic>> _wallets = const [];
  bool _loading = true;

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

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final t = (event["topic"] ?? "").toString();
      if (t == "profiles" ||
          t == "wallets" ||
          t == "compliance" ||
          t == "analytics") {
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
    final token = context.read<SessionStore>().token;
    try {
      _me = await _api.getObject("/api/auth/me/", token: token);
      _onlineUsers = await _api.getList("/api/users/online/", token: token);
      _wallets = await _api.getList("/api/wallets/", token: token);
    } catch (_) {
      _me = const {};
      _onlineUsers = const [];
      _wallets = const [];
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final canAccessCompliance = session.role == UserRole.supplier ||
        session.role == UserRole.wholesaler ||
        session.role == UserRole.transitAgent;
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Mon profil",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text("Rôle actif: ${session.role.name}"),
                      ],
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.verified_user_outlined, size: 16),
                    label: Text(session.role.name),
                  ),
                ],
              ),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(
                      _resolveMediaUrl((_me["avatar_url"] ?? "").toString()),
                    ),
                  ),
                  title: Text(
                    (_me["name"] ??
                            _me["username"] ??
                            session.username ??
                            "Compte")
                        .toString(),
                  ),
                  subtitle: Text(
                    "Ref: ${(_me["reference_code"] ?? "").toString().isEmpty ? "-" : _me["reference_code"]}",
                  ),
                  trailing: TextButton.icon(
                    onPressed: _openProfileEditDialog,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text("Modifier"),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Wallet"),
                  subtitle: Text(
                    _wallets.isEmpty
                        ? "Aucun wallet"
                        : "Solde: ${_wallets.first["balance"]} | Bloqué: ${_wallets.first["blocked_balance"]}",
                  ),
                  trailing: const Icon(Icons.account_balance_wallet_outlined),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletPage()),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Utilisateurs en ligne"),
                  subtitle: Text("${_onlineUsers.length} connectés"),
                  onTap: () => _showOnlineUsers(context),
                ),
              ),
              if (canAccessCompliance)
                Card(
                  child: ListTile(
                    title: const Text("Conformité/KYC"),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ComplianceDocumentsPage())),
                  ),
                ),
              if (session.role == UserRole.wholesaler)
                Card(
                  child: ListTile(
                    title: const Text("Campagnes"),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const CampaignsPage())),
                  ),
                ),
              Card(
                child: ListTile(
                  title: const Text("Securite du compte"),
                  subtitle: const Text(
                      "Sessions actives, mot de passe, verification"),
                  trailing: const Icon(Icons.shield_outlined),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SecurityCenterPage()),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Innovation Hub (15 features)"),
                  subtitle: const Text(
                      "Escrow split, RFQ compare, alerts, loyalty, webhooks..."),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const InnovationHubPage()),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Demandes RFQ"),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RfqsPage())),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Offres RFQ"),
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RfqOffersPage())),
                ),
              ),
              if (session.role == UserRole.transitAgent)
                Card(
                  child: ListTile(
                    title: const Text("Profil transport"),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const TransportProfilePage())),
                  ),
                ),
              Card(
                child: ListTile(
                  title: const Text("Litiges expédition"),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ShipmentDisputesPage())),
                ),
              ),
              Card(
                child: ListTile(
                  title: const Text("Support & Aide"),
                  subtitle: const Text("FAQ, contact support, assistance"),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SupportCenterPage(),
                    ),
                  ),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text("Deconnexion"),
                  subtitle: const Text("Revoque la session courante"),
                  onTap: _logout,
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text("Actualiser"),
                  onTap: () {
                    widget.onRefresh();
                    _load();
                  },
                ),
              ),
            ],
          );
  }

  void _showOnlineUsers(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(12),
        children: _onlineUsers
            .map(
              (u) => ListTile(
                leading: CircleAvatar(
                  backgroundImage: NetworkImage(
                    _resolveMediaUrl((u["avatar_url"] ?? "").toString()),
                  ),
                ),
                title: Text((u["username"] ?? "").toString()),
                subtitle: Text((u["role"] ?? "").toString()),
              ),
            )
            .toList(),
      ),
    );
  }

  String _resolveMediaUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return "https://i.pravatar.cc/200?u=profile";
    }
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return value;
    }
    final normalized = value.startsWith("/") ? value : "/$value";
    return "${AppConfig.apiBaseUrl}$normalized";
  }

  Future<void> _openProfileEditDialog() async {
    final usernameCtrl = TextEditingController(
      text: (_me["username"] ?? "").toString(),
    );
    final nameCtrl = TextEditingController(
      text: (_me["name"] ?? "").toString(),
    );
    PlatformFile? avatarFile;
    var removeAvatar = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Modifier mon profil"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: "Nom du compte"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: "Nom affiche"),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.image,
                          allowMultiple: false,
                          withData: kIsWeb,
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final selected = picked.files.single;
                        final hasPath = _safePlatformFilePath(selected) != null;
                        final hasBytes = selected.bytes != null &&
                            selected.bytes!.isNotEmpty;
                        if (!hasPath && !hasBytes) return;
                        setDialogState(() {
                          avatarFile = selected;
                          removeAvatar = false;
                        });
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text("Photo"),
                    ),
                    const SizedBox(width: 8),
                    if (avatarFile != null)
                      Expanded(
                        child: Text(
                          avatarFile!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                CheckboxListTile(
                  value: removeAvatar,
                  onChanged: (v) =>
                      setDialogState(() => removeAvatar = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Supprimer la photo actuelle"),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () async {
                final token = context.read<SessionStore>().token;
                if (token == null || token.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("Session invalide. Reconnectez-vous.")),
                  );
                  return;
                }
                try {
                  final verification =
                      await _sensitiveActionService.requestAndCollectCode(
                    context: context,
                    token: token,
                    actionKey: "profile.update",
                    actionLabel: "Mise a jour profil",
                  );
                  if (!context.mounted || verification == null) return;
                  final updated = await _api.postMultipart(
                    "/api/auth/profile/",
                    fields: {
                      "username": usernameCtrl.text.trim(),
                      "name": nameCtrl.text.trim(),
                      "remove_avatar": removeAvatar ? "true" : "false",
                      "challenge_token": verification.challengeToken,
                      "verification_code": verification.verificationCode,
                    },
                    token: token,
                    file: avatarFile,
                    fileFieldName: "avatar",
                  );
                  if (!context.mounted) return;
                  setState(() => _me = updated);
                  context.read<SessionStore>().updateProfile(
                        currentUsername: (updated["username"] ?? "").toString(),
                      );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Profil mis a jour.")),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(_api.toUserMessage(e,
                            fallback: "Echec de mise a jour du profil."))),
                  );
                }
              },
              child: const Text("Enregistrer"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final session = context.read<SessionStore>();
    try {
      final refresh = session.refreshToken;
      if (refresh != null && refresh.isNotEmpty) {
        await _authApi.logout(
            refreshToken: refresh, accessToken: session.token);
      }
    } catch (_) {}
    if (!mounted) return;
    session.logout();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Session fermee.")),
    );
  }
}

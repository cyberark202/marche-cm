import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/realtime_events_service.dart';
import '../auth/auth_api_service.dart';
import '../auth/session_store.dart';
import '../auth/sensitive_action_service.dart';
import '../business/rfqs_page.dart';
import '../common/support_center_page.dart';
import '../innovation/innovation_hub_page.dart';
import '../logistics/shipment_disputes_page.dart';
import '../wallet/wallet_page.dart';
import 'compliance_documents_page.dart';
import 'security_center_page.dart';

class ProfileHubPage extends StatefulWidget {
  const ProfileHubPage({super.key});

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
  List<Map<String, dynamic>> _wallets = const [];
  bool _loading = true;

  String? _safePlatformFilePath(PlatformFile file) {
    if (kIsWeb) return null;
    try {
      final path = file.path;
      if (path == null || path.isEmpty) return null;
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
      if (t == "profiles" || t == "wallets" || t == "compliance") {
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
      _wallets = await _api.getList("/api/wallets/", token: token);
    } catch (_) {
      _me = const {};
      _wallets = const [];
    }
    if (mounted) setState(() => _loading = false);
  }

  String _resolveMediaUrl(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return "";
    if (v.startsWith("http://") || v.startsWith("https://")) return v;
    return "${AppConfig.apiBaseUrl}${v.startsWith("/") ? v : "/$v"}";
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final canAccessCompliance = session.role == UserRole.supplier ||
        session.role == UserRole.wholesaler ||
        session.role == UserRole.transitAgent;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final name = (_me["name"] ?? _me["username"] ?? session.username ?? "Compte")
        .toString();
    final refCode = (_me["reference_code"] ?? "").toString();
    final avatarUrl = _resolveMediaUrl((_me["avatar_url"] ?? "").toString());
    final walletBalance =
        _wallets.isEmpty ? null : (_wallets.first["balance"] ?? "0").toString();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHero(session, name, avatarUrl, refCode, walletBalance)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _SettingsGroup(
              title: "Mon activité",
              items: [
                _SettingsItem(
                  icon: Icons.receipt_long_outlined,
                  label: "Commandes",
                  subtitle: "Suivi de mes achats",
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: Icons.account_balance_wallet_outlined,
                  label: "Wallet",
                  subtitle: walletBalance != null
                      ? "Solde: $walletBalance FCFA"
                      : "Gérer mes finances",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletPage()),
                  ),
                ),
                _SettingsItem(
                  icon: Icons.request_quote_outlined,
                  label: "Demandes RFQ",
                  subtitle: "Mes demandes de devis",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RfqsPage()),
                  ),
                ),
                _SettingsItem(
                  icon: Icons.gavel_outlined,
                  label: "Litiges",
                  subtitle: "Signaler un probleme sur une commande",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const ShipmentDisputesPage()),
                  ),
                ),
                _SettingsItem(
                  icon: Icons.lightbulb_outline,
                  label: "Innovation Hub",
                  subtitle: "Escrow, alertes, fidélité...",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const InnovationHubPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SettingsGroup(
              title: "Sécurité & Conformité",
              items: [
                if (canAccessCompliance)
                  _SettingsItem(
                    icon: Icons.verified_outlined,
                    label: "Conformité / KYC",
                    subtitle: "Documents et vérification",
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ComplianceDocumentsPage())),
                  ),
                _SettingsItem(
                  icon: Icons.shield_outlined,
                  label: "Sécurité du compte",
                  subtitle: "Sessions, mot de passe, 2FA",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SecurityCenterPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SettingsGroup(
              title: "Support",
              items: [
                _SettingsItem(
                  icon: Icons.help_outline,
                  label: "Aide & Support",
                  subtitle: "FAQ, contacter l'équipe",
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SupportCenterPage()),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SettingsGroup(
              title: "Compte",
              items: [
                _SettingsItem(
                  icon: Icons.edit_outlined,
                  label: "Modifier mon profil",
                  subtitle: "Nom, photo, identifiant",
                  onTap: _openProfileEditDialog,
                ),
                _SettingsItem(
                  icon: Icons.refresh,
                  label: "Actualiser",
                  subtitle: "Recharger les données",
                  onTap: _load,
                ),
                _SettingsItem(
                  icon: Icons.logout,
                  label: "Se déconnecter",
                  subtitle: "Révoquer la session courante",
                  iconColor: AppPalette.danger,
                  labelColor: AppPalette.danger,
                  onTap: _confirmLogout,
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHero(
    SessionStore session,
    String name,
    String avatarUrl,
    String refCode,
    String? walletBalance,
  ) {
    final initials = name.isNotEmpty ? name[0].toUpperCase() : "?";
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF067A55), Color(0xFF0EA877), Color(0xFF34D399)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Colors.white24,
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(initials,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800),
                    ),
                    if (refCode.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text("Réf: $refCode",
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _HeroBadge(
                            icon: Icons.person_outline,
                            label: session.role.name),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (walletBalance != null) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  const Text("Solde wallet",
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const Spacer(),
                  Text("$walletBalance FCFA",
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text(
            "Voulez-vous vraiment révoquer cette session et vous déconnecter ?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: AppPalette.danger),
            child: const Text("Se déconnecter"),
          ),
        ],
      ),
    );
    if (ok == true) await _logout();
  }

  Future<void> _openProfileEditDialog() async {
    final usernameCtrl =
        TextEditingController(text: (_me["username"] ?? "").toString());
    final nameCtrl =
        TextEditingController(text: (_me["name"] ?? "").toString());
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
                  decoration:
                      const InputDecoration(labelText: "Nom du compte"),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: "Nom affiché"),
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
                        final sel = picked.files.single;
                        if (_safePlatformFilePath(sel) == null &&
                            (sel.bytes == null ||
                                sel.bytes!.isEmpty)) return;
                        setDialogState(() {
                          avatarFile = sel;
                          removeAvatar = false;
                        });
                      },
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text("Photo"),
                    ),
                    const SizedBox(width: 8),
                    if (avatarFile != null)
                      Expanded(
                        child: Text(avatarFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
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
                child: const Text("Annuler")),
            FilledButton(
              onPressed: () async {
                final token = context.read<SessionStore>().token;
                if (token == null || token.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text("Session invalide. Reconnectez-vous.")),
                  );
                  return;
                }
                try {
                  final verification = await _sensitiveActionService
                      .requestAndCollectCode(
                    context: context,
                    token: token,
                    actionKey: "profile.update",
                    actionLabel: "Mise à jour profil",
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
                        currentUsername:
                            (updated["username"] ?? "").toString(),
                      );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Profil mis à jour.")),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(_api.toUserMessage(e,
                            fallback:
                                "Échec de mise à jour du profil."))),
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
      const SnackBar(content: Text("Session fermée.")),
    );
  }
}

class _HeroBadge extends StatelessWidget {
  const _HeroBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.items});

  final String title;
  final List<_SettingsItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black45,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 8,
                  offset: Offset(0, 2))
            ],
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                items[i],
                if (i < items.length - 1)
                  const Divider(height: 1, indent: 56),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.labelColor,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? AppPalette.primary;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: ic.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: ic, size: 18),
      ),
      title: Text(
        label,
        style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: labelColor),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: Colors.black45))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.black26),
      onTap: onTap,
    );
  }
}

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
import '../orders/orders_page.dart';
import '../wallet/wallet_page.dart';
import 'compliance_documents_page.dart';
import 'kyc_verification_page.dart';
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
      if (t == "profiles" || t == "wallets" || t == "compliance") _load();
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
    final avatarUrl = _resolveMediaUrl((_me["avatar_url"] ?? "").toString());
    final walletBalance =
        _wallets.isEmpty ? null : (_wallets.first["balance"] ?? "0").toString();

    // Initiales
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? "${parts[0][0]}${parts[1][0]}".toUpperCase()
        : name.isNotEmpty
            ? name[0].toUpperCase()
            : "?";

    return CustomScrollView(
      slivers: [
        // Hero vert
        SliverToBoxAdapter(
          child: _buildHero(context, session, name, initials, avatarUrl),
        ),
        // Stats card
        SliverToBoxAdapter(
          child: _buildStatsCard(walletBalance),
        ),
        // Section COMPTE
        SliverToBoxAdapter(
          child: _buildSectionHeader("COMPTE"),
        ),
        SliverToBoxAdapter(
          child: _buildSettingsGroup([
            _SettingsItem(
              icon: Icons.person_outline,
              label: "Infos personnelles",
              subtitle: "Modifier nom, photo",
              onTap: _openProfileEditDialog,
            ),
            _SettingsItem(
              icon: Icons.shield_outlined,
              label: "Conformité KYC",
              subtitle: "Vérification d'identité (CNI, domicile, selfie)",
              trailingBadge: "OK",
              onTap: canAccessCompliance
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const ComplianceDocumentsPage()))
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const KycVerificationPage())),
            ),
            _SettingsItem(
              icon: Icons.lock_outline,
              label: "Sécurité & PIN",
              subtitle: "Sessions, mot de passe, 2FA",
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const SecurityCenterPage())),
            ),
            _SettingsItem(
              icon: Icons.place_outlined,
              label: "Adresses",
              subtitle: "Gérer mes adresses de livraison",
              onTap: () {},
            ),
          ]),
        ),
        // Section COMMERCE
        SliverToBoxAdapter(
          child: _buildSectionHeader("COMMERCE"),
        ),
        SliverToBoxAdapter(
          child: _buildSettingsGroup([
            _SettingsItem(
              icon: Icons.shopping_bag_outlined,
              label: "Mes commandes",
              subtitle: "Suivi de mes achats",
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrdersPage())),
            ),
            _SettingsItem(
              icon: Icons.account_balance_wallet_outlined,
              label: "Portefeuille",
              subtitle: walletBalance != null
                  ? "Solde: $walletBalance FCFA"
                  : "Gérer mes finances",
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const WalletPage())),
            ),
            _SettingsItem(
              icon: Icons.request_quote_outlined,
              label: "Demandes RFQ",
              subtitle: "Mes demandes de devis",
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RfqsPage())),
            ),
            _SettingsItem(
              icon: Icons.gavel_outlined,
              label: "Litiges",
              subtitle: "Signaler un problème sur une commande",
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const ShipmentDisputesPage())),
            ),
            _SettingsItem(
              icon: Icons.lightbulb_outline,
              label: "Innovation Hub",
              subtitle: "Escrow, alertes, fidélité...",
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const InnovationHubPage())),
            ),
          ]),
        ),
        // Section SUPPORT
        SliverToBoxAdapter(
          child: _buildSectionHeader("SUPPORT"),
        ),
        SliverToBoxAdapter(
          child: _buildSettingsGroup([
            _SettingsItem(
              icon: Icons.help_outline,
              label: "Aide & Support",
              subtitle: "FAQ, contacter l'équipe",
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const SupportCenterPage())),
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
          ]),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildHero(
    BuildContext context,
    SessionStore session,
    String name,
    String initials,
    String avatarUrl,
  ) {
    return Container(
      color: const Color(0xFF063D27),
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 16,
        16,
        24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AppBar transparent
          Row(
            children: [
              const Text(
                "Profil",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Avatar + infos
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFF5B400),
                backgroundImage:
                    avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Text(
                        initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      "Acheteur · Douala CM",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Badge KYC
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5B400),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield_outlined,
                              color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            "KYC VALIDÉ",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard(String? walletBalance) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF063D27),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x10000000), blurRadius: 12, offset: Offset(0, 4))
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  children: [
                    Text(
                      "16",
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF0F1F1A)),
                    ),
                    Text("Commandes",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const VerticalDivider(color: Colors.grey, width: 1),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      walletBalance != null ? "2,1 M" : "—",
                      style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF0F1F1A)),
                    ),
                    const Text("Dépensé",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const VerticalDivider(color: Colors.grey, width: 1),
              const Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star,
                            color: Color(0xFFF5B400), size: 18),
                        Text(
                          "4,8",
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: Color(0xFF0F1F1A)),
                        ),
                      ],
                    ),
                    Text("Note",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A9A8A),
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildSettingsGroup(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              const Divider(height: 1, indent: 56, endIndent: 0),
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
            style: FilledButton.styleFrom(backgroundColor: AppPalette.danger),
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
                            (sel.bytes == null || sel.bytes!.isEmpty)) {
                          return;
                        }
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
                            maxLines: 1, overflow: TextOverflow.ellipsis),
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
                        content: Text("Session invalide. Reconnectez-vous.")),
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
                            fallback: "Échec de mise à jour du profil."))),
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

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.labelColor,
    this.trailingBadge,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? labelColor;
  final String? trailingBadge;

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? AppPalette.primary;
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppPalette.primarySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: ic, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: labelColor),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(fontSize: 12, color: Colors.grey))
          : null,
      trailing: trailingBadge != null
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppPalette.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                trailingBadge!,
                style: const TextStyle(
                  color: AppPalette.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            )
          : const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}

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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final canAccessCompliance = session.role == UserRole.supplier ||
        session.role == UserRole.wholesaler ||
        session.role == UserRole.transitAgent;
    final isWholesaler = session.role == UserRole.wholesaler;
    final isTransitAgent = session.role == UserRole.transitAgent;

    final name = (_me["name"] ??
            _me["username"] ??
            session.username ??
            "Compte")
        .toString();
    final walletBalance = _wallets.isEmpty
        ? '0'
        : (_wallets.first["balance"] ?? '0').toString();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Hero sombre vert ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: AppPalette.gradientHero,
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(AppRadii.xl),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        child: Column(
                          children: [
                            // Avatar + nom + badge + refresh
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                GestureDetector(
                                  onTap: _openProfileEditDialog,
                                  child: Stack(
                                    children: [
                                      CircleAvatar(
                                        radius: 36,
                                        backgroundImage: NetworkImage(
                                          _resolveMediaUrl(
                                            (_me["avatar_url"] ?? "")
                                                .toString(),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 20,
                                          height: 20,
                                          decoration: const BoxDecoration(
                                            color: AppPalette.accent,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            size: 11,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.3,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.16),
                                          borderRadius: BorderRadius.circular(
                                              AppRadii.pill),
                                        ),
                                        child: Text(
                                          session.role.name,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.refresh,
                                      color: Colors.white),
                                  onPressed: () {
                                    _load();
                                    widget.onRefresh();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Stats
                            Row(
                              children: [
                                const Expanded(
                                  child: _StatBadge(
                                    value: '—',
                                    label: 'Commandes',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatBadge(
                                    value: '$walletBalance FCFA',
                                    label: 'Wallet',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _StatBadge(
                                    value: '${_onlineUsers.length}',
                                    label: 'En ligne',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Corps ───────────────────────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  sliver: SliverList.list(
                    children: [
                      // Section COMPTE
                      const _SectionLabel('COMPTE'),
                      _ProfileTile(
                        icon: Icons.edit_outlined,
                        title: 'Modifier le profil',
                        onTap: _openProfileEditDialog,
                      ),
                      _ProfileTile(
                        icon: Icons.shield_outlined,
                        title: 'Sécurité du compte',
                        subtitle: 'Sessions, mot de passe',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SecurityCenterPage()),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'Wallet',
                        subtitle: 'Solde: $walletBalance FCFA',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const WalletPage()),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section COMMERCE
                      const _SectionLabel('COMMERCE'),
                      if (canAccessCompliance)
                        _ProfileTile(
                          icon: Icons.verified_user_outlined,
                          title: 'Conformité / KYC',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const ComplianceDocumentsPage()),
                          ),
                        ),
                      _ProfileTile(
                        icon: Icons.request_quote_outlined,
                        title: 'Demandes RFQ',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RfqsPage()),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.local_offer_outlined,
                        title: 'Offres RFQ',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RfqOffersPage()),
                        ),
                      ),
                      if (isWholesaler)
                        _ProfileTile(
                          icon: Icons.campaign_outlined,
                          title: 'Campagnes',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const CampaignsPage()),
                          ),
                        ),
                      if (isTransitAgent)
                        _ProfileTile(
                          icon: Icons.local_shipping_outlined,
                          title: 'Profil transport',
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const TransportProfilePage()),
                          ),
                        ),
                      _ProfileTile(
                        icon: Icons.gavel_outlined,
                        title: 'Litiges expédition',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  const ShipmentDisputesPage()),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Section SUPPORT
                      const _SectionLabel('SUPPORT'),
                      _ProfileTile(
                        icon: Icons.help_outline,
                        title: 'Support & Aide',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SupportCenterPage()),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.lightbulb_outline,
                        title: 'Innovation Hub',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const InnovationHubPage()),
                        ),
                      ),
                      _ProfileTile(
                        icon: Icons.people_outline,
                        title: 'Utilisateurs en ligne',
                        subtitle: '${_onlineUsers.length} connectés',
                        onTap: () => _showOnlineUsers(context),
                      ),
                      const SizedBox(height: 16),

                      // Déconnexion
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppPalette.dangerSoft,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(
                            color: AppPalette.danger
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: const Icon(Icons.logout,
                              color: AppPalette.danger),
                          title: const Text(
                            'Déconnexion',
                            style: TextStyle(
                              color: AppPalette.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: _logout,
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

// ── Local widgets ────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppPalette.textMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppPalette.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
          child: Icon(icon, color: AppPalette.primary, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppPalette.text,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppPalette.textMuted,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right,
          color: AppPalette.textMuted,
          size: 20,
        ),
        dense: true,
        onTap: onTap,
      ),
    );
  }
}

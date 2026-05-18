import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../auth/session_store.dart';
import '../auth/sensitive_action_service.dart';

class SecurityCenterPage extends StatefulWidget {
  const SecurityCenterPage({super.key});

  @override
  State<SecurityCenterPage> createState() => _SecurityCenterPageState();
}

class _SecurityCenterPageState extends State<SecurityCenterPage> {
  final ApiService _api = ApiService();
  final SensitiveActionService _sensitiveActionService =
      SensitiveActionService();
  List<Map<String, dynamic>> _sessions = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final payload = await _api.getObject("/api/auth/sessions/", token: token);
      final sessions = ((payload["sessions"] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _api.toUserMessage(e,
          fallback: "Impossible de charger les sessions."));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _revokeSession(String jti) async {
    if (_busy) return;
    final token = context.read<SessionStore>().token;
    setState(() => _busy = true);
    try {
      await _api.post(
        "/api/auth/sessions/",
        {"jti": jti},
        token: token,
      );
      await _loadSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session revoquee.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                _api.toUserMessage(e, fallback: "Revocation impossible."))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _revokeAllOtherSessions() async {
    if (_busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Revoquer les autres sessions"),
        content: const Text(
          "Toutes les sessions seront fermees sauf celle-ci. Continuer ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }
    final token = context.read<SessionStore>().token;
    setState(() => _busy = true);
    try {
      await _api.post(
        "/api/auth/sessions/",
        {"all_except_current": true},
        token: token,
      );
      await _loadSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Autres sessions revoquees.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                _api.toUserMessage(e, fallback: "Revocation impossible."))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _changePassword() async {
    if (_busy) return;
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Changer mot de passe"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: "Mot de passe actuel"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: "Nouveau mot de passe"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: "Confirmer nouveau mot de passe"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Continuer"),
          ),
        ],
      ),
    );

    if (!mounted || proceed != true) {
      currentPasswordController.dispose();
      newPasswordController.dispose();
      confirmPasswordController.dispose();
      return;
    }

    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();

    if (newPassword.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Le nouveau mot de passe doit contenir au moins 8 caracteres.")),
      );
      return;
    }
    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("La confirmation du mot de passe ne correspond pas.")),
      );
      return;
    }

    final token = context.read<SessionStore>().token;
    SensitiveActionVerification? verification;
    try {
      verification = await _sensitiveActionService.requestAndCollectCode(
        context: context,
        token: token,
        actionKey: "auth.password.change",
        actionLabel: "Changement mot de passe",
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                _api.toUserMessage(e, fallback: "Verification impossible."))),
      );
      return;
    }
    if (!mounted || verification == null) return;

    setState(() => _busy = true);
    try {
      await _api.post(
        "/api/auth/password-change/",
        {
          "current_password": currentPassword,
          "new_password": newPassword,
          "challenge_token": verification.challengeToken,
          "verification_code": verification.verificationCode,
        },
        token: token,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Mot de passe mis a jour. Reconnectez-vous."),
        ),
      );
      context.read<SessionStore>().logout();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Changement de mot de passe refuse."))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _sessionSubtitle(Map<String, dynamic> row) {
    final created = (row["created_at"] ?? "").toString();
    final expires = (row["expires_at"] ?? "").toString();
    final createdText =
        created.isEmpty ? "-" : created.split(".").first.replaceFirst("T", " ");
    final expiresText =
        expires.isEmpty ? "-" : expires.split(".").first.replaceFirst("T", " ");
    final statusText = row["is_blacklisted"] == true ? "Fermee" : "Active";
    return "Creation: $createdText\nExpiration: $expiresText\nStatut: $statusText";
  }

  @override
  Widget build(BuildContext context) {
    final activeSessions =
        _sessions.where((row) => row["is_blacklisted"] != true).length;
    final closedSessions =
        _sessions.where((row) => row["is_blacklisted"] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Securite du compte"),
        actions: [
          IconButton(
            onPressed: _loading ? null : _loadSessions,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const AppHeaderPanel(
              title: "Protection du compte",
              subtitle:
                  "Controlez vos sessions actives, changez votre mot de passe et verrouillez les acces suspects.",
              trailing: Icon(Icons.shield_outlined),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppMetricTile(
                    label: "Sessions actives",
                    value: "$activeSessions",
                    icon: Icons.phone_android_outlined,
                    tint: AppPalette.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppMetricTile(
                    label: "Sessions fermees",
                    value: "$closedSessions",
                    icon: Icons.mobile_off_outlined,
                    tint: AppPalette.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Actions de securite",
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _changePassword,
                      icon: const Icon(Icons.password),
                      label: Text(
                          _busy ? "Traitement..." : "Changer mot de passe"),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _revokeAllOtherSessions,
                      icon: const Icon(Icons.mobile_off),
                      label: const Text("Revoquer autres sessions"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _SectionCard(
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else if (_sessions.isEmpty)
              const _SectionCard(
                child: Text("Aucune session a afficher."),
              )
            else
              ..._sessions.map((row) {
                final isCurrent = row["is_current"] == true;
                final isBlacklisted = row["is_blacklisted"] == true;
                final jti = (row["jti"] ?? "").toString();
                return _SectionCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: isCurrent
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFE5E7EB),
                      child: Icon(
                        isCurrent ? Icons.phone_android : Icons.devices_other,
                        color: isCurrent
                            ? const Color(0xFF065F46)
                            : const Color(0xFF374151),
                      ),
                    ),
                    title: Text(
                        isCurrent ? "Session actuelle" : "Session secondaire"),
                    subtitle: Text(_sessionSubtitle(row)),
                    trailing: isCurrent || isBlacklisted
                        ? AppStatusBadge(
                            text: isCurrent ? "Courante" : "Fermee",
                            color: isCurrent
                                ? AppPalette.success
                                : AppPalette.warning,
                          )
                        : TextButton(
                            onPressed: _busy ? null : () => _revokeSession(jti),
                            child: const Text("Revoquer"),
                          ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      child: child,
    );
  }
}

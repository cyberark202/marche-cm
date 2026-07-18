import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import '../auth/auth_api_service.dart';
import '../data/admin_repository.dart';

/// Écran 41 — Configuration plateforme à chaud (doc 03/16).
///
/// Valeurs servies par /api/admin/platform-settings/ (registre + surcharges
/// historisées). La modification exige le scope admin.settings.manage ET un
/// step-up 2FA e-mail, comme la réconciliation wallet.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  final _api = ApiService();
  final _auth = AuthApiService();
  final _repo = AdminRepository.instance;
  List<Map<String, dynamic>> _settings = const [];
  bool _loading = true;
  String? _error;

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
    try {
      final data = await _api.getObject('/api/admin/platform-settings/');
      final rows = (data['settings'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _settings = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _repo.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> setting) async {
    final key = '${setting['key']}';
    final controller =
        TextEditingController(text: _display(setting['value']));
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(key),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Défaut : ${_display(setting['default'])}\n'
              'Les valeurs complexes se saisissent en JSON.',
              style: const TextStyle(
                  fontSize: 12.5, color: AppPalette.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Nouvelle valeur'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Continuer')),
        ],
      ),
    );
    if (newValue == null || newValue.isEmpty) return;

    // Step-up 2FA : identique à la réconciliation wallet.
    String challengeToken;
    try {
      challengeToken = await _auth.requestSensitiveAction('admin.settings.manage');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
      return;
    }
    if (!mounted) return;
    final code = await _askCode();
    if (code == null || code.isEmpty) return;

    try {
      await _api.put('/api/admin/platform-settings/', {
        'key': key,
        'value': _parse(newValue),
        'challenge_token': challengeToken,
        'verification_code': code,
      });
      if (!mounted) return;
      showSnack(context, 'Paramètre $key mis à jour.');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
    }
  }

  Future<String?> _askCode() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vérification 2FA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Un code à 6 chiffres vient d\'être envoyé à votre e-mail. '
              'Saisissez-le pour confirmer la modification.',
              style: TextStyle(fontSize: 13, color: AppPalette.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Code de sécurité',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }

  /// JSON si possible (nombres, booléens, objets), sinon chaîne brute.
  static dynamic _parse(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  static String _display(dynamic value) {
    if (value is Map || value is List) return jsonEncode(value);
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: _loading
          ? const AppLoadingState(label: 'Chargement de la configuration…')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      const Text('Paramètres plateforme à chaud',
                          style: TextStyle(color: AppPalette.textMuted)),
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          children: [
                            for (var i = 0; i < _settings.length; i++) ...[
                              if (i > 0) const Divider(height: 18),
                              InkWell(
                                onTap: () => _edit(_settings[i]),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${_settings[i]['key']}',
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600)),
                                          if (_settings[i]['is_default'] !=
                                              true)
                                            const Text('Surchargé',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppPalette
                                                        .secondary)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        _display(_settings[i]['value']),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            color: AppPalette.primary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(LucideIcons.pencil,
                                        size: 14,
                                        color: AppPalette.textMuted),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppPalette.infoSoft,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                        ),
                        child: const Row(
                          children: [
                            Icon(LucideIcons.shield,
                                size: 18, color: AppPalette.info),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Chaque modification est validée par 2FA '
                                'e-mail, historisée et auditée.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

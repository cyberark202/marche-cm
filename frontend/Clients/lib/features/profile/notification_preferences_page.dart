import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';

/// Préférences de notifications (doc 10).
///
/// Les alertes de sécurité et les notifications critiques restent toujours
/// actives : seuls les canaux librement désactivables sont exposés.
class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  final ApiService _api = ApiService();
  bool _promotions = true;
  bool _push = true;
  bool _loading = true;
  bool _saving = false;
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
    final token = context.read<SessionStore>().token;
    try {
      final prefs =
          await _api.getObject('/api/notifications/preferences/', token: token);
      if (!mounted) return;
      setState(() {
        _promotions = prefs['promotions_enabled'] != false;
        _push = prefs['push_enabled'] != false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(e,
            fallback: 'Impossible de charger les préférences.');
        _loading = false;
      });
    }
  }

  Future<void> _save({bool? promotions, bool? push}) async {
    setState(() {
      _saving = true;
      if (promotions != null) _promotions = promotions;
      if (push != null) _push = push;
    });
    final token = context.read<SessionStore>().token;
    try {
      await _api.patch('/api/notifications/preferences/', {
        'promotions_enabled': _promotions,
        'push_enabled': _push,
      }, token: token);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_api.toUserMessage(e,
              fallback: 'Enregistrement impossible.'))));
      _load();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de notifications')),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SwitchListTile(
                      value: _push,
                      onChanged:
                          _saving ? null : (v) => _save(push: v),
                      title: const Text('Notifications push'),
                      subtitle: const Text(
                          'Alertes sur cet appareil quand l\'application est fermée'),
                    ),
                    SwitchListTile(
                      value: _promotions,
                      onChanged:
                          _saving ? null : (v) => _save(promotions: v),
                      title: const Text('Promotions'),
                      subtitle: const Text(
                          'Offres, campagnes et annonces commerciales'),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Les alertes de sécurité (connexion, paiement, litige '
                        'critique) ne peuvent pas être désactivées.',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
    );
  }
}

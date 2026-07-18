import 'dart:async';

import 'package:flutter/material.dart';

import 'runtime_config.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Porte de démarrage : intercale forced-update / maintenance / kill switch
/// AVANT toute UI applicative. Non bloquante par défaut (fail-open) tant que le
/// serveur ne demande rien.
///
/// [systemEvents] (optionnel) : flux d'évènements temps réel ; si un évènement de
/// topic "system" arrive, la config est rafraîchie immédiatement (kill switch /
/// maintenance instantanés). Les apps sans canal realtime passent `null`.
class AppGate extends StatefulWidget {
  const AppGate({super.key, required this.child, this.systemEvents});

  final Widget child;
  final Stream<Map<String, dynamic>>? systemEvents;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> with WidgetsBindingObserver {
  StreamSubscription<Map<String, dynamic>>? _sysSub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Cache d'abord (fail-closed), puis réseau.
    RuntimeConfigService.instance
        .loadCached()
        .then((_) => RuntimeConfigService.instance.refresh());

    _sysSub = widget.systemEvents?.listen((event) {
      if ((event['topic'] ?? '').toString() == 'system') {
        RuntimeConfigService.instance.refresh();
      }
    });

    // Filet de sécurité si le WebSocket est absent/coupé.
    _poll = Timer.periodic(
      const Duration(minutes: 15),
      (_) => RuntimeConfigService.instance.refresh(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RuntimeConfigService.instance.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sysSub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'fr';
    return ValueListenableBuilder<RuntimeConfig?>(
      valueListenable: RuntimeConfigService.instance.config,
      builder: (context, cfg, _) {
        if (cfg == null || !cfg.isBlocking) return widget.child;
        if (cfg.killSwitch) {
          return _GateScreen(
            icon: LucideIcons.lock,
            title: lang == 'en' ? 'Service unavailable' : 'Service indisponible',
            message: lang == 'en'
                ? 'This application has been temporarily disabled. Please try again later.'
                : "Cette application a été temporairement désactivée. Réessayez plus tard.",
          );
        }
        if (cfg.maintenance) {
          return _GateScreen(
            icon: LucideIcons.wrench,
            title: lang == 'en' ? 'Maintenance' : 'Maintenance',
            message: cfg.localizedMaintenanceMessage(lang).isNotEmpty
                ? cfg.localizedMaintenanceMessage(lang)
                : (lang == 'en'
                    ? 'Maintenance in progress. Please try again shortly.'
                    : 'Maintenance en cours. Merci de réessayer dans un instant.'),
            onRetry: RuntimeConfigService.instance.refresh,
          );
        }
        // update_required
        return _GateScreen(
          icon: LucideIcons.download,
          title: lang == 'en' ? 'Update required' : 'Mise à jour requise',
          message: cfg.localizedUpdateMessage(lang).isNotEmpty
              ? cfg.localizedUpdateMessage(lang)
              : (lang == 'en'
                  ? 'A new version is required to continue.'
                  : 'Une nouvelle version est nécessaire pour continuer.'),
          downloadUrl: cfg.downloadUrl,
          onRetry: RuntimeConfigService.instance.refresh,
        );
      },
    );
  }
}

class _GateScreen extends StatelessWidget {
  const _GateScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.downloadUrl = '',
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final String downloadUrl;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                if (downloadUrl.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SelectableText(
                    downloadUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ],
                if (onRetry != null) ...[
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: () => onRetry!(),
                    child: const Text('Réessayer'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

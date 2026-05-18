import 'package:flutter/material.dart';

import 'app_i18n.dart';
import 'app_theme.dart';
import 'app_ui.dart';

class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.label = ""});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppSectionCard(
        margin: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              label.isEmpty ? context.tr("state.loading") : label,
              style: const TextStyle(color: AppPalette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    this.onRetry,
    this.retryLabel = "",
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AppSectionCard(
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppPalette.textMuted),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    retryLabel.isEmpty ? context.tr("state.retry") : retryLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = "",
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  static String _sanitize(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'Exception:\s*'), '')
        .replaceAll(RegExp(r'(GET|POST|PUT|PATCH|DELETE)\s+/\S+\s+failed:\s+\d+\s*'), '')
        .replaceAll(RegExp(r'\d{3}\s+(Internal Server Error|Bad Gateway|Service Unavailable|Not Found|Forbidden|Unauthorized)', caseSensitive: false), '')
        .replaceAll(RegExp(r'SocketException.*'), '')
        .replaceAll(RegExp(r'HandshakeException.*'), '')
        .replaceAll(RegExp(r'HttpException.*'), '')
        .trim();

    final lower = cleaned.toLowerCase();
    if (lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('socketexception')) {
      return 'Connexion impossible. Verifiez votre reseau et reessayez.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Le serveur met trop de temps a repondre. Reessayez dans un moment.';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Session expiree. Veuillez vous reconnectez.';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Acces refuse. Vous n\'avez pas les droits pour cette action.';
    }
    if (lower.contains('500') || lower.contains('internal server')) {
      return 'Une erreur s\'est produite de notre cote. Reessayez dans un moment.';
    }
    if (cleaned.isEmpty || cleaned.length > 200) {
      return 'Une erreur s\'est produite. Verifiez votre connexion et reessayez.';
    }
    return cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final displayMessage = _sanitize(message);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: AppSectionCard(
          margin: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_outlined,
                  size: 42, color: AppPalette.danger),
              const SizedBox(height: 12),
              Text(
                title.isEmpty ? context.tr("state.error.title") : title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                displayMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppPalette.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr("state.retry")),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

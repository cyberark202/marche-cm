import 'package:flutter/material.dart';

/// Canonical transaction states for all wallet/payment flows.
enum TransactionState {
  idle,
  validating,
  awaitingPin,
  submitting,
  pendingNotchPay,
  pendingMomo,
  processing,
  success,
  failed,
  timedOut,
}

extension TransactionStateX on TransactionState {
  bool get isTerminal =>
      this == TransactionState.success ||
      this == TransactionState.failed ||
      this == TransactionState.timedOut;

  bool get isBusy =>
      this == TransactionState.validating ||
      this == TransactionState.awaitingPin ||
      this == TransactionState.submitting ||
      this == TransactionState.processing;

  bool get isPending =>
      this == TransactionState.pendingNotchPay ||
      this == TransactionState.pendingMomo;

  String get label {
    switch (this) {
      case TransactionState.idle:
        return '';
      case TransactionState.validating:
        return 'Vérification...';
      case TransactionState.awaitingPin:
        return 'Saisie du PIN...';
      case TransactionState.submitting:
        return 'Envoi...';
      case TransactionState.pendingNotchPay:
        return 'En attente NotchPay';
      case TransactionState.pendingMomo:
        return 'En attente Mobile Money';
      case TransactionState.processing:
        return 'Traitement...';
      case TransactionState.success:
        return 'Succès';
      case TransactionState.failed:
        return 'Échec';
      case TransactionState.timedOut:
        return 'Délai dépassé';
    }
  }
}

// ── AppTransactionBanner ──────────────────────────────────────────────────────

/// Full-width status banner for wallet/payment screens.
class AppTransactionBanner extends StatelessWidget {
  const AppTransactionBanner({
    super.key,
    required this.state,
    this.message,
  });

  final TransactionState state;
  final String? message;

  @override
  Widget build(BuildContext context) {
    if (state == TransactionState.idle) return const SizedBox.shrink();

    final (color, icon) = switch (state) {
      TransactionState.success => (Colors.green.shade700, Icons.check_circle),
      TransactionState.failed => (Colors.red.shade700, Icons.error),
      TransactionState.timedOut =>
        (Colors.orange.shade700, Icons.timer_off_rounded),
      TransactionState.pendingNotchPay ||
      TransactionState.pendingMomo =>
        (Colors.blue.shade700, Icons.hourglass_top_rounded),
      _ => (Colors.blueGrey.shade700, Icons.sync_rounded),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: color,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? state.label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── AppPendingIndicator ───────────────────────────────────────────────────────

/// Compact inline spinner + label for pending states.
class AppPendingIndicator extends StatelessWidget {
  const AppPendingIndicator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

// ── AppSyncStateBadge ─────────────────────────────────────────────────────────

/// Small pill badge showing sync freshness (fresh / syncing / stale / offline).
enum SyncState { fresh, syncing, stale, offline }

class AppSyncStateBadge extends StatelessWidget {
  const AppSyncStateBadge({super.key, required this.state});

  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      SyncState.fresh => ('Actualisé', Colors.green),
      SyncState.syncing => ('Sync...', Colors.blue),
      SyncState.stale => ('Cache', Colors.orange),
      SyncState.offline => ('Hors ligne', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color.shade700,
        ),
      ),
    );
  }
}

// ── AppLoadingButton ──────────────────────────────────────────────────────────

/// FilledButton that shows a spinner when [loading] is true.
/// Drop-in replacement for financial action buttons.
class AppLoadingButton extends StatelessWidget {
  const AppLoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.style,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingLabel;
  final ButtonStyle? style;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(loadingLabel ?? label),
            ],
          )
        : Text(label);

    return SizedBox(
      width: double.infinity,
      child: tonal
          ? FilledButton.tonal(
              onPressed: loading ? null : onPressed,
              style: style,
              child: child,
            )
          : FilledButton(
              onPressed: loading ? null : onPressed,
              style: style,
              child: child,
            ),
    );
  }
}

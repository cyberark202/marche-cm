import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_metrics_service.dart';
import '../auth/session_store.dart';

enum _PollResult { pending, success, failed, timedOut }

/// Bottom sheet shown after NotchPay checkout URL is launched.
///
/// Polls /api/wallets/transactions/ every 5s for up to 120s looking for
/// a non-PENDING transaction created after [initiatedAt].
/// Uses AppLifecycleListener to probe immediately when the user returns
/// from the payment app (foreground resume).
///
/// Usage:
///   final result = await NotchPayPendingSheet.show(
///     context: context,
///     token: token,
///     provider: _provider,
///     initiatedAt: DateTime.now(),
///   );
///   if (result == true) { /* success */ }
class NotchPayPendingSheet extends StatefulWidget {
  const NotchPayPendingSheet({
    super.key,
    required this.token,
    required this.provider,
    required this.initiatedAt,
    this.transactionId = '',
  });

  final String? token;
  final String provider;
  final DateTime initiatedAt;
  /// ID externe de la transaction (external_transaction_id) retourné par
  /// l'API au moment du topup. Quand fourni, le polling utilise l'endpoint
  /// ciblé /api/wallets/transactions/{id}/status/ au lieu de scanner toute
  /// la liste — évite les faux positifs si une autre transaction se termine
  /// pendant l'attente.
  final String transactionId;

  static Future<bool?> show({
    required BuildContext context,
    required String? token,
    required String provider,
    required DateTime initiatedAt,
    String transactionId = '',
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => NotchPayPendingSheet(
        token: token,
        provider: provider,
        initiatedAt: initiatedAt,
        transactionId: transactionId,
      ),
    );
  }

  @override
  State<NotchPayPendingSheet> createState() => _NotchPayPendingSheetState();
}

class _NotchPayPendingSheetState extends State<NotchPayPendingSheet> {
  static const Duration _pollInterval = Duration(seconds: 5);
  static const Duration _maxWait = Duration(seconds: 120);

  final ApiService _api = ApiService();
  Timer? _pollTimer;
  late final AppLifecycleListener _lifecycleListener;
  late final DateTime _deadline;

  _PollResult _state = _PollResult.pending;
  int _elapsed = 0; // seconds
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(_maxWait);

    _lifecycleListener = AppLifecycleListener(
      onResume: _onAppResume,
    );

    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      _elapsed += _pollInterval.inSeconds;
      if (DateTime.now().isAfter(_deadline)) {
        _setResult(_PollResult.timedOut);
        return;
      }
      await _probe();
    });
    // Immediate first probe
    _probe();
  }

  void _onAppResume() {
    // User came back from NotchPay — probe right away
    if (_state == _PollResult.pending) _probe();
  }

  Future<void> _probe() async {
    if (_polling || _state != _PollResult.pending) return;
    _polling = true;
    try {
      final token = widget.token ??
          (mounted ? context.read<SessionStore>().token : null);

      if (widget.transactionId.isNotEmpty) {
        // Endpoint ciblé: évite de télécharger toute la liste et empêche
        // qu'une transaction concurrente (retrait, etc.) déclenche un faux
        // positif de confirmation.
        final tx = await _api.getObject(
          '/api/wallets/transactions/${widget.transactionId}/status/',
          token: token,
        );
        final s = (tx['status'] ?? '').toString().toUpperCase();
        if (s == 'SUCCESS') {
          _setResult(_PollResult.success);
        } else if (s == 'FAILED' || s == 'CANCELLED' || s == 'EXPIRED') {
          _setResult(_PollResult.failed);
        }
      } else {
        // Fallback: scan de la liste si transactionId non disponible.
        final txList = await _api.getList(
          '/api/wallets/transactions/',
          token: token,
        );
        final result = _checkTransactions(txList);
        if (result != _PollResult.pending) _setResult(result);
      }
    } catch (_) {
      // Erreur réseau pendant le polling — on continue d'attendre.
    } finally {
      _polling = false;
    }
  }

  _PollResult _checkTransactions(List<Map<String, dynamic>> txList) {
    for (final tx in txList) {
      final createdRaw = tx['created_at'] ?? tx['timestamp'] ?? '';
      DateTime? created;
      try {
        created = DateTime.parse(createdRaw.toString());
      } catch (_) {}
      if (created == null || created.isBefore(widget.initiatedAt)) continue;

      final status = (tx['status'] ?? '').toString().toUpperCase();
      if (status == 'SUCCESS' || status == 'COMPLETED' || status == 'PAID') {
        return _PollResult.success;
      }
      if (status == 'FAILED' || status == 'CANCELLED' || status == 'EXPIRED') {
        return _PollResult.failed;
      }
    }
    return _PollResult.pending;
  }

  void _setResult(_PollResult result) {
    if (!mounted || _state != _PollResult.pending) return;
    _pollTimer?.cancel();
    setState(() => _state = result);

    final provider = widget.provider;
    if (result == _PollResult.success) {
      AppMetricsService.instance.recordPaymentSuccess(
        provider,
        DateTime.now().difference(widget.initiatedAt).inMilliseconds,
      );
    } else if (result == _PollResult.failed) {
      AppMetricsService.instance.recordPaymentFailed(provider);
    } else if (result == _PollResult.timedOut) {
      AppMetricsService.instance.recordPaymentTimedOut(provider);
    }

    // Auto-close after short delay on terminal states
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop(result == _PollResult.success);
    });
  }

  void _cancelManually() {
    _pollTimer?.cancel();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case _PollResult.pending:
        return _PendingBody(
          provider: widget.provider,
          elapsed: _elapsed,
          maxSeconds: _maxWait.inSeconds,
          onCancel: _cancelManually,
        );
      case _PollResult.success:
        return const _ResultBody(
          icon: Icons.check_circle_rounded,
          color: Colors.green,
          title: 'Paiement confirmé',
          subtitle: 'Votre wallet a été rechargé avec succès.',
        );
      case _PollResult.failed:
        return const _ResultBody(
          icon: Icons.cancel_rounded,
          color: Colors.red,
          title: 'Paiement échoué',
          subtitle: 'La transaction a été refusée ou annulée.',
        );
      case _PollResult.timedOut:
        return const _ResultBody(
          icon: Icons.timer_off_rounded,
          color: Colors.orange,
          title: 'Délai dépassé',
          subtitle:
              'Aucune confirmation reçue. Vérifiez votre solde dans quelques minutes.',
        );
    }
  }
}

class _PendingBody extends StatelessWidget {
  const _PendingBody({
    required this.provider,
    required this.elapsed,
    required this.maxSeconds,
    required this.onCancel,
  });

  final String provider;
  final int elapsed;
  final int maxSeconds;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = (elapsed / maxSeconds).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(height: 20),
        Text(
          'Paiement $provider en cours',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Finalisez le paiement dans l\'application.\n'
          'Cette page se met à jour automatiquement.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 20),
        LinearProgressIndicator(value: progress, minHeight: 4),
        const SizedBox(height: 6),
        Text(
          'Attente: ${elapsed}s / ${maxSeconds}s',
          style: const TextStyle(fontSize: 11, color: Colors.black38),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: onCancel,
          child: const Text('Annuler et vérifier plus tard'),
        ),
      ],
    );
  }
}

class _ResultBody extends StatelessWidget {
  const _ResultBody({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 64),
        const SizedBox(height: 16),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

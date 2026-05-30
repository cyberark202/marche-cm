import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import '../../core/ui_kit.dart';
import '../auth/auth_api_service.dart';
import '../data/admin_repository.dart';

/// Screen 39 — Wallet reconciliation (NotchPay vs system) + step-up reconcile.
class ReconciliationPage extends StatefulWidget {
  const ReconciliationPage({super.key});

  @override
  State<ReconciliationPage> createState() => _ReconciliationPageState();
}

class _ReconciliationPageState extends State<ReconciliationPage> {
  final _repo = AdminRepository.instance;
  final _auth = AuthApiService();
  late Future<_EscrowSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_EscrowSummary> _load() async {
    final holds = await _repo.escrowHolds();
    num held = 0;
    int active = 0;
    for (final h in holds) {
      final state = '${h['state']}';
      if (state == 'HELD' || state == 'FROZEN' || state == 'PARTIAL') {
        held += Fmt.amount(h['remaining_amount'] ?? h['amount'] ?? 0);
        active++;
      }
    }
    return _EscrowSummary(totalHeld: held, activeHolds: active, count: holds.length);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_EscrowSummary>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const AppLoadingState(label: 'Chargement du wallet…');
            }
            if (snap.hasError) {
              return AppErrorState(
                message: _repo.errorMessage(snap.error!),
                onRetry: _refresh,
              );
            }
            final s = snap.data!;
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Text('Réconciliation wallet',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Text('NotchPay vs système',
                      style: TextStyle(color: AppPalette.textMuted)),
                  const SizedBox(height: 14),
                  HeroPanel(
                    gradient: AppPalette.gradientOcean,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SOLDE PLATEFORME ESCROW',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 8),
                        Text(Fmt.fcfa(s.totalHeld),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('${s.activeHolds} séquestres actifs',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionLabel('Transactions à rapprocher'),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Les transactions PENDING bloquées (recharge non confirmée, '
                          'payout en échec, webhook orphelin) se rapprochent manuellement '
                          'par leur identifiant externe NotchPay.',
                          style:
                              TextStyle(color: AppPalette.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _startReconcile,
                            icon: const Icon(Icons.sync),
                            label: const Text('Rapprocher une transaction'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Row(
                      children: const [
                        Icon(Icons.shield_outlined,
                            color: AppPalette.secondary, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Le rapprochement crédite/débite des wallets réels : '
                            'une vérification 2FA par e-mail est exigée à chaque opération.',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Step-up reconciliation flow ────────────────────────────────────────────

  Future<void> _startReconcile() async {
    final input = await _askTransaction();
    if (input == null) return;

    // 1. Request the 2FA challenge (server e-mails a 6-digit code).
    String challengeToken;
    try {
      challengeToken = await _auth.requestSensitiveAction('wallet.reconcile');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
      return;
    }
    if (!mounted) return;

    // 2. Ask for the emailed verification code.
    final code = await _askCode();
    if (code == null || code.isEmpty) return;

    // 3. Submit reconciliation.
    try {
      await _repo.reconcile(
        transactionId: input.transactionId,
        status: input.targetStatus,
        challengeToken: challengeToken,
        verificationCode: code,
      );
      if (!mounted) return;
      showSnack(context, 'Transaction rapprochée (${input.targetStatus}).');
      _refresh();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
    }
  }

  Future<_ReconcileInput?> _askTransaction() async {
    final txController = TextEditingController();
    String target = 'SUCCESS';
    return showDialog<_ReconcileInput>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Rapprocher une transaction'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: txController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'ID transaction externe',
                  hintText: 'ex : NCH-48A2…',
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'SUCCESS', label: Text('Succès')),
                  ButtonSegment(value: 'FAILED', label: Text('Échec')),
                ],
                selected: {target},
                onSelectionChanged: (s) => setLocal(() => target = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final id = txController.text.trim();
                if (id.isEmpty) return;
                Navigator.pop(
                    ctx, _ReconcileInput(transactionId: id, targetStatus: target));
              },
              child: const Text('Continuer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askCode() async {
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
              'Saisissez-le pour confirmer le rapprochement.',
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
}

class _EscrowSummary {
  _EscrowSummary({
    required this.totalHeld,
    required this.activeHolds,
    required this.count,
  });
  final num totalHeld;
  final int activeHolds;
  final int count;
}

class _ReconcileInput {
  _ReconcileInput({required this.transactionId, required this.targetStatus});
  final String transactionId;
  final String targetStatus;
}

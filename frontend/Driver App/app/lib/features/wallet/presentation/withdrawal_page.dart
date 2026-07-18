import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';
import 'wallet_security_dialogs.dart';
import 'package:lucide_icons/lucide_icons.dart';

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({super.key});

  @override
  State<WithdrawalPage> createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  final _amountCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  // Provider codes must match the backend PaymentProvider choices
  // (apps/wallets/models.py): MTN MoMo maps to "MOBILE_MONEY".
  String _provider = 'MOBILE_MONEY';
  bool _busy = false;
  String? _error;

  static const _providers = [
    ('MOBILE_MONEY', 'MTN Mobile Money', Color(0xFFFFCC00)),
    ('ORANGE_MONEY', 'Orange Money', Color(0xFFFF6600)),
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _withdraw() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 500) {
      setState(() => _error = 'Montant minimum : 500 FCFA.');
      return;
    }
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      setState(() => _error = 'Numéro de téléphone invalide.');
      return;
    }

    // Withdrawals are protected by a one-time email challenge (the wallet PIN
    // was removed product-wide). Collect the code before posting.
    final verification = await collectSensitiveActionCode(
      context,
      actionKey: 'wallet.withdraw',
      actionLabel: 'Retrait wallet',
    );
    if (!mounted || verification == null) return;

    setState(() { _busy = true; _error = null; });
    try {
      // Audit ref: [Front-Driver] backend exposes WalletViewSet.withdraw at
      // /api/wallets/withdraw/ (wallets/views.py:751). Destination is read from
      // `destination_account`/`destination_phone`; the challenge pair is
      // mandatory.
      await DriverDioClient.dio.post('/api/wallets/withdraw/', data: {
        'amount': amount,
        'provider': _provider,
        'destination_phone': phone,
        'destination_account': phone,
        'challenge_token': verification.challengeToken,
        'verification_code': verification.verificationCode,
        'idempotency_key': DateTime.now().microsecondsSinceEpoch.toString(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande de retrait envoyée !')),
      );
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = ApiError.friendly(e));
    } finally {
      // Toujours relâcher le spinner (succès = navigation ; échec = ré-essai).
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Retrait'),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(LucideIcons.alertCircle, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13))),
                ]),
              ),
              const SizedBox(height: 16),
            ],

            const _Label('Opérateur Mobile Money'),
            const SizedBox(height: 8),
            ..._providers.map((p) {
              final sel = _provider == p.$1;
              return GestureDetector(
                onTap: () => setState(() => _provider = p.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: sel ? p.$3.withValues(alpha: 0.08) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: sel ? p.$3 : DriverPalette.border,
                        width: sel ? 2 : 1),
                  ),
                  child: Row(children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: p.$3, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(LucideIcons.smartphone, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(p.$2, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14,
                        color: sel ? DriverPalette.textPrimary : DriverPalette.textSecondary)),
                    const Spacer(),
                    if (sel) const Icon(LucideIcons.checkCircle2, color: DriverPalette.primary, size: 20),
                  ]),
                ),
              );
            }),

            const SizedBox(height: 16),
            const _Label('Numéro de téléphone'),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.phone),
                hintText: '+2376XXXXXXXX',
              ),
            ),
            const SizedBox(height: 16),

            const _Label('Montant (FCFA)'),
            const SizedBox(height: 8),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _withdraw(),
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.banknote),
                hintText: 'Minimum 500 FCFA',
                suffixText: 'FCFA',
              ),
            ),
            const SizedBox(height: 8),
            const Text('Les retraits sont traités sous 24h ouvrables.',
                style: TextStyle(fontSize: 12, color: DriverPalette.textMuted)),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _withdraw,
                child: _busy
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Text('Demander le retrait',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: DriverPalette.textMuted, letterSpacing: 0.5));
}

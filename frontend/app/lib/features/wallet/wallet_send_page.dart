import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/action_mutex.dart';
import '../../core/api_service.dart';
import '../../core/app_ui.dart';
import '../../core/backend_ui_config_service.dart';
import '../auth/session_store.dart';
import '../onboarding/escrow_onboarding_page.dart';
import 'notchpay_pending_sheet.dart';

class WalletTopupPage extends StatefulWidget {
  const WalletTopupPage({super.key});

  @override
  State<WalletTopupPage> createState() => _WalletTopupPageState();
}

class _WalletTopupPageState extends State<WalletTopupPage> {
  final ApiService _api = ApiService();
  final _mutex = ActionMutex();
  final _sourcePhone = TextEditingController();
  final _amount = TextEditingController();
  final _pin = TextEditingController();
  String _provider = '';
  List<Map<String, String>> _providerChoices = const [];
  Map<String, String> _providerLogo = const {};
  bool _busy = false;

  static String _generateIdempotencyKey() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
  }

  @override
  void dispose() {
    _sourcePhone.dispose();
    _amount.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      final providers = BackendUiConfigService.instance
          .readChoiceList(config, ['choices', 'wallet_payment_providers']);
      final logos = BackendUiConfigService.instance
          .readStringMap(config, ['choices', 'wallet_provider_logo_url']);
      if (!mounted) return;
      setState(() {
        _providerChoices = providers;
        _providerLogo = logos;
        _provider = providers.isEmpty ? '' : providers.first['value']!;
      });
    } catch (e) {
      debugPrint('[WalletTopupPage] _loadUiConfig error: $e');
    }
  }

  bool _isPhoneProvider(String provider) =>
      provider == 'MOBILE_MONEY' || provider == 'ORANGE_MONEY';

  bool _isCardProvider(String provider) =>
      provider == 'VISA' || provider == 'MASTERCARD';

  bool _isPaypalProvider(String provider) => provider == 'PAYPAL';

  String _accountLabel() {
    if (_isPhoneProvider(_provider)) return 'Numero a debiter';
    if (_isCardProvider(_provider)) return 'Reference carte a debiter';
    if (_isPaypalProvider(_provider)) return 'Email PayPal a debiter';
    return 'Identifiant compte a debiter';
  }

  String _accountHint() {
    if (_isPhoneProvider(_provider)) return 'Ex: +2376XXXXXXXX';
    if (_isCardProvider(_provider)) return 'Entrez 12 a 19 chiffres';
    if (_isPaypalProvider(_provider)) return 'Ex: client@paypal.com';
    return '';
  }

  String _accountSummaryLabel() {
    if (_isPhoneProvider(_provider)) return 'Numero debite';
    if (_isCardProvider(_provider)) return 'Carte debitee';
    if (_isPaypalProvider(_provider)) return 'Compte PayPal debite';
    return 'Compte debite';
  }

  TextInputType _accountKeyboardType() {
    if (_isPhoneProvider(_provider)) return TextInputType.phone;
    if (_isCardProvider(_provider)) return TextInputType.number;
    if (_isPaypalProvider(_provider)) return TextInputType.emailAddress;
    return TextInputType.text;
  }

  String _normalizeAccountValue(String raw) {
    final value = raw.trim();
    if (_isCardProvider(_provider)) {
      return value.replaceAll(RegExp(r'\D'), '');
    }
    if (_isPaypalProvider(_provider)) {
      return value.toLowerCase();
    }
    return value;
  }

  String? _validateAccountValue(String raw) {
    final normalized = _normalizeAccountValue(raw);
    if (normalized.isEmpty) return 'Ce champ est obligatoire.';
    if (_isPhoneProvider(_provider)) {
      final ok = RegExp(r'^\+\d{8,}$').hasMatch(normalized);
      if (!ok) {
        return 'Numero invalide. Exemple attendu: +2376XXXXXXXX.';
      }
    } else if (_isCardProvider(_provider)) {
      if (normalized.length < 12 || normalized.length > 19) {
        return 'Reference carte invalide (12 a 19 chiffres).';
      }
    } else if (_isPaypalProvider(_provider)) {
      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized);
      if (!ok) {
        return 'Email PayPal invalide.';
      }
    }
    return null;
  }

  Future<void> _launchTransferCode(String code) async {
    final normalized = code.trim();
    final uri = normalized.startsWith('http')
        ? Uri.parse(normalized)
        : Uri(scheme: 'tel', path: normalized);
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Impossible d'ouvrir l'app telephone.")),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir l'app telephone.")),
      );
    }
  }

  Future<void> _topup() async {
    if (_busy) return;
    if (_provider.isEmpty) return;
    final sourceValue = _normalizeAccountValue(_sourcePhone.text);
    final accountError = _validateAccountValue(_sourcePhone.text);
    if (accountError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accountError)),
      );
      return;
    }
    final amountValue = double.tryParse(_amount.text.trim()) ?? 0;
    if (amountValue < 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Montant minimum: 100 FCFA.')),
      );
      return;
    }
    await showEscrowOnboardingIfNeeded(context);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirmer la recharge"),
        content: Text(
          "Canal: $_provider\n${_accountSummaryLabel()}: $sourceValue\nMontant: ${_amount.text.trim()} FCFA",
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
    if (!mounted) return;
    if (confirm != true) return;
    final token = context.read<SessionStore>().token;
    final pin = await _collectPin();
    if (!mounted || pin == null) return;

    setState(() => _busy = true);
    final idempotencyKey = _generateIdempotencyKey();
    try {
      final result = await _api.post(
        '/api/wallets/topup/',
        {
          'source_phone': sourceValue,
          'source_account': sourceValue,
          'amount': amountValue,
          'provider': _provider,
          'pin': pin,
          'idempotency_key': idempotencyKey,
        },
        token: token,
      );
      if (!mounted) return;
      final checkoutUrl = (result['checkout_url'] ?? '').toString();
      final txId = (result['transaction_id'] ?? '').toString();
      final paymentMode = (result['payment_mode'] ?? '').toString();
      final status = (result['status'] ?? '').toString().toUpperCase();
      final initiatedAt = DateTime.now();

      // In-app Direct Charge (mobile money): NotchPay a poussé une demande de
      // validation USSD sur le téléphone — pas de navigateur externe. On ouvre
      // directement la feuille de suivi qui sonde le statut.
      if (paymentMode == 'direct_charge' ||
          (checkoutUrl.isEmpty && status == 'PENDING')) {
        final paid = await NotchPayPendingSheet.show(
          context: context,
          token: token,
          provider: _provider,
          initiatedAt: initiatedAt,
          transactionId: txId,
        );
        if (!mounted) return;
        if (paid == true) Navigator.of(context).pop(true);
      } else if (checkoutUrl.isNotEmpty) {
        // Flux hébergé (carte / PayPal) : redirection navigateur puis suivi.
        await _launchTransferCode(checkoutUrl);
        if (!mounted) return;
        final paid = await NotchPayPendingSheet.show(
          context: context,
          token: token,
          provider: _provider,
          initiatedAt: initiatedAt,
          transactionId: txId,
        );
        if (!mounted) return;
        if (paid == true) Navigator.of(context).pop(true);
        // paid == false/null: timeout or cancel — stay on page so user can retry
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Recharge effectuee.')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_api.toUserMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _collectPin() async {
    _pin.clear();
    String? pinError;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Entrez votre PIN wallet"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _pin,
                keyboardType: TextInputType.number,
                maxLength: 4,
                obscureText: true,
                autofocus: true,
                onChanged: (_) => setDialogState(() => pinError = null),
                decoration: InputDecoration(
                  labelText: "Code PIN (4 chiffres)",
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: pinError,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () {
                final pin = _pin.text.trim();
                if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
                  setDialogState(() => pinError = "PIN invalide — 4 chiffres requis");
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text("Valider"),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return _pin.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final username = context.watch<SessionStore>().username ?? 'Utilisateur';
    return Scaffold(
      appBar: AppBar(title: const Text("Recharger le wallet")),
      body: AppPageBackground(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AppHeaderPanel(
              title: 'Recharge pour $username',
              subtitle:
                  'Indiquez le compte source a debiter puis le montant a recharger.',
            ),
            AppSectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProviderPreview(
                      provider: _provider, url: _providerLogo[_provider]),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _provider.isEmpty ? null : _provider,
                    items: _providerChoices
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item['value'],
                            child: Text(item['label'] ?? item['value']!),
                          ),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _provider = v ?? _provider),
                    decoration:
                        const InputDecoration(labelText: 'Moyen de paiement'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _sourcePhone,
                    keyboardType: _accountKeyboardType(),
                    decoration: InputDecoration(
                      labelText: _accountLabel(),
                      hintText: _accountHint().isEmpty ? null : _accountHint(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amount,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Montant a recharger'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _mutex.run(_topup),
                      child: Text(_busy ? 'Rechargement...' : 'Recharger'),
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

class _ProviderPreview extends StatelessWidget {
  const _ProviderPreview({required this.provider, this.url});
  final String provider;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final logoUrl = url ?? '';
    return Row(
      children: [
        if (logoUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: logoUrl.startsWith('asset:')
                ? Image.asset(
                    logoUrl.replaceFirst('asset:', ''),
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                  )
                : CachedNetworkImage(
                    imageUrl: logoUrl,
                    width: 30,
                    height: 30,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => const Center(
                      child: SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Icon(Icons.credit_card),
                  ),
          )
        else
          const Icon(Icons.credit_card),
        const SizedBox(width: 8),
        Text('Canal: $provider',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

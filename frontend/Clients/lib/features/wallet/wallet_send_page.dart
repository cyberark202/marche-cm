import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
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
  final _sourceAccount = TextEditingController();
  final _amount = TextEditingController();
  final _pin = TextEditingController();
  String _provider = '';
  List<Map<String, String>> _providerChoices = const [];
  Map<String, String> _providerLogo = const {};
  bool _busy = false;

  static const double _feeRate = 0.01;
  static const List<int> _presets = [25000, 50000, 100000];

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _sourceAccount.dispose();
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
    } catch (_) {}
  }

  bool _isPhoneProvider(String provider) =>
      provider == 'MOBILE_MONEY' || provider == 'ORANGE_MONEY';
  bool _isCardProvider(String provider) =>
      provider == 'VISA' || provider == 'MASTERCARD';
  bool _isPaypalProvider(String provider) => provider == 'PAYPAL';

  IconData _providerIcon(String code) {
    switch (code) {
      case 'MOBILE_MONEY':
        return Icons.phone_iphone;
      case 'ORANGE_MONEY':
        return Icons.phone_android;
      case 'VISA':
      case 'MASTERCARD':
        return Icons.credit_card;
      case 'PAYPAL':
        return Icons.account_balance_wallet_outlined;
      default:
        return Icons.payments_outlined;
    }
  }

  Color _providerAccent(String code) {
    switch (code) {
      case 'MOBILE_MONEY':
        return const Color(0xFFFFB020);
      case 'ORANGE_MONEY':
        return const Color(0xFFFF7A45);
      case 'VISA':
        return const Color(0xFF1A1F71);
      case 'MASTERCARD':
        return const Color(0xFFEB001B);
      case 'PAYPAL':
        return const Color(0xFF003087);
      default:
        return AppPalette.primary;
    }
  }

  String _accountLabel() {
    if (_isPhoneProvider(_provider)) return 'Numéro Mobile Money';
    if (_isCardProvider(_provider)) return 'Référence carte';
    if (_isPaypalProvider(_provider)) return 'Email PayPal';
    return 'Identifiant compte';
  }

  String _accountHint() {
    if (_isPhoneProvider(_provider)) return '+237 6XX XX XX XX';
    if (_isCardProvider(_provider)) return '12 à 19 chiffres';
    if (_isPaypalProvider(_provider)) return 'votre.email@paypal.com';
    return '';
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
    if (_isPaypalProvider(_provider)) return value.toLowerCase();
    return value;
  }

  String? _validateAccountValue(String raw) {
    final normalized = _normalizeAccountValue(raw);
    if (normalized.isEmpty) return 'Ce champ est obligatoire.';
    if (_isPhoneProvider(_provider)) {
      final ok = RegExp(r'^\+\d{8,}$').hasMatch(normalized);
      if (!ok) return 'Numéro invalide. Exemple : +2376XXXXXXXX.';
    } else if (_isCardProvider(_provider)) {
      if (normalized.length < 12 || normalized.length > 19) {
        return 'Référence carte invalide (12 à 19 chiffres).';
      }
    } else if (_isPaypalProvider(_provider)) {
      final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(normalized);
      if (!ok) return 'Email PayPal invalide.';
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
          const SnackBar(content: Text("Impossible d'ouvrir l'app.")),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Impossible d'ouvrir l'app.")),
      );
    }
  }

  Future<void> _topup() async {
    if (_busy) return;
    if (_provider.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Choisissez un moyen de paiement.")),
      );
      return;
    }
    final sourceValue = _normalizeAccountValue(_sourceAccount.text);
    final accountError = _validateAccountValue(_sourceAccount.text);
    if (accountError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(accountError)),
      );
      return;
    }
    final amountValue = double.tryParse(_amount.text.trim()) ?? 0;
    if (amountValue < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Montant minimum : 500 FCFA.")),
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
          "Canal : $_provider\n"
          "Compte : $sourceValue\n"
          "Montant : ${amountValue.toStringAsFixed(0)} FCFA\n"
          "Frais NotchPay : ${(amountValue * _feeRate).toStringAsFixed(0)} FCFA",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Confirmer")),
        ],
      ),
    );
    if (!mounted || confirm != true) return;

    final token = context.read<SessionStore>().token;
    final pin = await _collectPin();
    if (!mounted || pin == null) return;

    setState(() => _busy = true);
    try {
      final result = await _api.post(
        '/api/wallets/topup/',
        {
          'source_phone': sourceValue,
          'source_account': sourceValue,
          'amount': amountValue,
          'provider': _provider,
          'pin': pin,
          'idempotency_key': DateTime.now().microsecondsSinceEpoch.toString(),
        },
        token: token,
      );
      if (!mounted) return;
      final checkoutUrl = (result['checkout_url'] ?? '').toString();
      final txId = (result['transaction_id'] ?? '').toString();
      final paymentMode = (result['payment_mode'] ?? '').toString();
      final status = (result['status'] ?? '').toString().toUpperCase();
      final initiatedAt = DateTime.now();

      // Paiement in-app (Direct Charge mobile money) : NotchPay pousse une
      // demande de validation USSD sur le téléphone, aucun navigateur ouvert.
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
        return;
      } else if (checkoutUrl.isNotEmpty) {
        // Flux hébergé (carte / PayPal) : redirection puis suivi.
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
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Recharge effectuée.")));
      }
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
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
          title: const Text("Code PIN wallet"),
          content: TextField(
            controller: _pin,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            autofocus: true,
            onChanged: (_) => setDialogState(() => pinError = null),
            decoration: InputDecoration(
              labelText: "PIN (4 chiffres)",
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: pinError,
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler")),
            FilledButton(
                onPressed: () {
                  final pin = _pin.text.trim();
                  if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
                    setDialogState(() =>
                        pinError = "PIN invalide — 4 chiffres requis.");
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text("Valider")),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return _pin.text.trim();
  }

  @override
  Widget build(BuildContext context) {
    final amountValue = double.tryParse(_amount.text.trim()) ?? 0;
    final fees = amountValue * _feeRate;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _TopupHeader(onClose: () => Navigator.maybePop(context)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  const _SectionLabel(label: "MÉTHODE"),
                  const SizedBox(height: 10),
                  if (_providerChoices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppPalette.card,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        border: Border.all(color: AppPalette.borderSoft),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text("Chargement des moyens de paiement..."),
                        ],
                      ),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _providerChoices.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.85,
                      ),
                      itemBuilder: (_, i) {
                        final c = _providerChoices[i];
                        final code = c['value'] ?? '';
                        final selected = code == _provider;
                        return _ProviderCard(
                          code: code,
                          label: c['label'] ?? code,
                          icon: _providerIcon(code),
                          accent: _providerAccent(code),
                          logoUrl: _providerLogo[code] ?? '',
                          selected: selected,
                          onTap: () => setState(() => _provider = code),
                        );
                      },
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(label: "MONTANT À RECHARGER"),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    decoration: BoxDecoration(
                      color: AppPalette.card,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppPalette.borderSoft),
                      boxShadow: AppPalette.shadowSoft,
                    ),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amount,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: AppPalette.primaryDark,
                                  letterSpacing: -1.0,
                                ),
                                decoration: const InputDecoration(
                                  hintText: "0",
                                  hintStyle: TextStyle(
                                    color: AppPalette.textFaint,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 6),
                              child: Text(
                                "FCFA",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppPalette.accentSoft,
                            borderRadius:
                                BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline,
                                  size: 13, color: AppPalette.accentDark),
                              const SizedBox(width: 5),
                              Text(
                                "Frais NotchPay 1 % = ${fees.toStringAsFixed(0)} FCFA",
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppPalette.accentDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final preset in _presets) ...[
                        Expanded(
                          child: _PresetChip(
                            amount: preset,
                            selected: amountValue.round() == preset,
                            onTap: () => _amount.text = preset.toString(),
                          ),
                        ),
                        if (preset != _presets.last)
                          const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(label: _accountLabel().toUpperCase()),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _sourceAccount,
                    keyboardType: _accountKeyboardType(),
                    decoration: InputDecoration(
                      hintText: _accountHint(),
                      prefixIcon: Icon(_providerIcon(_provider),
                          color: _providerAccent(_provider)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppPalette.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 18, color: AppPalette.primaryDark),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Confirmation OTP requise. Un code à 6 chiffres sera envoyé par SMS, puis votre PIN wallet sera demandé.",
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppPalette.primaryDark,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: AppPalette.card,
            boxShadow: AppPalette.shadowFloating,
            border: const Border(
                top: BorderSide(color: AppPalette.borderSoft, width: 1)),
          ),
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _topup,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bolt, size: 18),
              label: Text(
                _busy
                    ? "Initialisation..."
                    : amountValue > 0
                        ? "Recharger ${amountValue.toStringAsFixed(0)} FCFA"
                        : "Recharger",
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopupHeader extends StatelessWidget {
  const _TopupHeader({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Expanded(
                child: Text(
                  "Recharger",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 2),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.28)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.payments_outlined,
                          size: 12, color: Colors.white),
                      SizedBox(width: 5),
                      Text(
                        "Via NotchPay",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: AppPalette.textMuted,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.code,
    required this.label,
    required this.icon,
    required this.accent,
    required this.logoUrl,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String label;
  final IconData icon;
  final Color accent;
  final String logoUrl;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppPalette.primarySoft : AppPalette.card,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: selected ? AppPalette.primary : AppPalette.borderSoft,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: AppPalette.shadowSoft,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: logoUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: logoUrl.startsWith('asset:')
                          ? Image.asset(
                              logoUrl.replaceFirst('asset:', ''),
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(icon, size: 18, color: accent),
                            )
                          : CachedNetworkImage(
                              imageUrl: logoUrl,
                              width: 26,
                              height: 26,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const Center(
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 1.5),
                                ),
                              ),
                              errorWidget: (_, __, ___) =>
                                  Icon(icon, size: 18, color: accent),
                            ),
                    )
                  : Icon(icon, size: 18, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? AppPalette.primaryDark : AppPalette.text,
                  height: 1.2,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  size: 18, color: AppPalette.primary),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = amount >= 1000
        ? "${(amount ~/ 1000)} k"
        : amount.toString();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppPalette.primary : AppPalette.card,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected ? AppPalette.primary : AppPalette.borderSoft,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          "$formatted FCFA",
          style: TextStyle(
            color: selected ? Colors.white : AppPalette.text,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

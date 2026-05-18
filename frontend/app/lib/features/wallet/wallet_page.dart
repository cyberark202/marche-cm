import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../../core/backend_ui_config_service.dart';
import '../../core/transaction_state.dart';
import '../../core/wallet_cache_service.dart';
import '../auth/session_store.dart';
import 'wallet_send_page.dart';
import 'wallet_withdraw_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final ApiService _api = ApiService();
  final _pinController = TextEditingController();

  bool _loading = true;
  String? _error;
  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _transactions = const [];
  List<String> _reconcileStatuses = const [];
  String _defaultReconcileReason = '';
  String _statusFilter = 'ALL';
  String _kindFilter = 'ALL';
  bool _balanceVisible = true;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _loadUiConfig();
    _load();
  }

  Future<void> _loadUiConfig() async {
    try {
      final config = await BackendUiConfigService.instance.load();
      if (!mounted) return;
      setState(() {
        _reconcileStatuses = BackendUiConfigService.instance
            .readStringList(config, ['choices', 'wallet_reconcile_statuses']);
        _defaultReconcileReason = BackendUiConfigService.instance
            .readString(config, ['defaults', 'wallet_reconcile_reason']);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      final results = await Future.wait([
        _api.getList('/api/wallets/', token: token),
        _api.getList('/api/wallets/transactions/', token: token),
      ]);
      final wallet =
          results[0].isEmpty ? const <String, dynamic>{} : results[0].first;
      final transactions = results[1];
      await Future.wait([
        WalletCacheService.instance.saveWallet(wallet),
        WalletCacheService.instance.saveTransactions(transactions),
      ]);
      if (!mounted) return;
      _wallet = wallet;
      _transactions = transactions;
      _error = null;
      _fromCache = false;
    } catch (_) {
      final cachedWallet =
          await WalletCacheService.instance.loadWallet(allowStale: true);
      final cachedTx =
          await WalletCacheService.instance.loadTransactions(allowStale: true);
      if (!mounted) return;
      if (cachedWallet != null || cachedTx != null) {
        _wallet = cachedWallet ?? const <String, dynamic>{};
        _transactions = cachedTx ?? const [];
        _error = null;
        _fromCache = true;
      } else {
        _wallet = const <String, dynamic>{};
        _transactions = const <Map<String, dynamic>>[];
        _error = 'Impossible de charger le wallet.';
        _fromCache = false;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: _loading
          ? const AppSkeletonListView(count: 4)
          : _error != null && _wallet.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          size: 52, color: AppPalette.textFaint),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style:
                              const TextStyle(color: AppPalette.textMuted)),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text('Réessayer')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppPalette.primary,
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      _buildSliverHeader(session),
                      SliverPadding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 20, 16, 120),
                        sliver: SliverList.list(children: [
                          _buildQuickActions(context),
                          const SizedBox(height: 24),
                          _buildTransactions(),
                          if (session.role == UserRole.generalAdmin) ...[
                            const SizedBox(height: 16),
                            _buildAdminSection(),
                          ],
                        ]),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ─── Sliver Header ────────────────────────────────────────────────────────

  Widget _buildSliverHeader(SessionStore session) {
    final balance = (_wallet['balance'] ?? '0').toString();
    final blocked = (_wallet['blocked_balance'] ?? '0').toString();

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppPalette.gradientHero,
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            'Mon Wallet',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          if (_fromCache) ...[
                            const SizedBox(width: 8),
                            const AppSyncStateBadge(state: SyncState.stale),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _balanceVisible = !_balanceVisible),
                      icon: Icon(
                        _balanceVisible
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      tooltip: _balanceVisible
                          ? 'Masquer le solde'
                          : 'Afficher le solde',
                    ),
                    IconButton(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded,
                          color: Colors.white, size: 22),
                      tooltip: 'Actualiser',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Balance card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.22)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solde disponible',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _balanceVisible ? '$balance FCFA' : '••••• FCFA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _BalanceChip(
                            label: 'Sécurisé escrow',
                            value: _balanceVisible
                                ? '$blocked FCFA'
                                : '••••',
                            icon: Icons.lock_outline_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              color: Colors.white.withValues(alpha: 0.55),
                              size: 13),
                          const SizedBox(width: 5),
                          Text(
                            'Fonds sécurisés · Paiements protégés par escrow',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Quick Actions ────────────────────────────────────────────────────────

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppPalette.text,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                icon: Icons.add_circle_outline_rounded,
                label: 'Recharger',
                color: AppPalette.success,
                onTap: () async {
                  final done = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WalletTopupPage()),
                  );
                  if (done == true) _load();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionTile(
                icon: Icons.south_rounded,
                label: 'Retirer',
                color: AppPalette.primary,
                onTap: () async {
                  final done = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const WalletWithdrawPage()),
                  );
                  if (done == true) _load();
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionTile(
                icon: Icons.pin_outlined,
                label: 'PIN wallet',
                color: AppPalette.secondary,
                onTap: _setWalletPin,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─── Transactions ─────────────────────────────────────────────────────────

  Widget _buildTransactions() {
    final filtered = _transactions.where((tx) {
      final status = (tx['status'] ?? '').toString().toUpperCase();
      final kind = (tx['kind'] ?? '').toString().toUpperCase();
      return (_statusFilter == 'ALL' || status == _statusFilter) &&
          (_kindFilter == 'ALL' || kind == _kindFilter);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Transactions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.text,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Text(
              '${filtered.length} opération(s)',
              style: const TextStyle(
                  fontSize: 12.5, color: AppPalette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Filters
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ...['ALL', 'PENDING', 'SUCCESS', 'FAILED'].map(
                (s) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AppFilterChip(
                    label: s == 'ALL'
                        ? 'Tous'
                        : s == 'PENDING'
                            ? 'En attente'
                            : s == 'SUCCESS'
                                ? 'Réussi'
                                : 'Échoué',
                    selected: _statusFilter == s,
                    onTap: () => setState(() => _statusFilter = s),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ...['ALL', 'TOPUP', 'WITHDRAWAL'].map(
                (k) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AppFilterChip(
                    label: k == 'ALL'
                        ? 'Tous types'
                        : k == 'TOPUP'
                            ? 'Rechargements'
                            : 'Retraits',
                    selected: _kindFilter == k,
                    onTap: () => setState(() => _kindFilter = k),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppPalette.borderSoft),
            ),
            child: const Center(
              child: Text(
                'Aucune transaction pour ce filtre.',
                style: TextStyle(color: AppPalette.textMuted, fontSize: 14),
              ),
            ),
          )
        else
          ...filtered.take(30).map(_buildTransactionRow),
      ],
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> tx) {
    final status = (tx['status'] ?? '-').toString().toUpperCase();
    final kind = (tx['kind'] ?? '-').toString().toUpperCase();
    final reference = (tx['reference'] ?? '').toString();
    final amount = (tx['amount'] ?? '0').toString();
    final timeRaw = (tx['created_at'] ?? '').toString();
    final time = _formatDate(timeRaw);

    final Color statusColor;
    final String statusLabel;
    if (status == 'SUCCESS') {
      statusColor = AppPalette.success;
      statusLabel = 'Réussi';
    } else if (status == 'FAILED') {
      statusColor = AppPalette.danger;
      statusLabel = 'Échoué';
    } else {
      statusColor = AppPalette.warning;
      statusLabel = 'En attente';
    }

    final isTopup = kind == 'TOPUP';
    final Color kindColor = isTopup ? AppPalette.success : AppPalette.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppPalette.borderSoft),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kindColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(
              isTopup ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: kindColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTopup ? 'Rechargement' : 'Retrait',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppPalette.text,
                  ),
                ),
                if (reference.isNotEmpty)
                  Text(
                    reference,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppPalette.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (time.isNotEmpty)
                  Text(
                    time,
                    style: const TextStyle(
                        fontSize: 11, color: AppPalette.textFaint),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isTopup ? '+' : '-'} $amount FCFA',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: kindColor,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Admin section ────────────────────────────────────────────────────────

  Widget _buildAdminSection() {
    return AppSectionCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppPalette.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: const Icon(Icons.admin_panel_settings_outlined,
              color: AppPalette.warning, size: 20),
        ),
        title: const Text('Réconciliation transaction'),
        subtitle: const Text('Forcer SUCCESS/FAILED sur une transaction.'),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: _openReconcileDialog,
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  static String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m ${h}h$min';
  }

  Future<void> _setWalletPin() async {
    _pinController.clear();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Configurer PIN wallet'),
        content: TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN (4 chiffres)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final token = context.read<SessionStore>().token;
    try {
      await _api.post('/api/auth/wallet-pin/', {'pin': _pinController.text.trim()},
          token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN wallet configuré.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_api.toUserMessage(e))));
    }
  }

  Future<void> _openReconcileDialog() async {
    if (_reconcileStatuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Aucun statut de réconciliation disponible.')));
      return;
    }
    final txController = TextEditingController();
    final reasonController =
        TextEditingController(text: _defaultReconcileReason);
    String statusValue = _reconcileStatuses.first;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Réconciliation wallet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: txController,
                decoration:
                    const InputDecoration(labelText: 'Transaction ID externe'),
              ),
              DropdownButtonFormField<String>(
                initialValue: statusValue,
                items: _reconcileStatuses
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setDialogState(
                    () => statusValue = v ?? _reconcileStatuses.first),
                decoration: const InputDecoration(labelText: 'Nouveau statut'),
              ),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Raison'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exécuter')),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final token = context.read<SessionStore>().token;
    try {
      await _api.post('/api/wallets/reconcile/', {
        'transaction_id': txController.text.trim(),
        'status': statusValue,
        'reason': reasonController.text.trim(),
      }, token: token);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Réconciliation effectuée.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_api.toUserMessage(e))));
    }
  }
}

// ─── Reusable widgets ─────────────────────────────────────────────────────────

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13),
          const SizedBox(width: 5),
          Text(
            '$label: $value',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.text,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

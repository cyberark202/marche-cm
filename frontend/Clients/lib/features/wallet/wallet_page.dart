import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../../core/backend_ui_config_service.dart';
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
  bool _balanceVisible = true;
  Map<String, dynamic> _wallet = const {};
  List<Map<String, dynamic>> _transactions = const [];
  List<String> _reconcileStatuses = const [];
  String _defaultReconcileReason = "";
  String _statusFilter = "ALL";
  String _kindFilter = "ALL";

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
            .readStringList(config, ["choices", "wallet_reconcile_statuses"]);
        _defaultReconcileReason = BackendUiConfigService.instance
            .readString(config, ["defaults", "wallet_reconcile_reason"]);
      });
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final wallets = await _api.getList("/api/wallets/", token: token);
      final txs = await _api.getList("/api/wallets/transactions/", token: token);
      _wallet = wallets.isEmpty ? const {} : wallets.first;
      _transactions = txs;
    } catch (_) {
      _wallet = const {};
      _transactions = const [];
      _error = "Impossible de charger le wallet. Vérifiez votre connexion.";
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  double get _topupTotal => _transactions
      .where((tx) =>
          (tx["status"] ?? "").toString().toUpperCase() == "SUCCESS" &&
          (tx["kind"] ?? "").toString().toUpperCase() == "TOPUP")
      .fold<double>(0, (s, tx) => s + _asPositive(tx["amount"]));

  double get _withdrawTotal => _transactions
      .where((tx) =>
          (tx["status"] ?? "").toString().toUpperCase() == "SUCCESS" &&
          (tx["kind"] ?? "").toString().toUpperCase() == "WITHDRAWAL")
      .fold<double>(0, (s, tx) => s + _asPositive(tx["amount"]));

  double _asPositive(dynamic raw) =>
      (double.tryParse((raw ?? "0").toString()) ?? 0).abs();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: _loading
          ? const AppSkeletonListView(count: 4)
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_outlined,
                          size: 48, color: Colors.black38),
                      const SizedBox(height: 12),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: _load, child: const Text("Réessayer")),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                          child: _buildHero(session)),
                      SliverToBoxAdapter(
                          child: _buildQuickActions()),
                      SliverToBoxAdapter(
                          child: _buildTransactions()),
                      if (session.role == UserRole.generalAdmin)
                        SliverToBoxAdapter(
                            child: _buildAdminReconcile()),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: 100)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHero(SessionStore session) {
    final balance = (_wallet["balance"] ?? "0").toString();
    final blocked = (_wallet["blocked_balance"] ?? "0").toString();
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF067A55), Color(0xFF0EA877), Color(0xFF34D399)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 6),
              Text(
                "Wallet de ${session.username ?? 'Utilisateur'}",
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                onPressed: _load,
                icon: const Icon(Icons.refresh, color: Colors.white70),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _balanceVisible ? "$balance FCFA" : "••••••",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _balanceVisible = !_balanceVisible),
                icon: Icon(
                  _balanceVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Solde disponible",
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatChip(
                icon: Icons.south_west_outlined,
                label: "Rechargé",
                value: _balanceVisible
                    ? "${_topupTotal.toStringAsFixed(0)} FCFA"
                    : "••••",
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.north_east_outlined,
                label: "Retiré",
                value: _balanceVisible
                    ? "${_withdrawTotal.toStringAsFixed(0)} FCFA"
                    : "••••",
              ),
              const SizedBox(width: 10),
              _StatChip(
                icon: Icons.lock_outline,
                label: "Sécurisé",
                value: _balanceVisible ? "$blocked FCFA" : "••••",
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  color: Colors.white.withValues(alpha: 0.55), size: 13),
              const SizedBox(width: 5),
              Text(
                'Fonds sécurisés · Protégés par escrow',
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
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _QuickAction(
              icon: Icons.add_circle_outline,
              label: "Recharger",
              color: AppPalette.primary,
              onTap: () async {
                final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const WalletTopupPage()),
                );
                if (done == true) await _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.send_outlined,
              label: "Retirer",
              color: const Color(0xFF0EA5E9),
              onTap: () async {
                final done = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                      builder: (_) => const WalletWithdrawPage()),
                );
                if (done == true) await _load();
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _QuickAction(
              icon: Icons.pin_outlined,
              label: "PIN wallet",
              color: AppPalette.warning,
              onTap: _setWalletPin,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactions() {
    final filtered = _transactions.where((tx) {
      final status = (tx["status"] ?? "").toString().toUpperCase();
      final kind = (tx["kind"] ?? "").toString().toUpperCase();
      final okStatus = _statusFilter == "ALL" || status == _statusFilter;
      final okKind = _kindFilter == "ALL" || kind == _kindFilter;
      return okStatus && okKind;
    }).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text("Transactions",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text("${filtered.length} opération(s)",
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black45)),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...["ALL", "PENDING", "SUCCESS", "FAILED"].map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s == "ALL" ? "Tous" : s,
                          style: const TextStyle(fontSize: 12)),
                      selected: _statusFilter == s,
                      onSelected: (_) => setState(() => _statusFilter = s),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ...["ALL", "TOPUP", "WITHDRAWAL"].map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(k == "ALL" ? "Tous types" : k,
                          style: const TextStyle(fontSize: 12)),
                      selected: _kindFilter == k,
                      onSelected: (_) => setState(() => _kindFilter = k),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text("Aucune transaction pour ce filtre.",
                    style: TextStyle(color: Colors.black45)),
              ),
            )
          else
            ...filtered.take(30).map(_buildTxRow),
        ],
      ),
    );
  }

  Widget _buildTxRow(Map<String, dynamic> tx) {
    final status = (tx["status"] ?? "-").toString().toUpperCase();
    final kind = (tx["kind"] ?? "-").toString().toUpperCase();
    final reference = (tx["reference"] ?? "").toString();
    final amount = (tx["amount"] ?? "0").toString();
    final isTopup = kind == "TOPUP";
    final Color iconBg = isTopup
        ? AppPalette.primary.withValues(alpha: 0.12)
        : const Color(0xFF0EA5E9).withValues(alpha: 0.12);
    final Color iconColor =
        isTopup ? AppPalette.primary : const Color(0xFF0EA5E9);
    final Color badgeColor = status == "SUCCESS"
        ? AppPalette.success
        : status == "FAILED"
            ? AppPalette.danger
            : AppPalette.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration:
                BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(
                isTopup
                    ? Icons.south_west_outlined
                    : Icons.north_east_outlined,
                color: iconColor,
                size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(kind,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    AppStatusBadge(text: status, color: badgeColor),
                  ],
                ),
                if (reference.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(reference,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black45)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text("$amount FCFA",
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isTopup ? AppPalette.primary : Colors.black87,
                  fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildAdminReconcile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppPalette.warning.withValues(alpha: 0.4)),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppPalette.warning.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.admin_panel_settings_outlined,
                color: AppPalette.warning),
          ),
          title: const Text("Réconciliation",
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text("Forcer SUCCESS/FAILED sur une transaction."),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openReconcileDialog,
        ),
      ),
    );
  }

  Future<void> _setWalletPin() async {
    _pinController.clear();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Configurer PIN wallet"),
        content: TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          decoration:
              const InputDecoration(labelText: "PIN (4 chiffres)"),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler")),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Enregistrer")),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final pin = _pinController.text.trim();
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/auth/wallet-pin/", {"pin": pin}, token: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("PIN wallet configuré.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Impossible de configurer le PIN."))),
      );
    }
  }

  Future<void> _openReconcileDialog() async {
    if (_reconcileStatuses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text("Aucun statut de réconciliation disponible.")),
      );
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
          title: const Text("Réconciliation wallet"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: txController,
                decoration: const InputDecoration(
                    labelText: "Transaction ID externe"),
              ),
              DropdownButtonFormField<String>(
                initialValue: statusValue,
                items: _reconcileStatuses
                    .map((v) =>
                        DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setDialogState(() {
                  statusValue = v ?? _reconcileStatuses.first;
                }),
                decoration:
                    const InputDecoration(labelText: "Nouveau statut"),
              ),
              TextField(
                controller: reasonController,
                decoration:
                    const InputDecoration(labelText: "Raison"),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Annuler")),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Exécuter")),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/wallets/reconcile/", {
        "transaction_id": txController.text.trim(),
        "status": statusValue,
        "reason": reasonController.text.trim(),
      }, token: token);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Réconciliation effectuée.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_api.toUserMessage(e,
                fallback: "Réconciliation impossible."))),
      );
    }
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 12),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 8,
                offset: Offset(0, 2))
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

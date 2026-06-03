import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
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
  String _statusFilter = "ALL";
  String _kindFilter = "ALL";

  @override
  void initState() {
    super.initState();
    _load();
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

  double _asPositive(dynamic raw) =>
      (double.tryParse((raw ?? "0").toString()) ?? 0).abs();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        backgroundColor: AppPalette.bg,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          "Portefeuille",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
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
                      SliverToBoxAdapter(child: _buildBalanceCard(session)),
                      SliverToBoxAdapter(child: _buildMiniCards()),
                      SliverToBoxAdapter(child: _buildPaymentMethods()),
                      SliverToBoxAdapter(child: _buildTransactions()),
                      const SliverToBoxAdapter(child: SizedBox(height: 100)),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBalanceCard(SessionStore session) {
    final balance = (_wallet["balance"] ?? "0").toString();
    final walletId = (_wallet["id"] ?? "").toString();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F7A4F), Color(0xFF063D27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppPalette.shadowStrong,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "SOLDE DISPONIBLE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    setState(() => _balanceVisible = !_balanceVisible),
                icon: Icon(
                  _balanceVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.white70,
                  size: 18,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _balanceVisible ? "$balance FCFA" : "••••••",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          if (walletId.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "ID #$walletId",
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          // Badge PIN actif
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF5B400),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              "PIN actif",
              style: TextStyle(
                color: Colors.black87,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5B400),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () async {
                      final done = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const WalletTopupPage()),
                      );
                      if (done == true) await _load();
                    },
                    child: const Text(
                      "+ Recharger",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white, width: 1.4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      final done = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                            builder: (_) => const WalletWithdrawPage()),
                      );
                      if (done == true) await _load();
                    },
                    child: const Text(
                      "→ Envoyer",
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  icon: const Icon(Icons.qr_code, color: Colors.white, size: 20),
                  onPressed: _setWalletPin,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCards() {
    final blocked =
        (_wallet["blocked_balance"] ?? "0").toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _MiniCard(
              icon: Icons.shield_outlined,
              iconColor: const Color(0xFF0EA5E9),
              title: "Séquestre",
              value: _balanceVisible ? "$blocked FCFA" : "••••",
              subtitle: "2 commandes",
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MiniCard(
              icon: Icons.trending_up,
              iconColor: AppPalette.primary,
              title: "Mai 2026",
              value: _balanceVisible
                  ? "+${_topupTotal.toStringAsFixed(0)} FCFA"
                  : "••••",
              subtitle: "vs avril",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethods() {
    const methods = [
      _PaymentMethod(
        badge: "MTN",
        badgeColor: Color(0xFFF59E0B),
        title: "MTN Mobile Money",
        subtitle: "Instantané · 1%",
      ),
      _PaymentMethod(
        badge: "OM",
        badgeColor: Color(0xFFEA580C),
        title: "Orange Money",
        subtitle: "Instantané · 1%",
      ),
      _PaymentMethod(
        badge: "VISA",
        badgeColor: Color(0xFF1D4ED8),
        title: "Carte Visa",
        subtitle: "3-D Secure",
      ),
      _PaymentMethod(
        badge: "MC",
        badgeColor: Color(0xFFDC2626),
        title: "Mastercard",
        subtitle: "3-D Secure",
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Moyens de recharge",
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.8,
            children: methods.map((m) => _PaymentMethodCard(method: m)).toList(),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "Transactions",
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const Spacer(),
              Text("${filtered.length} opération(s)",
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
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
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
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
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black45)),
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
          decoration: const InputDecoration(labelText: "PIN (4 chiffres)"),
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

}

// ── Widgets helpers ───────────────────────────────────────────────────────────

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0F1F1A))),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.black38)),
        ],
      ),
    );
  }
}

class _PaymentMethod {
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;

  const _PaymentMethod({
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
  });
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({required this.method});

  final _PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: method.badgeColor,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              method.badge,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(method.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(method.subtitle,
                    style: const TextStyle(fontSize: 10, color: Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

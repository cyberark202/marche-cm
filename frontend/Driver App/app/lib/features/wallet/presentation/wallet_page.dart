import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/driver_dio_client.dart';
import '../../../core/theme/driver_theme.dart';

final _walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/wallets/driver/');
  return res.data as Map<String, dynamic>;
});

final _txProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await DriverDioClient.dio.get('/api/wallets/driver/transactions/');
  final data = res.data;
  if (data is List) return data.cast<Map<String, dynamic>>();
  if (data is Map && data['results'] is List) {
    return (data['results'] as List).cast<Map<String, dynamic>>();
  }
  return [];
});

class DriverWalletPage extends ConsumerWidget {
  const DriverWalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(_walletProvider);
    final txAsync = ref.watch(_txProvider);

    return Scaffold(
      backgroundColor: DriverPalette.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 28),
              decoration: const BoxDecoration(
                gradient: T.gradientDriverHeader,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Mon Portefeuille',
                      style: TextStyle(color: Colors.white, fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 20),
                  walletAsync.when(
                    loading: () => const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                    error: (_, __) => const Text('Erreur de chargement',
                        style: TextStyle(color: Colors.white70)),
                    data: (w) {
                      final balance = (w['balance'] ?? 0).toString();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Solde disponible',
                              style: TextStyle(color: Colors.white70, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('$balance FCFA',
                              style: const TextStyle(color: Colors.white, fontSize: 36,
                                  fontWeight: FontWeight.w800)),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.trending_up,
                        label: 'Gains',
                        onTap: () => context.push('/wallet/earnings'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _WalletAction(
                        icon: Icons.account_balance_outlined,
                        label: 'Retirer',
                        onTap: () => context.push('/wallet/withdraw'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Transactions récentes',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: DriverPalette.textPrimary)),
                  TextButton(
                    onPressed: () => context.push('/wallet/earnings'),
                    child: const Text('Voir tout'),
                  ),
                ],
              ),
            ),
          ),
          txAsync.when(
            loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator())),
            error: (_, __) => const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Impossible de charger les transactions.',
                    style: TextStyle(color: DriverPalette.textSecondary)),
              ),
            ),
            data: (txs) {
              if (txs.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: DriverPalette.textMuted),
                        SizedBox(height: 12),
                        Text('Aucune transaction pour le moment.',
                            style: TextStyle(color: DriverPalette.textSecondary, fontSize: 14)),
                      ]),
                    ),
                  ),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                sliver: SliverList.separated(
                  itemCount: txs.length > 10 ? 10 : txs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _TxTile(tx: txs[i]),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WalletAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _WalletAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 13,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

class _TxTile extends StatelessWidget {
  final Map<String, dynamic> tx;
  const _TxTile({required this.tx});

  @override
  Widget build(BuildContext context) {
    final type = tx['transaction_type'] as String? ?? '';
    final amount = (tx['amount'] ?? 0).toString();
    final createdAt = tx['created_at'] as String?;
    final isCredit = type == 'CREDIT' || type == 'EARNING';
    String date = '';
    if (createdAt != null) {
      try {
        date = DateFormat('dd/MM HH:mm').format(DateTime.parse(createdAt).toLocal());
      } catch (_) {}
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DriverPalette.border),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: (isCredit ? Colors.green : Colors.red).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isCredit ? Icons.arrow_downward : Icons.arrow_upward,
            color: isCredit ? Colors.green : Colors.red,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx['description'] ?? type,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: DriverPalette.textPrimary)),
            if (date.isNotEmpty)
              Text(date, style: const TextStyle(fontSize: 11, color: DriverPalette.textMuted)),
          ]),
        ),
        Text(
          '${isCredit ? '+' : '-'}$amount FCFA',
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: isCredit ? Colors.green : Colors.red),
        ),
      ]),
    );
  }
}

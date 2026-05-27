import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/app_theme.dart';
import '../../core/security/secure_dio_client.dart';
import '../auth/session_store.dart';
import 'buyer_kyc_page.dart';

class BuyerHomePage extends StatefulWidget {
  const BuyerHomePage({super.key});

  @override
  State<BuyerHomePage> createState() => _BuyerHomePageState();
}

class _BuyerHomePageState extends State<BuyerHomePage> {
  bool _loading = true;
  List<Map<String, dynamic>> _recommended = [];
  String _walletBalance = '—';
  bool _walletLoading = true;

  static const _categories = [
    _Cat('Alimentation', Icons.restaurant, Color(0xFF16A34A)),
    _Cat('Électronique', Icons.devices, Color(0xFF2563EB)),
    _Cat('Vêtements', Icons.checkroom, Color(0xFF7C3AED)),
    _Cat('Agriculture', Icons.grass, Color(0xFF15803D)),
    _Cat('Beauté', Icons.spa, Color(0xFFDB2777)),
    _Cat('Construction', Icons.construction, Color(0xFFCA8A04)),
    _Cat('Auto-Moto', Icons.directions_car, Color(0xFFDC2626)),
    _Cat('Services', Icons.handyman, Color(0xFF0891B2)),
  ];

  @override
  void initState() {
    super.initState();
    _loadRecommended();
    _loadWallet();
  }

  Future<void> _loadRecommended() async {
    setState(() => _loading = true);
    try {
      final resp = await SecureDioClient.dio.get('/api/products/recommended/');
      final data = resp.data;
      final raw = data is Map ? (data['results'] ?? data['data'] ?? []) : data;
      if (!mounted) return;
      setState(() {
        _recommended =
            List<Map<String, dynamic>>.from(raw is List ? raw : []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadWallet() async {
    try {
      // Audit ref: [Front-marche_cm] no /api/wallets/me/ endpoint exists.
      // WalletViewSet.list is auto-filtered to owner=request.user, so the
      // first (and only) row is always the caller's own wallet.
      final resp = await SecureDioClient.dio.get('/api/wallets/');
      final data = resp.data;
      Map<String, dynamic> wallet = {};
      if (data is Map && data['results'] is List && (data['results'] as List).isNotEmpty) {
        wallet = (data['results'] as List).first as Map<String, dynamic>;
      } else if (data is List && data.isNotEmpty) {
        wallet = data.first as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        wallet = data;
      }
      final balance =
          (wallet['available_balance'] ?? wallet['balance'] ?? 0).toString();
      if (!mounted) return;
      setState(() {
        _walletBalance = _fmtBalance(balance);
        _walletLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _walletLoading = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadRecommended(), _loadWallet()]);
  }

  String _fmtBalance(String v) {
    final n = num.tryParse(v) ?? 0;
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)} M';
    if (n >= 1000) {
      final k = (n / 1000).toStringAsFixed(0);
      return '$k 000';
    }
    return n.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final firstName =
        (session.username ?? 'vous').split(' ').first;

    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppPalette.primary,
        child: CustomScrollView(
          slivers: [
            // ── App bar ──────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.white,
              elevation: 0,
              toolbarHeight: 60,
              title: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppPalette.gradientPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.storefront,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Bonjour, $firstName !',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0E1F18))),
                    const Text('Market CM',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF5C6B64))),
                  ],
                ),
              ]),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: Color(0xFF2D3D36)),
                  onPressed: () {},
                ),
              ],
            ),

            // ── Wallet card ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding:
                    const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  gradient: AppPalette.gradientHero,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppPalette.shadowMedium,
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -16,
                      top: -16,
                      child: Icon(Icons.account_balance_wallet,
                          size: 110,
                          color: Colors.white.withValues(alpha: 0.07)),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Solde disponible',
                            style: TextStyle(
                                fontSize: 12,
                                color:
                                    Colors.white.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        _walletLoading
                            ? Container(
                                width: 120,
                                height: 30,
                                decoration: BoxDecoration(
                                  color:
                                      Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              )
                            : Text(
                                '$_walletBalance FCFA',
                                style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.6),
                              ),
                        const SizedBox(height: 16),
                        Row(children: [
                          _WalletAction(
                            icon: Icons.add,
                            label: 'Recharger',
                            onTap: () {},
                          ),
                          const SizedBox(width: 10),
                          _WalletAction(
                            icon: Icons.send_outlined,
                            label: 'Envoyer',
                            onTap: () {},
                          ),
                          const SizedBox(width: 10),
                          _WalletAction(
                            icon: Icons.history,
                            label: 'Historique',
                            onTap: () {},
                          ),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Search bar ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  margin:
                      const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppPalette.border),
                  ),
                  child: const Row(children: [
                    Icon(Icons.search,
                        color: Color(0xFF8F9C96), size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Rechercher un produit, une boutique…',
                      style: TextStyle(
                          color: Color(0xFF8F9C96), fontSize: 14),
                    ),
                  ]),
                ),
              ),
            ),

            // ── KYC banner ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BuyerKycPage())),
                child: Container(
                  margin:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF4D6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFF5B400)
                            .withValues(alpha: 0.5)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.shield_outlined,
                        color: Color(0xFFC68F00), size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Vérifiez votre identité pour débloquer toutes les fonctionnalités',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E5A00),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        size: 16, color: Color(0xFFC68F00)),
                  ]),
                ),
              ),
            ),

            // ── Categories 4×2 grid ───────────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Text('Catégories',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E1F18),
                        letterSpacing: -0.2)),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(
                child: GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                  children: _categories
                      .map((c) => _CategoryTile(cat: c))
                      .toList(),
                ),
              ),
            ),

            // ── Products header ───────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Row(children: [
                  const Expanded(
                    child: Text('Recommandés pour vous',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0E1F18),
                            letterSpacing: -0.2)),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: const Text('Voir tout →',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.primary)),
                  ),
                ]),
              ),
            ),

            // ── Products grid ─────────────────────────────────────────────
            if (_loading)
              const SliverToBoxAdapter(child: _ShimmerGrid())
            else if (_recommended.isEmpty)
              const SliverToBoxAdapter(child: _EmptyProducts())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ProductCard(
                        product: _recommended[i]),
                    childCount: _recommended.length,
                  ),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              ),
            const SliverToBoxAdapter(
                child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ── Wallet action button ───────────────────────────────────────────────────────

class _WalletAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _WalletAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ── Category tile ─────────────────────────────────────────────────────────────

class _Cat {
  final String name;
  final IconData icon;
  final Color color;
  const _Cat(this.name, this.icon, this.color);
}

class _CategoryTile extends StatelessWidget {
  final _Cat cat;
  const _CategoryTile({required this.cat});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {},
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: cat.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(cat.icon, color: cat.color, size: 24),
            ),
            const SizedBox(height: 5),
            Text(cat.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2D3D36))),
          ],
        ),
      );
}

// ── Product card ──────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final name =
        (product['name'] ?? product['title'] ?? 'Produit').toString();
    final price = product['price'] ?? product['unit_price'] ?? '—';
    final images = product['images'];
    final imageUrl = images is List && images.isNotEmpty
        ? (images.first['url'] ?? images.first['image'] ?? '')
            .toString()
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14)),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) =>
                          _imgPlaceholder())
                  : _imgPlaceholder(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0E1F18))),
                const SizedBox(height: 4),
                Text('$price XAF',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.primary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: AppPalette.bgSoft,
        child: const Center(
            child: Icon(Icons.image_outlined,
                size: 38, color: Color(0xFF8F9C96))),
      );
}

// ── Shimmer & empty ───────────────────────────────────────────────────────────

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();

  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: AppPalette.bgSoft,
        highlightColor: Colors.white,
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.storefront_outlined,
                size: 56, color: Color(0xFF8F9C96)),
            SizedBox(height: 14),
            Text('Aucun produit disponible',
                style: TextStyle(
                    color: Color(0xFF5C6B64), fontSize: 14)),
          ]),
        ),
      );
}

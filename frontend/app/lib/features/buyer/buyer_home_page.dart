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
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  static const _banners = [
    _Banner('Bienvenue sur Market CM', 'Le marché digital du Cameroun',
        [Color(0xFF0F766E), Color(0xFF059669)], Icons.storefront),
    _Banner('Produits locaux & frais', 'Soutenez les producteurs camerounais',
        [Color(0xFF4F46E5), Color(0xFF7C3AED)], Icons.local_florist),
    _Banner('Paiement 100% sécurisé', 'MTN Money & Orange Money acceptés',
        [Color(0xFFF59E0B), Color(0xFFEA580C)], Icons.security),
  ];

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
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _bannerIndex = (_bannerIndex + 1) % _banners.length);
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRecommended() async {
    setState(() => _loading = true);
    try {
      final resp = await SecureDioClient.dio.get('/api/products/recommended/');
      final data = resp.data;
      final raw = data is Map ? (data['results'] ?? data['data'] ?? []) : data;
      if (!mounted) return;
      setState(() {
        _recommended = List<Map<String, dynamic>>.from(raw is List ? raw : []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final firstName = (session.username ?? 'vous').split(' ').first;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: _loadRecommended,
        color: AppPalette.primary,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(firstName),
            const SliverToBoxAdapter(child: SizedBox(height: 4)),
            SliverToBoxAdapter(child: _buildHeroBanner()),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildKycBanner()),
            SliverToBoxAdapter(child: _buildCategoriesSection()),
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Recommandés pour vous',
                icon: Icons.star_outline,
                onSeeAll: () {},
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: _ShimmerGrid())
            else if (_recommended.isEmpty)
              const SliverToBoxAdapter(child: _EmptyProducts())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ProductCard(product: _recommended[i]),
                    childCount: _recommended.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.78,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  SliverAppBar _buildAppBar(String firstName) => SliverAppBar(
        floating: true,
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 64,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                gradient:
                    const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF059669)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.storefront, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Bonjour, $firstName !',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const Text('Market CM',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF475569)),
            onPressed: () {},
          ),
        ],
      );

  Widget _buildHeroBanner() {
    final b = _banners[_bannerIndex];
    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        height: 156,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: b.colors),
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppPalette.shadowMedium,
        ),
        child: Stack(
          children: [
            Positioned(
              right: -8,
              bottom: -8,
              child: Icon(b.icon, size: 110,
                  color: Colors.white.withValues(alpha: 0.13)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 90, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(b.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.2)),
                  const SizedBox(height: 6),
                  Text(b.subtitle,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88), fontSize: 13)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Text('Explorer →',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 10,
              right: 14,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  _banners.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: i == _bannerIndex ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: i == _bannerIndex ? 1.0 : 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() => GestureDetector(
        onTap: () {},
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: const Row(
            children: [
              Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
              SizedBox(width: 10),
              Text('Rechercher un produit, une boutique...',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
            ],
          ),
        ),
      );

  Widget _buildKycBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BuyerKycPage())),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF3C7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
        ),
        child: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFFD97706), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Vérifiez votre identité pour débloquer toutes les fonctionnalités',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Color(0xFFD97706)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Catégories', icon: Icons.grid_view_outlined, onSeeAll: () {}),
          SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (_, i) {
                final c = _categories[i];
                return GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 76,
                    margin: const EdgeInsets.only(right: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: c.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(c.icon, color: c.color, size: 24),
                        ),
                        const SizedBox(height: 5),
                        Text(c.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _Banner {
  final String title, subtitle;
  final List<Color> colors;
  final IconData icon;
  const _Banner(this.title, this.subtitle, this.colors, this.icon);
}

class _Cat {
  final String name;
  final IconData icon;
  final Color color;
  const _Cat(this.name, this.icon, this.color);
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback? onSeeAll;
  const _SectionHeader({required this.title, required this.icon, this.onSeeAll});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 8),
        child: Row(
          children: [
            Icon(icon, size: 17, color: AppPalette.primary),
            const SizedBox(width: 7),
            Text(title,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            const Spacer(),
            if (onSeeAll != null)
              TextButton(
                onPressed: onSeeAll,
                child: const Text('Voir tout', style: TextStyle(fontSize: 13)),
              ),
          ],
        ),
      );
}

class _ShimmerGrid extends StatelessWidget {
  const _ShimmerGrid();
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: const Color(0xFFE2E8F0),
        highlightColor: const Color(0xFFF8FAFC),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.78,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: 6,
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 56, color: Color(0xFFCBD5E1)),
              SizedBox(height: 14),
              Text('Aucun produit disponible',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14)),
            ],
          ),
        ),
      );
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final name = (product['name'] ?? product['title'] ?? 'Produit').toString();
    final price = product['price'] ?? product['unit_price'] ?? '—';
    final images = product['images'];
    final imageUrl = images is List && images.isNotEmpty
        ? (images.first['url'] ?? images.first['image'] ?? '').toString()
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppPalette.shadowSoft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => _imgPlaceholder())
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
                        color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text('$price XAF',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F766E))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(
            child:
                Icon(Icons.image_outlined, size: 38, color: Color(0xFFCBD5E1))),
      );
}

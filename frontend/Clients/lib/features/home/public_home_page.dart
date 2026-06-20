import 'package:flutter/material.dart';

import '../../core/app_i18n.dart';
import '../../core/app_logo.dart';
import '../../core/app_theme.dart';
import '../../core/cm_components.dart';
import '../../core/ui_state_widgets.dart';
import '../common/support_center_page.dart';
import '../feed/feed_api_service.dart';
import '../feed/feed_models.dart';

class PublicHomePage extends StatefulWidget {
  const PublicHomePage({
    super.key,
    required this.onLoginRequested,
    required this.onRegisterRequested,
  });

  final VoidCallback onLoginRequested;
  final VoidCallback onRegisterRequested;

  @override
  State<PublicHomePage> createState() => _PublicHomePageState();
}

class _PublicHomePageState extends State<PublicHomePage> {
  final FeedApiService _feedApi = FeedApiService();
  late Future<List<ProductCardData>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadProducts();
  }

  Future<List<ProductCardData>> _loadProducts() async {
    final payload = await _feedApi.loadFeed();
    return payload.products;
  }

  static const List<CmTone> _tones = [
    CmTone.primary,
    CmTone.accent,
    CmTone.cream,
    CmTone.sky,
    CmTone.coral,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: FutureBuilder<List<ProductCardData>>(
        future: _future,
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <ProductCardData>[];
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHero(context)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    context.tr("public.products.title"),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: AppPalette.text,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppLoadingState(
                        label: context.tr("public.products.loading")),
                  ),
                )
              else if (snapshot.hasError)
                SliverToBoxAdapter(
                  child: AppErrorState(
                    message: context.tr("public.products.load_error"),
                    onRetry: () =>
                        setState(() => _future = _loadProducts()),
                  ),
                )
              else if (products.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppEmptyState(
                      title: context.tr("public.products.empty"),
                      subtitle: context.tr("public.products.empty_subtitle"),
                      icon: Icons.store_mall_directory_outlined,
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.62,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final p = products[i];
                        return CmProductCard(
                          name: p.title,
                          supplier: p.brand,
                          price: '${p.priceMin}',
                          tone: _tones[i % _tones.length],
                          imageUrl: p.imageUrl,
                          onTap: widget.onLoginRequested,
                          onAdd: widget.onLoginRequested,
                          onFavorite: widget.onLoginRequested,
                        );
                      },
                      childCount: products.length > 20 ? 20 : products.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppPalette.primary, Color(0xFF063D27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const MarcheLogo(size: 36, withWordmark: true, light: true),
                const Spacer(),
                IconButton(
                  tooltip: context.tr("public.support"),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SupportCenterPage()),
                  ),
                  icon: const Icon(Icons.help_outline, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              context.tr("public.hero.title"),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr("public.hero.subtitle"),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.accent,
                        foregroundColor: const Color(0xFF1A0F00),
                      ),
                      onPressed: widget.onLoginRequested,
                      child: Text(context.tr("public.hero.login")),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      onPressed: widget.onRegisterRequested,
                      child: Text(context.tr("public.hero.signup")),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

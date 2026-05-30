import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_config.dart';
import '../../core/app_theme.dart';
import '../../core/app_ui.dart';
import '../auth/session_store.dart';
import '../business/rfqs_page.dart';
import '../chat/chat_hub_page.dart';

class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key});

  @override
  State<MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends State<MarketplaceTab> {
  final _api = ApiService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _products = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String _selectedCategory = 'Tous';
  String _query = '';
  int _page = 1;
  bool _hasMore = true;

  static const _categories = [
    'Tous',
    'Alimentaire',
    'Textile',
    'Électronique',
    'Matériaux',
    'Cosmétiques',
    'Agriculture',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (!mounted) return;
    if (reset) {
      setState(() {
        _loading = true;
        _page = 1;
        _hasMore = true;
      });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    final token = context.read<SessionStore>().token;
    final nextPage = reset ? 1 : _page + 1;

    try {
      final params = StringBuffer('/api/products/?page=$nextPage&page_size=20');
      if (_query.trim().isNotEmpty) {
        params.write('&search=${Uri.encodeQueryComponent(_query.trim())}');
      }
      if (_selectedCategory != 'Tous') {
        params.write('&category=${Uri.encodeQueryComponent(_selectedCategory)}');
      }

      final rows = await _api.getList(params.toString(), token: token);
      if (!mounted) return;
      setState(() {
        _page = nextPage;
        _hasMore = rows.length >= 20;
        _products = reset ? rows : [..._products, ...rows];
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _onSearch(String value) {
    _query = value;
    _load(reset: true);
  }

  void _onCategorySelected(String cat) {
    if (_selectedCategory == cat) return;
    setState(() => _selectedCategory = cat);
    _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildAppBar(innerBoxIsScrolled),
          _buildCategoryBar(),
        ],
        body: _loading
            ? _buildSkeleton()
            : _products.isEmpty
                ? AppEmptyStateView(
                    icon: Icons.storefront_outlined,
                    title: 'Aucun produit trouvé',
                    message:
                        'Essayez de modifier vos filtres ou votre recherche.',
                    action: TextButton(
                      onPressed: () {
                        _searchController.clear();
                        _query = '';
                        _selectedCategory = 'Tous';
                        _load(reset: true);
                      },
                      child: const Text('Réinitialiser'),
                    ),
                  )
                : RefreshIndicator(
                    color: AppPalette.primary,
                    onRefresh: () => _load(reset: true),
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.68,
                      ),
                      itemCount:
                          _products.length + (_loadingMore ? 2 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _products.length) {
                          return _SkeletonCard();
                        }
                        return _ProductCard(product: _products[index]);
                      },
                    ),
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RfqsPage()),
        ),
        icon: const Icon(Icons.request_quote_rounded),
        label: const Text('Appel d\'offre'),
        backgroundColor: AppPalette.secondary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
    );
  }

  SliverAppBar _buildAppBar(bool innerBoxIsScrolled) {
    return SliverAppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      floating: true,
      snap: true,
      elevation: innerBoxIsScrolled ? 1 : 0,
      shadowColor: AppPalette.border,
      title: const Text(
        'Marché B2B',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 19,
          letterSpacing: -0.3,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: TextField(
            controller: _searchController,
            onSubmitted: _onSearch,
            onChanged: (v) {
              if (v.isEmpty && _query.isNotEmpty) {
                _query = '';
                _load(reset: true);
              }
            },
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Rechercher produits, fournisseurs…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearch('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppPalette.bgSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
                borderSide:
                    const BorderSide(color: AppPalette.primary, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              isDense: true,
            ),
          ),
        ),
      ),
    );
  }

  SliverToBoxAdapter _buildCategoryBar() {
    return SliverToBoxAdapter(
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final cat = _categories[i];
            final selected = _selectedCategory == cat;
            return AppFilterChip(
              label: cat,
              selected: selected,
              onTap: () => _onCategorySelected(cat),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.68,
      ),
      itemCount: 6,
      itemBuilder: (_, __) => _SkeletonCard(),
    );
  }
}

// ─── Product Card ─────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final name = (product['title'] ?? product['name'] ?? 'Produit').toString();
    final priceMin = (product['price_for_min_qty'] ?? 0).toString();
    final priceMax = (product['price_for_max_qty'] ?? '').toString();
    final isVerified = product['seller_is_verified'] == true;
    final imageUrl = (product['image'] ?? '').toString();
    final hasVideo = product['has_video'] == true ||
        (product['video_url'] ?? '').toString().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppPalette.borderSoft),
            boxShadow: AppPalette.shadowSoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image area
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadii.lg)),
                      child: imageUrl.isNotEmpty
                          ? Image.network(
                              _fullUrl(imageUrl),
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _ImagePlaceholder(),
                            )
                          : _ImagePlaceholder(),
                    ),
                    if (isVerified)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppPalette.success,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified_rounded,
                                  color: Colors.white, size: 10),
                              SizedBox(width: 3),
                              Text(
                                'Vérifié',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (hasVideo)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                  ],
                ),
              ),
              // Info area
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: -0.1,
                          color: AppPalette.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        priceMax.isNotEmpty && priceMax != priceMin
                            ? '$priceMin – $priceMax FCFA'
                            : '$priceMin FCFA',
                        style: const TextStyle(
                          color: AppPalette.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RfqsPage()),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            side: const BorderSide(
                                color: AppPalette.secondary, width: 1.2),
                            foregroundColor: AppPalette.secondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            textStyle: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                          child: const Text('Demander RFQ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductDetailSheet(product: product),
    );
  }

  String _fullUrl(String path) {
    if (path.startsWith('http')) return path;
    return '${AppConfig.apiBaseUrl}$path';
  }
}

// ─── Product Detail Sheet ─────────────────────────────────────────────────────

class _ProductDetailSheet extends StatefulWidget {
  const _ProductDetailSheet({required this.product});
  final Map<String, dynamic> product;

  @override
  State<_ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends State<_ProductDetailSheet> {
  final _api = ApiService();
  bool _contacting = false;

  Future<void> _contact(BuildContext context) async {
    if (_contacting) return;
    setState(() => _contacting = true);
    final token = context.read<SessionStore>().token;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final productName =
        (widget.product['title'] ?? widget.product['name'] ?? 'Produit')
            .toString();
    try {
      final sellerId =
          widget.product['seller'] ?? widget.product['supplier_id'];
      final body = <String, dynamic>{
        'name': 'Discussion - $productName',
        if (sellerId != null) 'participants': [sellerId],
      };
      final room = await _api.post('/api/chat/rooms/', body, token: token);
      if (!mounted) return;
      final roomId = room['id'] is int ? room['id'] as int : null;
      navigator.pop();
      navigator.push(
        MaterialPageRoute(builder: (_) => ChatHubPage(initialRoomId: roomId)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(_api.toUserMessage(
              e, fallback: "Impossible d'ouvrir la discussion.")),
        ),
      );
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name =
        (widget.product['title'] ?? widget.product['name'] ?? 'Produit')
            .toString();
    final priceMin = (widget.product['price_for_min_qty'] ?? 0).toString();
    final priceMax = (widget.product['price_for_max_qty'] ?? '').toString();
    final imageUrl = (widget.product['image'] ?? '').toString();
    final description = (widget.product['description'] ?? '').toString();
    final supplier = (widget.product['seller_username'] ?? '').toString();
    final isVerified = widget.product['seller_is_verified'] == true;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollController) => Column(
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppPalette.borderSoft,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (imageUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: Image.network(
                      imageUrl.startsWith('http')
                          ? imageUrl
                          : '${AppConfig.apiBaseUrl}$imageUrl',
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          color: AppPalette.text,
                        ),
                      ),
                    ),
                    if (isVerified)
                      const Icon(Icons.verified_rounded,
                          color: AppPalette.success, size: 18),
                  ],
                ),
                if (supplier.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '@$supplier',
                    style: const TextStyle(
                        color: AppPalette.textMuted, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  priceMax.isNotEmpty && priceMax != priceMin
                      ? '$priceMin – $priceMax FCFA'
                      : '$priceMin FCFA',
                  style: const TextStyle(
                    color: AppPalette.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    description,
                    style: const TextStyle(
                        color: AppPalette.textMuted,
                        fontSize: 13.5,
                        height: 1.45),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _contacting ? null : () => _contact(context),
                    icon: _contacting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.chat_rounded),
                    label: const Text('Contacter le vendeur'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppPalette.secondary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RfqsPage()));
                    },
                    icon: const Icon(Icons.request_quote_rounded),
                    label: const Text('Demander un devis (RFQ)'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppPalette.primary),
                      foregroundColor: AppPalette.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppPalette.bgSoft,
      child: const Center(
        child: Icon(Icons.image_outlined, color: AppPalette.textFaint, size: 34),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppPalette.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Container(
              decoration: const BoxDecoration(
                color: AppPalette.bgSoft,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadii.lg)),
              ),
            ),
          ),
          const Expanded(
            flex: 4,
            child: Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(width: double.infinity, height: 12),
                  SizedBox(height: 6),
                  _SkeletonBox(width: 80, height: 12),
                  Spacer(),
                  _SkeletonBox(width: double.infinity, height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppPalette.bgDeep,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

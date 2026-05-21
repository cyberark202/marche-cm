import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/app_theme.dart';
import '../../core/security/secure_dio_client.dart';

class BuyerCatalogPage extends StatefulWidget {
  const BuyerCatalogPage({super.key});

  @override
  State<BuyerCatalogPage> createState() => _BuyerCatalogPageState();
}

class _BuyerCatalogPageState extends State<BuyerCatalogPage> {
  final _searchCtrl = TextEditingController();
  String _selectedCategory = 'Tous';
  String _sortBy = 'recent';
  bool _loading = false;
  List<Map<String, dynamic>> _products = [];

  static const _categories = [
    'Tous', 'Alimentation', 'Électronique', 'Vêtements',
    'Agriculture', 'Beauté', 'Construction', 'Auto-Moto', 'Services',
  ];

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchProducts({String? query}) async {
    setState(() => _loading = true);
    try {
      final params = <String, dynamic>{'page_size': 30};
      if (query != null && query.isNotEmpty) params['search'] = query;
      if (_selectedCategory != 'Tous') params['category'] = _selectedCategory;
      if (_sortBy == 'price_asc') params['ordering'] = 'price';
      if (_sortBy == 'price_desc') params['ordering'] = '-price';

      final resp = await SecureDioClient.dio.get('/api/products/', queryParameters: params);
      final data = resp.data;
      final raw = data is Map ? (data['results'] ?? []) : (data is List ? data : []);
      if (!mounted) return;
      setState(() {
        _products = List<Map<String, dynamic>>.from(raw);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchSubmit(String v) => _fetchProducts(query: v);

  void _onCategorySelect(String cat) {
    setState(() => _selectedCategory = cat);
    _fetchProducts(query: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            _buildFilters(),
            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : _products.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: () => _fetchProducts(
                              query: _searchCtrl.text.trim().isEmpty
                                  ? null
                                  : _searchCtrl.text.trim()),
                          color: AppPalette.primary,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.78,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _products.length,
                            itemBuilder: (_, i) =>
                                _CatalogProductCard(product: _products[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() => Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Row(
          children: [
            const Text('Catalogue',
                style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            const Spacer(),
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort_rounded, color: Color(0xFF475569)),
              onSelected: (v) {
                setState(() => _sortBy = v);
                _fetchProducts(
                    query: _searchCtrl.text.trim().isEmpty
                        ? null
                        : _searchCtrl.text.trim());
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'recent', child: Text('Plus récents')),
                const PopupMenuItem(value: 'price_asc', child: Text('Prix croissant')),
                const PopupMenuItem(value: 'price_desc', child: Text('Prix décroissant')),
              ],
            ),
          ],
        ),
      );

  Widget _buildFilters() => Container(
        color: Colors.white,
        child: Column(
          children: [
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchCtrl,
                onSubmitted: _onSearchSubmit,
                onTap: () {},
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                decoration: InputDecoration(
                  hintText: 'Rechercher un produit...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _fetchProducts();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF1F5F9),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppPalette.primary, width: 1.2),
                  ),
                ),
              ),
            ),
            // Category chips
            SizedBox(
              height: 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                itemCount: _categories.length,
                itemBuilder: (_, i) {
                  final cat = _categories[i];
                  final selected = cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () => _onCategorySelect(cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppPalette.primary : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: selected ? Colors.white : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
          ],
        ),
      );

  Widget _buildShimmer() => Shimmer.fromColors(
        baseColor: const Color(0xFFE2E8F0),
        highlightColor: const Color(0xFFF8FAFC),
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, childAspectRatio: 0.78,
            crossAxisSpacing: 12, mainAxisSpacing: 12,
          ),
          itemCount: 8,
          itemBuilder: (_, __) => Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
          ),
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 64, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 16),
            const Text('Aucun produit trouvé',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            const SizedBox(height: 8),
            const Text('Modifiez vos filtres ou votre recherche',
                style: TextStyle(color: Color(0xFF94A3B8))),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _selectedCategory = 'Tous');
                _fetchProducts();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réinitialiser'),
            ),
          ],
        ),
      );
}

class _CatalogProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  const _CatalogProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    final name = (product['name'] ?? product['title'] ?? 'Produit').toString();
    final price = product['price'] ?? product['unit_price'] ?? '—';
    final unit = product['unit'] ?? '';
    final images = product['images'];
    final imageUrl = images is List && images.isNotEmpty
        ? (images.first['url'] ?? images.first['image'] ?? '').toString()
        : '';
    final seller = (product['seller_name'] ?? product['owner_name'] ?? '').toString();

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
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  child: imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholder())
                      : _placeholder(),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.favorite_border, size: 16, color: Color(0xFF64748B)),
                  ),
                ),
              ],
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
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                const SizedBox(height: 3),
                if (seller.isNotEmpty)
                  Text(seller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text('$price XAF${unit.isNotEmpty ? ' / $unit' : ''}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F766E))),
                    ),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppPalette.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, size: 14, color: Colors.white),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(
            child: Icon(Icons.image_outlined, size: 38, color: Color(0xFFCBD5E1))),
      );
}

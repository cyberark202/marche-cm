import 'package:flutter/material.dart';

import '../../core/app_i18n.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Central Market"),
        actions: [
          IconButton(
            tooltip: context.tr("public.support"),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportCenterPage()),
            ),
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
      body: FutureBuilder<List<ProductCardData>>(
        future: _future,
        builder: (context, snapshot) {
          final products = snapshot.data ?? const <ProductCardData>[];
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr("public.hero.title"),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr("public.hero.subtitle"),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: widget.onLoginRequested,
                            child: Text(context.tr("public.hero.login")),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: widget.onRegisterRequested,
                            child: Text(context.tr("public.hero.signup")),
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr("public.products.title"),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (snapshot.connectionState == ConnectionState.waiting)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: AppLoadingState(label: context.tr("public.products.loading")),
                )
              else if (snapshot.hasError)
                AppErrorState(
                  message: context.tr("public.products.load_error"),
                  onRetry: () => setState(() => _future = _loadProducts()),
                )
              else if (products.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: AppEmptyState(
                    title: context.tr("public.products.empty"),
                    subtitle: context.tr("public.products.empty_subtitle"),
                    icon: Icons.store_mall_directory_outlined,
                  ),
                )
              else
                ...products.take(20).map((p) => Card(
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            p.imageUrl,
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) =>
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                        ),
                        title: Text(p.title),
                        subtitle: Text(
                            "${p.category} | ${p.brand} | ${p.priceMin} - ${p.priceMax} FCFA"),
                      ),
                    )),
            ],
          );
        },
      ),
    );
  }
}

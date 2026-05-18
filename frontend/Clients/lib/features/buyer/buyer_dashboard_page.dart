import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'buyer_store.dart';
import '../feed/feed_page.dart';

class BuyerDashboardPage extends StatelessWidget {
  const BuyerDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final existingStore = Provider.of<BuyerStore?>(context, listen: false);
    if (existingStore != null) {
      return const FeedPage();
    }
    return ChangeNotifierProvider(
      create: (_) => BuyerStore(),
      child: const FeedPage(),
    );
  }
}

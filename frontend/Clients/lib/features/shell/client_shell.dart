import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_icons.dart';
import '../../core/cm_components.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import '../buyer/buyer_store.dart';
import '../chat/chat_hub_page.dart';
import '../orders/orders_page.dart';
import '../profile/profile_hub_page.dart';
import '../wallet/wallet_page.dart';
import 'shop_tab.dart';
import 'videos_tab.dart';

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int _index = 0;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _hydrateCart();
  }

  /// Restaure le panier depuis le serveur (persistant, multi-appareils).
  Future<void> _hydrateCart() async {
    final token = context.read<SessionStore>().token;
    if (token == null || token.isEmpty) return;
    try {
      final rows = await _api.getList("/api/cart/", token: token);
      final items = rows
          .where((r) => r["product"] != null)
          .map((r) => CartEntry(
                productId: (r["product"] as num).toInt(),
                quantity: (r["quantity"] as num?)?.toInt() ?? 1,
              ))
          .toList();
      if (!mounted) return;
      context.read<BuyerStore>().hydrateCart(items);
    } catch (_) {
      // Best-effort : un panier serveur inaccessible n'empêche pas d'acheter.
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<BuyerStore>().unreadNotificationsCount;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _index == 1
          ? SystemUiOverlayStyle.light
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
      child: Scaffold(
        body: Column(
          children: [
            const CmOfflineBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  const ShopTab(),
                  VideosTab(active: _index == 1),
                  const ChatHubPage(),
                  const OrdersPage(),
                  const WalletPage(),
                  const ProfileHubPage(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: CmBottomNav(
          currentIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          items: [
            const CmNavItem(icon: AppIcons.shoppingBag, label: "Boutique"),
            const CmNavItem(icon: AppIcons.video, label: "Vidéos"),
            CmNavItem(
              icon: AppIcons.chat,
              label: "Messages",
              badge: unread,
            ),
            const CmNavItem(icon: AppIcons.receipt, label: "Commandes"),
            const CmNavItem(icon: AppIcons.wallet, label: "Wallet"),
            const CmNavItem(icon: AppIcons.person, label: "Profil"),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
        body: IndexedStack(
          index: _index,
          children: const [
            ShopTab(),
            VideosTab(),
            ChatHubPage(),
            OrdersPage(),
            WalletPage(),
            ProfileHubPage(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag),
              label: "Boutique",
            ),
            const NavigationDestination(
              icon: Icon(Icons.smart_display_outlined),
              selectedIcon: Icon(Icons.smart_display),
              label: "Vidéos",
            ),
            NavigationDestination(
              icon: Badge(
                label: Text(unread.toString()),
                isLabelVisible: unread > 0,
                child: const Icon(Icons.chat_bubble_outline),
              ),
              selectedIcon: Badge(
                label: Text(unread.toString()),
                isLabelVisible: unread > 0,
                child: const Icon(Icons.chat_bubble),
              ),
              label: "Messages",
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: "Commandes",
            ),
            const NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet),
              label: "Wallet",
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: "Profil",
            ),
          ],
        ),
      ),
    );
  }
}

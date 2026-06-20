import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/cm_components.dart';
import '../buyer/buyer_store.dart';
import '../chat/chat_hub_page.dart';
import '../feed/video_feed_tab.dart';
import '../home/home_tab.dart';
import '../marketplace/marketplace_tab.dart';
import '../profile/profile_tab.dart';
import '../wallet/wallet_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  void jumpToTab(int index) {
    if (index >= 0 && index < 6) {
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.watch<BuyerStore>().unreadNotificationsCount;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _index == 2
          ? SystemUiOverlayStyle.light
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
            ),
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            HomeTab(),
            MarketplaceTab(),
            VideoFeedTab(),
            ChatHubPage(),
            WalletPage(),
            ProfileTab(),
          ],
        ),
        bottomNavigationBar: CmBottomNav(
          currentIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          items: [
            const CmNavItem(icon: Icons.home_outlined, label: 'Accueil'),
            const CmNavItem(icon: Icons.storefront_outlined, label: 'Marché'),
            const CmNavItem(
                icon: Icons.play_circle_outline_rounded, label: 'Vidéos'),
            CmNavItem(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Messages',
                badge: unread),
            const CmNavItem(
                icon: Icons.account_balance_wallet_outlined, label: 'Wallet'),
            const CmNavItem(icon: Icons.person_outline_rounded, label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

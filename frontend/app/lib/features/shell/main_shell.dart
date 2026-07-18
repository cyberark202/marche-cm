import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/cm_components.dart';
import '../../core/ui_state_widgets.dart';
import '../buyer/buyer_store.dart';
import '../chat/chat_hub_page.dart';
import '../feed/video_feed_tab.dart';
import '../home/home_tab.dart';
import '../marketplace/marketplace_tab.dart';
import '../profile/profile_tab.dart';
import '../wallet/wallet_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
        body: Column(
          children: [
            const CmOfflineBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  const HomeTab(),
                  const MarketplaceTab(),
                  VideoFeedTab(active: _index == 2),
                  const ChatHubPage(),
                  const WalletPage(),
                  const ProfileTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: CmBottomNav(
          currentIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          items: [
            const CmNavItem(icon: LucideIcons.home, label: 'Accueil'),
            const CmNavItem(icon: LucideIcons.store, label: 'Marché'),
            const CmNavItem(
                icon: LucideIcons.playCircle, label: 'Vidéos'),
            CmNavItem(
                icon: LucideIcons.messageCircle,
                label: 'Messages',
                badge: unread),
            const CmNavItem(
                icon: LucideIcons.wallet, label: 'Wallet'),
            const CmNavItem(icon: LucideIcons.user, label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

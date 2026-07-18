import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cm_components.dart';
import '../chat/chat_hub_page.dart';
import '../feed/video_feed_tab.dart';
import 'buyer_catalog_page.dart';
import 'buyer_home_page.dart';
import 'buyer_profile_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BuyerShell extends StatefulWidget {
  const BuyerShell({super.key});

  @override
  State<BuyerShell> createState() => _BuyerShellState();
}

class _BuyerShellState extends State<BuyerShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
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
          children: [
            const BuyerHomePage(),
            const BuyerCatalogPage(),
            VideoFeedTab(active: _index == 2),
            const ChatHubPage(),
            const BuyerProfilePage(),
          ],
        ),
        bottomNavigationBar: CmBottomNav(
          currentIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          items: const [
            CmNavItem(icon: LucideIcons.home, label: 'Accueil'),
            CmNavItem(icon: LucideIcons.layoutGrid, label: 'Catalogue'),
            CmNavItem(icon: LucideIcons.playCircle, label: 'Vidéos'),
            CmNavItem(icon: LucideIcons.messageCircle, label: 'Messages'),
            CmNavItem(icon: LucideIcons.user, label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

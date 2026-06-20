import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cm_components.dart';
import '../chat/chat_hub_page.dart';
import '../feed/video_feed_tab.dart';
import 'buyer_catalog_page.dart';
import 'buyer_home_page.dart';
import 'buyer_profile_page.dart';

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
          children: const [
            BuyerHomePage(),
            BuyerCatalogPage(),
            VideoFeedTab(),
            ChatHubPage(),
            BuyerProfilePage(),
          ],
        ),
        bottomNavigationBar: CmBottomNav(
          currentIndex: _index,
          onSelect: (i) => setState(() => _index = i),
          items: const [
            CmNavItem(icon: Icons.home_outlined, label: 'Accueil'),
            CmNavItem(icon: Icons.grid_view_outlined, label: 'Catalogue'),
            CmNavItem(icon: Icons.play_circle_outline, label: 'Vidéos'),
            CmNavItem(icon: Icons.chat_bubble_outline, label: 'Messages'),
            CmNavItem(icon: Icons.person_outline, label: 'Profil'),
          ],
        ),
      ),
    );
  }
}

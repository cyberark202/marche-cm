import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_theme.dart';
import 'buyer_store.dart';

class BuyerDashboardPage extends StatelessWidget {
  const BuyerDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final existingStore = Provider.of<BuyerStore?>(context, listen: false);
    if (existingStore != null) {
      return const _BuyerHomeContent();
    }
    return ChangeNotifierProvider(
      create: (_) => BuyerStore(),
      child: const _BuyerHomeContent(),
    );
  }
}

class _BuyerHomeContent extends StatelessWidget {
  const _BuyerHomeContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildSearchBar()),
            SliverToBoxAdapter(child: _buildWalletCard()),
            SliverToBoxAdapter(child: _buildCategories()),
            SliverToBoxAdapter(child: _buildPromoBanner()),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Color(0xFFF5B400),
            child: Text(
              "AK",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Bonjour,",
                style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
              ),
              Text(
                "Awa Kamga CM",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F1F1A),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, color: Color(0xFF666666)),
            onPressed: () {},
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Color(0xFF666666)),
                onPressed: () {},
              ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5484D),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      "3",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5DECC)),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 12),
                  Icon(Icons.search, color: Color(0xFF9E9E9E), size: 20),
                  SizedBox(width: 8),
                  Text(
                    "Rechercher huile, riz, ciment…",
                    style: TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppPalette.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F7A4F), Color(0xFF063D27)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: AppPalette.shadowStrong,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                "MON PORTEFEUILLE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
              Spacer(),
              Icon(Icons.credit_card_outlined, color: Colors.white, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            "1 248 500 FCFA",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF5B400),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {},
                    child: const Text(
                      "+ Recharger",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white, width: 1.4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {},
                    child: const Text(
                      "→ Envoyer",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    const categories = [
      (_CategoryData(icon: Icons.restaurant_outlined, label: "Alimentation")),
      (_CategoryData(icon: Icons.checkroom_outlined, label: "Textile")),
      (_CategoryData(icon: Icons.electrical_services_outlined, label: "Électro")),
      (_CategoryData(icon: Icons.face_retouching_natural_outlined, label: "Beauté")),
      (_CategoryData(icon: Icons.construction_outlined, label: "BTP")),
      (_CategoryData(icon: Icons.agriculture_outlined, label: "Agro")),
      (_CategoryData(icon: Icons.public_outlined, label: "Import")),
      (_CategoryData(icon: Icons.handshake_outlined, label: "RFQ B2B")),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Catégories",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F1F1A),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: categories
                .map((cat) => _CategoryItem(data: cat))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF5B400), Color(0xFFFFC940)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "PROMO RAMADAN",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "-20 % sur les sacs de riz de 50 kg",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Jusqu'au 30 mai · 12 fournisseurs partenaires",
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3A3A2A),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.emoji_events_outlined,
            size: 48,
            color: const Color(0xFFB8860B).withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }
}

class _CategoryData {
  final IconData icon;
  final String label;

  const _CategoryData({required this.icon, required this.label});
}

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({required this.data});

  final _CategoryData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppPalette.primarySoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: AppPalette.primary, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF444444),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/driver_theme.dart';

class TrackingPage extends StatelessWidget {
  final String shipmentId;
  const TrackingPage({super.key, required this.shipmentId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DriverPalette.bg,
      appBar: AppBar(
        title: const Text('Suivi GPS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.navigation_outlined),
            tooltip: 'Ouvrir dans Maps',
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFFE8F5E9),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Map placeholder
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: DriverPalette.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.map_outlined,
                            size: 40, color: DriverPalette.primary),
                      ),
                      const SizedBox(height: 16),
                      const Text('Carte GPS',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                              color: DriverPalette.textPrimary)),
                      const SizedBox(height: 8),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Intégrez google_maps_flutter ou mapbox_maps pour afficher la carte en temps réel.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                  // Driver position marker (simulated)
                  Positioned(
                    bottom: 120,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: DriverPalette.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: DriverPalette.primary.withValues(alpha: 0.4),
                              blurRadius: 12, spreadRadius: 2),
                        ],
                      ),
                      child: const Icon(Icons.local_shipping, color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Position GPS active',
                      style: TextStyle(fontSize: 13, color: DriverPalette.textSecondary)),
                  const Spacer(),
                  Text('Livraison #$shipmentId',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: DriverPalette.textPrimary)),
                ]),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: FilledButton(
                    onPressed: () => context.push('/active/otp/$shipmentId'),
                    child: const Text('Valider la livraison',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

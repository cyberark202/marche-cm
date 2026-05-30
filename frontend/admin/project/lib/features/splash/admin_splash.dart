import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Screen 01 — Splash / brand intro for the admin console.
class AdminSplash extends StatefulWidget {
  const AdminSplash({super.key, required this.onCompleted});
  final VoidCallback onCompleted;

  @override
  State<AdminSplash> createState() => _AdminSplashState();
}

class _AdminSplashState extends State<AdminSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    Future.delayed(const Duration(milliseconds: 1900), () {
      if (mounted) widget.onCompleted();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppPalette.gradientHero),
        child: Center(
          child: FadeTransition(
            opacity: _c,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                  ),
                  child: const Icon(Icons.shield_moon_outlined,
                      size: 56, color: Colors.white),
                ),
                const SizedBox(height: 22),
                const Text('Marché.cm',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5)),
                const SizedBox(height: 6),
                Text('CONSOLE D’ADMINISTRATION',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 12,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 34),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor:
                        AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.9)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Connexion sécurisée…',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

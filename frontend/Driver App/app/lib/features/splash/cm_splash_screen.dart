import 'package:flutter/material.dart';

/// Splash screen partagé Market CM (repris de l'app Clients) pour une identité
/// visuelle cohérente entre toutes les applications.
class CmSplashScreen extends StatefulWidget {
  const CmSplashScreen({super.key, this.onCompleted, this.holdMs = 1800});

  final VoidCallback? onCompleted;
  final int holdMs;

  @override
  State<CmSplashScreen> createState() => _CmSplashScreenState();
}

class _CmSplashScreenState extends State<CmSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main;
  late final AnimationController _pulse;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _loaderFade;

  @override
  void initState() {
    super.initState();

    _main = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: widget.holdMs),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
      ),
    );
    _titleFade = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.45, 0.75, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _main,
        curve: const Interval(0.45, 0.78, curve: Curves.easeOutCubic),
      ),
    );
    _taglineFade = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
    );
    _loaderFade = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _main.forward();
    _main.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted?.call();
      }
    });
  }

  @override
  void dispose() {
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF063D27), Color(0xFF0F7A4F)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Positioned(
            top: 60,
            left: 24,
            child: Icon(
              Icons.star_outline,
              color: Colors.white.withValues(alpha: 0.18),
              size: 64,
            ),
          ),
          Positioned(
            top: 120,
            right: 18,
            child: Icon(
              Icons.star_outline,
              color: Colors.white.withValues(alpha: 0.22),
              size: 48,
            ),
          ),
          Positioned(
            bottom: 180,
            left: 12,
            child: Icon(
              Icons.star_outline,
              color: Colors.white.withValues(alpha: 0.15),
              size: 80,
            ),
          ),
          Positioned(
            bottom: 100,
            right: 30,
            child: Icon(
              Icons.star_outline,
              color: Colors.white.withValues(alpha: 0.20),
              size: 56,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _main,
                    builder: (_, __) {
                      return Transform.scale(
                        scale: _logoScale.value,
                        child: Opacity(
                          opacity: _logoFade.value,
                          child: _SimpleLogo(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  FadeTransition(
                    opacity: _titleFade,
                    child: SlideTransition(
                      position: _titleSlide,
                      child: const Text(
                        "Marché.cm",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: const Text(
                      "LE MARCHÉ CENTRAL DU CAMEROUN",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        letterSpacing: 2.0,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _loaderFade,
                    child: const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _loaderFade,
                    child: const Text(
                      "Connexion sécurisée...",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimpleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      height: 100,
      child: Stack(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.store_mall_directory,
              size: 48,
              color: Color(0xFF0F7A4F),
            ),
          ),
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF5B400),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF5B400).withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.star,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

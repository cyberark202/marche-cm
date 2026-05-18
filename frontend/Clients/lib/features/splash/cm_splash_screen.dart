import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_icons.dart';
import '../../core/app_theme.dart';

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
  late final Animation<double> _flagProgress;
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
    _flagProgress = CurvedAnimation(
      parent: _main,
      curve: const Interval(0.25, 0.75, curve: Curves.easeInOutCubic),
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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF6F8FB),
                  Color(0xFFEEF6F3),
                  Color(0xFFE0F2EC),
                ],
              ),
            ),
          ),
          _AnimatedBackdropBlobs(listenable: _pulse),
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
                          child: _LogoCrest(flagProgress: _flagProgress.value),
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
                        "Central Market",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.text,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: const Text(
                      "La marketplace B2B2C du Cameroun",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppPalette.textMuted,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FadeTransition(
                    opacity: _loaderFade,
                    child: const _ChasingDotsLoader(),
                  ),
                  const SizedBox(height: 24),
                  FadeTransition(
                    opacity: _loaderFade,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          AppIcons.shield,
                          size: 13,
                          color: AppPalette.textMuted.withValues(alpha: 0.65),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "Connexion securisee",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppPalette.textMuted.withValues(alpha: 0.65),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
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

class _AnimatedBackdropBlobs extends StatelessWidget {
  const _AnimatedBackdropBlobs({required this.listenable});

  final Animation<double> listenable;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: listenable,
      builder: (_, __) {
        final t = listenable.value;
        return Stack(
          children: [
            Positioned(
              top: 80 + (t * 20),
              right: -60,
              child: _Blob(
                size: 260,
                color: AppPalette.cmGreen.withValues(alpha: 0.12),
              ),
            ),
            Positioned(
              top: 260 - (t * 30),
              left: -80,
              child: _Blob(
                size: 220,
                color: AppPalette.cmYellow.withValues(alpha: 0.1),
              ),
            ),
            Positioned(
              bottom: 140 + (t * 25),
              right: -40,
              child: _Blob(
                size: 200,
                color: AppPalette.cmRed.withValues(alpha: 0.08),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}

class _LogoCrest extends StatelessWidget {
  const _LogoCrest({required this.flagProgress});
  final double flagProgress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      height: 140,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  AppPalette.primary.withValues(alpha: 0.06),
                  AppPalette.primary.withValues(alpha: 0.22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(
                color: AppPalette.primary.withValues(alpha: 0.12),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppPalette.primary.withValues(alpha: 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
          ),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: AppPalette.shadowMedium,
            ),
            alignment: Alignment.center,
            child: ShaderMask(
              shaderCallback: (rect) {
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: [
                    0.0,
                    0.33 * flagProgress,
                    0.66 * flagProgress,
                    flagProgress,
                  ],
                  colors: const [
                    AppPalette.cmGreen,
                    AppPalette.cmGreen,
                    AppPalette.cmRed,
                    AppPalette.cmYellow,
                  ],
                ).createShader(rect);
              },
              blendMode: BlendMode.srcATop,
              child: const Text(
                "CM",
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1,
                  height: 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Transform.translate(
              offset: const Offset(4, -4),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppPalette.cmYellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppPalette.cmYellow.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  AppIcons.zap,
                  size: 15,
                  color: AppPalette.cmRed,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChasingDotsLoader extends StatefulWidget {
  const _ChasingDotsLoader();

  @override
  State<_ChasingDotsLoader> createState() => _ChasingDotsLoaderState();
}

class _ChasingDotsLoaderState extends State<_ChasingDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Stack(
            children: List.generate(3, (i) {
              const colors = [
                AppPalette.cmGreen,
                AppPalette.cmRed,
                AppPalette.cmYellow,
              ];
              final phase = (_controller.value + i * 0.25) % 1.0;
              final sineY = math.sin(phase * math.pi * 2) * 4;
              final sineScale = 0.8 + math.sin(phase * math.pi * 2) * 0.25;
              return Positioned(
                left: 10 + i * 22.0,
                top: 4 + sineY,
                child: Transform.scale(
                  scale: sineScale,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: colors[i],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colors[i].withValues(alpha: 0.45),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

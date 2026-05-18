import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _prefKey = 'escrow_onboarding_seen_v1';

Future<bool> hasSeenEscrowOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_prefKey) ?? false;
}

Future<void> markEscrowOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_prefKey, true);
}

/// Shows the escrow onboarding if the user hasn't seen it yet.
/// Call this before the first transaction flow.
Future<void> showEscrowOnboardingIfNeeded(BuildContext context) async {
  final seen = await hasSeenEscrowOnboarding();
  if (seen || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const EscrowOnboardingPage(),
    ),
  );
}

class EscrowOnboardingPage extends StatefulWidget {
  const EscrowOnboardingPage({super.key});

  @override
  State<EscrowOnboardingPage> createState() => _EscrowOnboardingPageState();
}

class _EscrowOnboardingPageState extends State<EscrowOnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.lock_outlined,
      iconColor: Color(0xFF1E8E4B),
      title: 'Vos paiements sont protégés',
      body:
          'Quand vous passez commande, votre argent n\'est pas envoyé directement au vendeur — '
          'il est placé dans un compte sécurisé sur notre plateforme.',
      accent: Color(0xFFE8F5EE),
    ),
    _Slide(
      icon: Icons.security_outlined,
      iconColor: Color(0xFF1565C0),
      title: 'Vos fonds restent sécurisés',
      body:
          'Le vendeur ne reçoit rien tant que vous n\'avez pas confirmé la bonne réception de votre commande. '
          'En cas de problème, vos fonds vous sont restitués.',
      accent: Color(0xFFE3F2FD),
    ),
    _Slide(
      icon: Icons.verified_outlined,
      iconColor: Color(0xFFE65100),
      title: 'Vous confirmez, le vendeur est payé',
      body:
          'Une fois votre commande reçue et conforme, vous appuyez sur "Confirmer la livraison". '
          'Le vendeur est payé immédiatement. Simple, rapide, sécurisé.',
      accent: Color(0xFFFFF3E0),
    ),
  ];

  void _next() {
    if (_page < _slides.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _finish() async {
    await markEscrowOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_page];
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: slide.accent,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Ignorer',
                    style: TextStyle(color: Colors.black45)),
              ),
            ),

            // Slides
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),

            // Dot indicators
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? slide.iconColor : Colors.black26,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),

            // Action button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: slide.iconColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _next,
                  child: Text(
                    isLast ? 'Commencer' : 'Suivant',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: slide.iconColor.withValues(alpha: 0.2),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(slide.icon, size: 56, color: slide.iconColor),
          ),
          const SizedBox(height: 40),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final Color accent;
  const _Slide({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    required this.accent,
  });
}

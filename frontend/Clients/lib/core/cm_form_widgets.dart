import 'package:flutter/material.dart';

/// UI polish réutilisable inspiré de la référence b2c.
///
/// - [CmPasswordStrength] : jauge de robustesse du mot de passe en direct.
/// - [CmShimmer]          : placeholder animé pour les états de chargement.

/// Barre de force du mot de passe (faible → excellent) affichée sous le champ.
class CmPasswordStrength extends StatelessWidget {
  const CmPasswordStrength({super.key, required this.password});

  final String password;

  /// Score 0..4 selon longueur + variété de caractères.
  int get _score {
    final p = password;
    if (p.isEmpty) return 0;
    var s = 0;
    if (p.length >= 8) s++;
    if (p.length >= 12) s++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) s++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) s++;
    return s.clamp(0, 4);
  }

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final score = _score;
    const labels = ['Très faible', 'Faible', 'Moyen', 'Bon', 'Excellent'];
    const colors = [
      Color(0xFFDC2626),
      Color(0xFFF97316),
      Color(0xFFF59E0B),
      Color(0xFF22C55E),
      Color(0xFF15803D),
    ];
    final color = colors[score];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              final active = i < score;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: active ? color : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 5),
          Text(
            'Robustesse : ${labels[score]}',
            style: TextStyle(
                fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Placeholder animé (effet « shimmer ») pour les listes/cartes en chargement.
class CmShimmer extends StatefulWidget {
  const CmShimmer({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<CmShimmer> createState() => _CmShimmerState();
}

class _CmShimmerState extends State<CmShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1 - 2 * (1 - t), 0),
              end: Alignment(1 - 2 * (1 - t), 0),
              colors: const [
                Color(0xFFEDEFF3),
                Color(0xFFF7F8FA),
                Color(0xFFEDEFF3),
              ],
              stops: const [0.25, 0.5, 0.75],
            ),
          ),
        );
      },
    );
  }
}

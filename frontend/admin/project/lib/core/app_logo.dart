import 'package:flutter/material.dart';

class MarcheLogo extends StatelessWidget {
  final double size;
  final bool withWordmark;
  final bool mono;
  final bool light;

  const MarcheLogo({
    super.key,
    this.size = 48.0,
    this.withWordmark = false,
    this.mono = false,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget logoIcon = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarcheLogoPainter(mono: mono, light: light),
      ),
    );

    if (!withWordmark) return logoIcon;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoIcon,
        SizedBox(width: size * 0.24),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                text: "Marché",
                style: TextStyle(
                  fontFamily: 'Plus Jakarta Sans',
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.52,
                  letterSpacing: -0.02,
                  color: light ? Colors.white : const Color(0xFF0E1F18),
                ),
                children: const [
                  TextSpan(
                    text: ".",
                    style: TextStyle(color: Color(0xFFF5B400)),
                  ),
                ],
              ),
            ),
            Text(
              "CENTRAL MARKET",
              style: TextStyle(
                fontFamily: 'Plus Jakarta Sans',
                fontWeight: FontWeight.w700,
                fontSize: size * 0.22,
                letterSpacing: 1.5,
                color: light ? Colors.white70 : const Color(0xFF0F7A4F),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MarcheLogoPainter extends CustomPainter {
  final bool mono;
  final bool light;

  _MarcheLogoPainter({required this.mono, required this.light});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final w = size.width;
    final h = size.height;

    // Background Shield (rounded square)
    final bgGradient = LinearGradient(
      colors: mono
          ? [const Color(0xFF0E1F18), Colors.black]
          : [const Color(0xFF0F7A4F), const Color(0xFF063D27)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 13 / 48),
    );
    paint.shader = bgGradient.createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(bgRect, paint);
    paint.shader = null;

    // Sunrise Halo (circle)
    final sunColor = mono
        ? Colors.white.withValues(alpha: 0.18)
        : const Color(0xFFF5B400).withValues(alpha: 0.22);
    paint.color = sunColor;
    canvas.drawCircle(Offset(w * 24 / 48, h * 34 / 48), w * 16 / 48, paint);

    // Peak Gradient (Snow)
    final peakGradient = LinearGradient(
      colors: [Colors.white, Colors.white.withValues(alpha: 0.88)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    // M Mountains path
    final peakPath = Path()
      ..moveTo(w * 5 / 48, h * 40 / 48)
      ..lineTo(w * 5 / 48, h * 23 / 48)
      ..lineTo(w * 14 / 48, h * 14 / 48)
      ..lineTo(w * 24 / 48, h * 26 / 48)
      ..lineTo(w * 34 / 48, h * 14 / 48)
      ..lineTo(w * 43 / 48, h * 23 / 48)
      ..lineTo(w * 43 / 48, h * 40 / 48)
      ..close();

    paint.shader = peakGradient.createShader(Rect.fromLTWH(0, h * 14 / 48, w, h * 26 / 48));
    canvas.drawPath(peakPath, paint);
    paint.shader = null;

    // Valley shadow (depth)
    final shadowColor = mono
        ? Colors.black.withValues(alpha: 0.22)
        : const Color(0xFF063D27).withValues(alpha: 0.22);
    paint.color = shadowColor;
    final shadowPath = Path()
      ..moveTo(w * 14 / 48, h * 14 / 48)
      ..lineTo(w * 24 / 48, h * 26 / 48)
      ..lineTo(w * 34 / 48, h * 14 / 48)
      ..lineTo(w * 29 / 48, h * 18.5 / 48)
      ..lineTo(w * 24 / 48, h * 23 / 48)
      ..lineTo(w * 19 / 48, h * 18.5 / 48)
      ..close();
    canvas.drawPath(shadowPath, paint);

    // Snow caps detail (semi-transparent overlays)
    paint.color = Colors.white.withValues(alpha: 0.6);
    final cap1 = Path()
      ..moveTo(w * 11 / 48, h * 18 / 48)
      ..lineTo(w * 14 / 48, h * 14 / 48)
      ..lineTo(w * 17 / 48, h * 17.5 / 48)
      ..lineTo(w * 15 / 48, h * 19 / 48)
      ..lineTo(w * 13 / 48, h * 18 / 48)
      ..close();
    canvas.drawPath(cap1, paint);

    final cap2 = Path()
      ..moveTo(w * 31 / 48, h * 17.5 / 48)
      ..lineTo(w * 34 / 48, h * 14 / 48)
      ..lineTo(w * 37 / 48, h * 18 / 48)
      ..lineTo(w * 35 / 48, h * 18 / 48)
      ..lineTo(w * 33 / 48, h * 19 / 48)
      ..close();
    canvas.drawPath(cap2, paint);

    // Cameroon Flag 5-point Star
    final starColor = mono ? Colors.white : const Color(0xFFF5B400);
    paint.color = starColor;
    paint.style = PaintingStyle.fill;

    final starPath = Path()
      ..moveTo(w * 24 / 48, h * 4 / 48)
      ..lineTo(w * 25.6 / 48, h * 8.0 / 48)
      ..lineTo(w * 29.9 / 48, h * 8.4 / 48)
      ..lineTo(w * 26.6 / 48, h * 11.2 / 48)
      ..lineTo(w * 27.5 / 48, h * 15.4 / 48)
      ..lineTo(w * 24 / 48, h * 13.1 / 48)
      ..lineTo(w * 20.5 / 48, h * 15.4 / 48)
      ..lineTo(w * 21.4 / 48, h * 11.2 / 48)
      ..lineTo(w * 18.1 / 48, h * 8.4 / 48)
      ..lineTo(w * 22.4 / 48, h * 8.0 / 48)
      ..close();
    canvas.drawPath(starPath, paint);

    // Star stroke outline
    final strokePaint = Paint()
      ..color = mono ? Colors.white : const Color(0xFFC68F00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.4 / 48
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(starPath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _MarcheLogoPainter oldDelegate) {
    return oldDelegate.mono != mono || oldDelegate.light != light;
  }
}

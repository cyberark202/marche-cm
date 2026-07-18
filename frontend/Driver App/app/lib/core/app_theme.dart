import 'package:flutter/material.dart';

import 'theme/driver_theme.dart';

class AppPalette {
  AppPalette._();

  static const Color primary = T.primary;
  static const Color primaryDark = T.primaryDark;
  static const Color primarySoft = T.primarySoft;

  static const Color accent = T.accent;
  static const Color accentDark = T.accentDark;
  static const Color accentSoft = T.accentSoft;

  static const Color secondary = T.coral;
  static const Color secondarySoft = T.coralSoft;

  static const Color infoSoft = Color(0xFFE0E7FF);

  static const Color text = T.ink;
  static const Color textMuted = T.ink3;

  static const Color card = T.surface;
  static const Color border = T.line;
  static const Color borderSoft = T.line2;
  static const Color bgSoft = T.surface2;
  static const Color bgDeep = T.surface3;

  static List<BoxShadow> shadowSoft = T.shadowSm;
}

class AppRadii {
  AppRadii._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

class AppDurations {
  AppDurations._();
  static const Duration instant = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 240);
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Marché CM — Design tokens (fidèles à theme.jsx)
/// Palette camerounaise : forest green + sunburst amber + coral flag-red
class T {
  // Brand
  static const Color primary     = Color(0xFF0F7A4F);
  static const Color primaryDark = Color(0xFF0A5A3A);
  static const Color primaryDeep = Color(0xFF063D27);
  static const Color primarySoft = Color(0xFFE6F2EC);
  static const Color primaryTint = Color(0xFFF2F9F5);

  static const Color accent      = Color(0xFFF5B400);
  static const Color accentDark  = Color(0xFFC68F00);
  static const Color accentSoft  = Color(0xFFFEF4D6);

  static const Color coral       = Color(0xFFE5484D);
  static const Color coralSoft   = Color(0xFFFEECEC);

  // Surfaces (warm cream — daylight africain)
  static const Color bg       = Color(0xFFFAF7F0);
  static const Color surface  = Color(0xFFFFFFFF);
  static const Color surface2 = Color(0xFFF1ECDE);
  static const Color surface3 = Color(0xFFE8E2D2);

  // Ink
  static const Color ink  = Color(0xFF0E1F18);
  static const Color ink2 = Color(0xFF2D3D36);
  static const Color ink3 = Color(0xFF5C6B64);
  static const Color ink4 = Color(0xFF8F9C96);

  // Lines
  static const Color line  = Color(0xFFE5DECC);
  static const Color line2 = Color(0xFFEDE7D6);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color info    = Color(0xFF2563EB);
  static const Color danger  = Color(0xFFDC2626);

  // Gradients
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [primary, primaryDeep],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Gradient spécifique livreur (amber chaud)
  static const LinearGradient gradientDriver = LinearGradient(
    colors: [Color(0xFFC68426), Color(0xFF8E5A00)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientDriverHeader = LinearGradient(
    colors: [Color(0xFFC68426), Color(0xFF8E5A00)],
    begin: Alignment(0, -1),
    end: Alignment(0.5, 1),
  );

  // Radii
  static const double rSm  = 8;
  static const double r    = 12;
  static const double rLg  = 18;
  static const double rXl  = 24;
  static const double rFull = 999;

  // Shadows
  static List<BoxShadow> shadowSm = [
    BoxShadow(
      color: const Color(0xFF0E1F18).withValues(alpha: 0.06),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];
  static List<BoxShadow> shadowMd = [
    BoxShadow(
      color: const Color(0xFF0E1F18).withValues(alpha: 0.08),
      blurRadius: 12,
      spreadRadius: -2,
      offset: const Offset(0, 4),
    ),
  ];
  static List<BoxShadow> shadowBrand = [
    BoxShadow(
      color: const Color(0xFF0F7A4F).withValues(alpha: 0.45),
      blurRadius: 22,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];
  static List<BoxShadow> shadowAccent = [
    BoxShadow(
      color: const Color(0xFFF5B400).withValues(alpha: 0.45),
      blurRadius: 22,
      spreadRadius: -6,
      offset: const Offset(0, 8),
    ),
  ];
}

/// Alias lisibles dans les widgets
class DriverPalette {
  static const Color primary     = T.primary;
  static const Color primaryDark = T.primaryDark;
  static const Color primaryDeep = T.primaryDeep;
  static const Color primarySoft = T.primarySoft;
  static const Color secondary   = T.accent;
  static const Color secondaryDark = T.accentDark;
  static const Color bg          = T.bg;
  static const Color surface     = T.surface;
  static const Color border      = T.line;
  static const Color textPrimary = T.ink;
  static const Color textSecondary = T.ink2;
  static const Color textMuted   = T.ink3;
  static const Color success     = T.success;
  static const Color danger      = T.danger;
  static const Color warning     = T.warning;
  static const Color info        = T.info;
  static const Color coral       = T.coral;
  static const Color accent      = T.accent;
  static const Color accentDark  = T.accentDark;
  static const Color accentSoft  = T.accentSoft;

  static const LinearGradient driverHeaderGradient = T.gradientDriverHeader;
}

class DriverRadii {
  static const double xs   = T.rSm;
  static const double sm   = T.r;
  static const double md   = T.rLg;
  static const double lg   = T.rXl;
  static const double xl   = 28;
  static const double pill = T.rFull;
}

class DriverTheme {
  static ThemeData light() {
    const textTheme = TextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: T.primary,
        onPrimary: Colors.white,
        primaryContainer: T.primarySoft,
        onPrimaryContainer: T.primaryDark,
        secondary: T.accent,
        onSecondary: Color(0xFF1a0f00),
        surface: T.surface,
        onSurface: T.ink,
        error: T.danger,
        onError: Colors.white,
        outline: T.line,
        outlineVariant: T.line2,
      ),
      scaffoldBackgroundColor: T.bg,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: textTheme.copyWith(
        displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32, fontWeight: FontWeight.w800,
            letterSpacing: -0.8, color: T.ink),
        headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 25, fontWeight: FontWeight.w700,
            letterSpacing: -0.4, color: T.ink),
        headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20, fontWeight: FontWeight.w800,
            letterSpacing: -0.3, color: T.ink),
        titleLarge: GoogleFonts.plusJakartaSans(
            fontSize: 17, fontWeight: FontWeight.w700, color: T.ink),
        titleMedium: GoogleFonts.plusJakartaSans(
            fontSize: 15, fontWeight: FontWeight.w700, color: T.ink),
        titleSmall: GoogleFonts.plusJakartaSans(
            fontSize: 13.5, fontWeight: FontWeight.w600, color: T.ink),
        bodyLarge: GoogleFonts.plusJakartaSans(fontSize: 15, color: T.ink),
        bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: T.ink2),
        bodySmall: GoogleFonts.plusJakartaSans(fontSize: 12, color: T.ink3),
        labelLarge: GoogleFonts.plusJakartaSans(
            fontSize: 14.5, fontWeight: FontWeight.w700, color: T.ink),
        labelMedium: GoogleFonts.plusJakartaSans(
            fontSize: 12.5, fontWeight: FontWeight.w600, color: T.ink2),
        labelSmall: GoogleFonts.plusJakartaSans(
            fontSize: 10.5, fontWeight: FontWeight.w600, color: T.ink3),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: T.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 17, fontWeight: FontWeight.w700, color: T.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: T.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 15),
          elevation: 0,
          minimumSize: const Size(0, 52),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: T.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, fontSize: 15),
          minimumSize: const Size(0, 52),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: T.ink,
          side: const BorderSide(color: T.line, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 22),
          textStyle: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w600, fontSize: 15),
          minimumSize: const Size(0, 52),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: T.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: T.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: T.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: T.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.plusJakartaSans(color: T.ink2, fontSize: 14),
        hintStyle: GoogleFonts.plusJakartaSans(color: T.ink3, fontSize: 14),
        prefixIconColor: T.ink3,
      ),
      cardTheme: CardThemeData(
        color: T.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          side: const BorderSide(color: T.line),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: T.surface2,
        selectedColor: T.ink,
        labelStyle: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DriverRadii.pill)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: T.surface,
        indicatorColor: T.primarySoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return GoogleFonts.plusJakartaSans(
            fontSize: 10.5,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
            color: sel ? T.primary : T.ink3,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            color: sel ? T.primary : T.ink3,
            size: 22,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: T.line2, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: T.ink,
        contentTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 13, color: Colors.white),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DriverRadii.sm)),
        actionTextColor: T.accent,
      ),
    );
  }
}

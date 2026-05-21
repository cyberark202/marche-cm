import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DriverPalette {
  // Brand — forest green + amber
  static const Color primary = Color(0xFF1A6B3A);
  static const Color primaryLight = Color(0xFF22883F);
  static const Color primaryDark = Color(0xFF145230);
  static const Color secondary = Color(0xFFF5A623);
  static const Color secondaryDark = Color(0xFFE08E0B);

  // Status
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF2563EB);

  // Neutral
  static const Color bg = Color(0xFFF0F7F2);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFD1E8D9);
  static const Color textPrimary = Color(0xFF0F2318);
  static const Color textSecondary = Color(0xFF4A6B54);
  static const Color textMuted = Color(0xFF8FAF98);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF1A6B3A), Color(0xFF22883F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFF145230), Color(0xFF1A6B3A)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Shadows
  static List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: const Color(0xFF1A6B3A).withValues(alpha: 0.08),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: const Color(0xFF0F2318).withValues(alpha: 0.10),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];
}

class DriverRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double pill = 999;
}

class DriverTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: DriverPalette.primary,
        primary: DriverPalette.primary,
        secondary: DriverPalette.secondary,
        surface: DriverPalette.surface,
        error: DriverPalette.danger,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: DriverPalette.bg,
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
        displayLarge: GoogleFonts.poppins(
            fontSize: 32, fontWeight: FontWeight.w800, color: DriverPalette.textPrimary),
        headlineMedium: GoogleFonts.poppins(
            fontSize: 24, fontWeight: FontWeight.w700, color: DriverPalette.textPrimary),
        titleLarge: GoogleFonts.poppins(
            fontSize: 18, fontWeight: FontWeight.w700, color: DriverPalette.textPrimary),
        titleMedium: GoogleFonts.poppins(
            fontSize: 16, fontWeight: FontWeight.w600, color: DriverPalette.textPrimary),
        bodyLarge: GoogleFonts.poppins(fontSize: 15, color: DriverPalette.textPrimary),
        bodyMedium: GoogleFonts.poppins(fontSize: 14, color: DriverPalette.textSecondary),
        bodySmall: GoogleFonts.poppins(fontSize: 12, color: DriverPalette.textMuted),
        labelLarge: GoogleFonts.poppins(
            fontSize: 14, fontWeight: FontWeight.w600, color: DriverPalette.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: DriverPalette.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.poppins(
            fontSize: 18, fontWeight: FontWeight.w700, color: DriverPalette.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DriverPalette.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15),
          elevation: 0,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DriverPalette.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DriverPalette.primary,
          side: const BorderSide(color: DriverPalette.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DriverRadii.sm)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: DriverPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: DriverPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DriverRadii.sm),
          borderSide: const BorderSide(color: DriverPalette.primary, width: 1.5),
        ),
        labelStyle: GoogleFonts.poppins(color: DriverPalette.textSecondary, fontSize: 14),
        hintStyle: GoogleFonts.poppins(color: DriverPalette.textMuted, fontSize: 14),
        prefixIconColor: DriverPalette.primary,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DriverRadii.md),
          side: const BorderSide(color: DriverPalette.border),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFE8F5ED),
        labelStyle: GoogleFonts.poppins(fontSize: 13, color: DriverPalette.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: DriverPalette.primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.poppins(
                fontSize: 11, fontWeight: FontWeight.w600, color: DriverPalette.primary);
          }
          return GoogleFonts.poppins(
              fontSize: 11, color: DriverPalette.textMuted);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DriverPalette.primary, size: 22);
          }
          return const IconThemeData(color: DriverPalette.textMuted, size: 22);
        }),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
      ),
      dividerTheme: const DividerThemeData(color: DriverPalette.border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: GoogleFonts.poppins(fontSize: 13),
      ),
    );
  }
}

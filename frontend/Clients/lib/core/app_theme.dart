import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Design System — Clients (acheteurs)
///
/// Tonalité : marketplace chaleureuse, accueillante, énergique.
/// Palette : vert émeraude (primary), corail (secondary), ambre (accent).
class AppPalette {
  // ── Brand ──────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF0EA877);
  static const Color primaryDark = Color(0xFF067A55);
  static const Color primaryLight = Color(0xFF34D399);
  static const Color primarySoft = Color(0xFFD1FAE5);

  static const Color secondary = Color(0xFFFF7A45);
  static const Color secondaryDark = Color(0xFFE85D2C);
  static const Color secondaryLight = Color(0xFFFFA77E);
  static const Color secondarySoft = Color(0xFFFFE4D6);

  static const Color accent = Color(0xFFFFB020);
  static const Color accentDark = Color(0xFFD9920E);
  static const Color accentSoft = Color(0xFFFFF1CC);

  static const Color accentWarm = Color(0xFFEF4444);

  // ── Status ─────────────────────────────────────────────────────────────
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color success = Color(0xFF10B981);
  static const Color successSoft = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSoft = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF0EA5E9);
  static const Color infoSoft = Color(0xFFE0F2FE);

  // ── Surfaces ───────────────────────────────────────────────────────────
  static const Color bg = Color(0xFFF7FAF8);
  static const Color bgSoft = Color(0xFFEEF5F1);
  static const Color bgDeep = Color(0xFFE0EBE5);
  static const Color card = Colors.white;
  static const Color surfaceElevated = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5EBE8);
  static const Color borderSoft = Color(0xFFF0F4F2);

  // ── Text ───────────────────────────────────────────────────────────────
  static const Color text = Color(0xFF0F1F1A);
  static const Color textMuted = Color(0xFF5C6B65);
  static const Color textFaint = Color(0xFF94A39D);

  // ── Cameroun (drapeau, conservé pour identité) ─────────────────────────
  static const Color cmGreen = Color(0xFF007A3D);
  static const Color cmRed = Color(0xFFCE1126);
  static const Color cmYellow = Color(0xFFFCD116);

  // ── Gradients ──────────────────────────────────────────────────────────
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [Color(0xFF0EA877), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientAccent = LinearGradient(
    colors: [Color(0xFFFF7A45), Color(0xFFFFB020)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientRoyal = LinearGradient(
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientOcean = LinearGradient(
    colors: [Color(0xFF0EA5E9), Color(0xFF0EA877)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientPageLight = LinearGradient(
    colors: [Color(0xFFFFFFFF), Color(0xFFF7FAF8), Color(0xFFEEF5F1)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient gradientHero = LinearGradient(
    colors: [Color(0xFF067A55), Color(0xFF0EA877), Color(0xFF34D399)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows ────────────────────────────────────────────────────────────
  static List<BoxShadow> shadowSoft = [
    BoxShadow(
      color: const Color(0xFF0F1F1A).withValues(alpha: 0.04),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowMedium = [
    BoxShadow(
      color: const Color(0xFF0F1F1A).withValues(alpha: 0.06),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> shadowStrong = [
    BoxShadow(
      color: const Color(0xFF0EA877).withValues(alpha: 0.16),
      blurRadius: 32,
      offset: const Offset(0, 16),
    ),
  ];

  static List<BoxShadow> shadowFloating = [
    BoxShadow(
      color: const Color(0xFF0F1F1A).withValues(alpha: 0.08),
      blurRadius: 28,
      offset: const Offset(0, 14),
    ),
  ];
}

class AppRadii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 22;
  static const double xl = 28;
  static const double xxl = 36;
  static const double pill = 999;
}

class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppDurations {
  static const Duration instant = Duration(milliseconds: 150);
  static const Duration fast = Duration(milliseconds: 240);
  static const Duration medium = Duration(milliseconds: 380);
  static const Duration slow = Duration(milliseconds: 560);
}

class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppPalette.primary,
      onPrimary: Colors.white,
      primaryContainer: AppPalette.primarySoft,
      onPrimaryContainer: AppPalette.primaryDark,
      secondary: AppPalette.secondary,
      onSecondary: Colors.white,
      secondaryContainer: AppPalette.secondarySoft,
      onSecondaryContainer: AppPalette.secondaryDark,
      tertiary: AppPalette.accent,
      onTertiary: Colors.white,
      tertiaryContainer: AppPalette.accentSoft,
      onTertiaryContainer: AppPalette.accentDark,
      error: AppPalette.danger,
      onError: Colors.white,
      errorContainer: AppPalette.dangerSoft,
      onErrorContainer: AppPalette.danger,
      surface: AppPalette.card,
      onSurface: AppPalette.text,
      surfaceContainerHighest: AppPalette.bgSoft,
      outline: AppPalette.border,
      outlineVariant: AppPalette.borderSoft,
    );

    final base = ThemeData(
      useMaterial3: true,
      fontFamily: "Poppins",
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppPalette.bg,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppPalette.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppPalette.text,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      dividerColor: AppPalette.borderSoft,
      iconTheme: const IconThemeData(color: AppPalette.text, size: 22),
      cardTheme: CardThemeData(
        color: AppPalette.card,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppPalette.borderSoft),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        labelStyle: const TextStyle(
          color: AppPalette.textMuted,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(color: AppPalette.textFaint),
        prefixIconColor: AppPalette.textMuted,
        suffixIconColor: AppPalette.textMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppPalette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppPalette.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppPalette.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppPalette.danger, width: 1.6),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppPalette.bgSoft,
        selectedColor: AppPalette.primarySoft,
        side: const BorderSide(color: AppPalette.borderSoft),
        labelStyle: const TextStyle(
          color: AppPalette.text,
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.text,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        actionTextColor: AppPalette.accent,
        elevation: 6,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppPalette.bgDeep,
          disabledForegroundColor: AppPalette.textFaint,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
            letterSpacing: 0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppPalette.primaryDark,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppPalette.text,
          side: const BorderSide(color: AppPalette.border, width: 1.4),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppPalette.primary,
        linearTrackColor: AppPalette.bgSoft,
        circularTrackColor: AppPalette.bgSoft,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppPalette.primary.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppPalette.primary : AppPalette.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? AppPalette.primary : AppPalette.textMuted,
            size: 24,
          );
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        titleTextStyle: const TextStyle(
          color: AppPalette.text,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          color: AppPalette.textMuted,
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.xl),
          ),
        ),
        showDragHandle: true,
        dragHandleColor: AppPalette.border,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppPalette.textMuted,
        titleTextStyle: TextStyle(
          color: AppPalette.text,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: TextStyle(
          color: AppPalette.textMuted,
          fontSize: 12.5,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.lg)),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppPalette.primary,
        unselectedLabelColor: AppPalette.textMuted,
        indicatorColor: AppPalette.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
            TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
      ),
      dividerTheme: const DividerThemeData(
        color: AppPalette.borderSoft,
        thickness: 1,
        space: 1,
      ),
      textTheme: base.textTheme
          .apply(
            bodyColor: AppPalette.text,
            displayColor: AppPalette.text,
          )
          .copyWith(
            displayLarge: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.0,
              height: 1.1,
            ),
            displayMedium: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
            headlineLarge: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              height: 1.2,
            ),
            headlineMedium: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            titleLarge: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            titleMedium: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            titleSmall: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: const TextStyle(
                fontSize: 15, color: AppPalette.text, height: 1.5),
            bodyMedium: const TextStyle(
                fontSize: 14, color: AppPalette.text, height: 1.5),
            bodySmall: const TextStyle(
              fontSize: 12.5,
              color: AppPalette.textMuted,
              height: 1.4,
            ),
            labelLarge: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            labelMedium: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            labelSmall: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppPalette.textMuted,
            ),
          ),
    );
  }
}

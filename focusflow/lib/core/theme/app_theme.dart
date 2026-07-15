import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// FocusFlow — Cognitive Sanctuary Design System
/// Matches the Stitch design tokens exactly.
class AppColors {
  AppColors._();

  // ── Primary ────────────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF004AC6);
  static const Color primaryContainer = Color(0xFF2563EB);
  static const Color primaryFixed = Color(0xFFDBE1FF);
  static const Color primaryFixedDim = Color(0xFFB4C5FF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFFEEEFFF);
  static const Color inversePrimary = Color(0xFFB4C5FF);

  // ── Secondary ──────────────────────────────────────────────────────────────
  static const Color secondary = Color(0xFF505F76);
  static const Color secondaryContainer = Color(0xFFD0E1FB);
  static const Color secondaryFixed = Color(0xFFD3E4FE);
  static const Color secondaryFixedDim = Color(0xFFB7C8E1);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF54647A);

  // ── Tertiary (Success / Energy Green) ────────────────────────────────────
  static const Color tertiary = Color(0xFF006229);
  static const Color tertiaryContainer = Color(0xFF007E37);
  static const Color tertiaryFixed = Color(0xFF6BFF8F);
  static const Color tertiaryFixedDim = Color(0xFF4AE176);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color onTertiaryContainer = Color(0xFFC1FFC5);

  // ── Surface Hierarchy ─────────────────────────────────────────────────────
  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceBright = Color(0xFFF7F9FB);
  static const Color surfaceDim = Color(0xFFD8DADC);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF2F4F6);
  static const Color surfaceContainer = Color(0xFFECEEF0);
  static const Color surfaceContainerHigh = Color(0xFFE6E8EA);
  static const Color surfaceContainerHighest = Color(0xFFE0E3E5);
  static const Color inverseSurface = Color(0xFF2D3133);
  static const Color inverseOnSurface = Color(0xFFEFF1F3);

  // ── On-Surface ────────────────────────────────────────────────────────────
  static const Color onBackground = Color(0xFF191C1E);
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF434655);

  // ── Outline ───────────────────────────────────────────────────────────────
  static const Color outline = Color(0xFF737686);
  static const Color outlineVariant = Color(0xFFC3C6D7);
  // Ghost border = outlineVariant at 15% opacity
  static const Color ghostBorder = Color(0x26C3C6D7);

  // ── Error ─────────────────────────────────────────────────────────────────
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color onErrorContainer = Color(0xFF93000A);

  // ── Warning (Phase 4 progress-bar mid-cap state) ─────────────────────────
  // Material 3 has no built-in warning token; amber-900 + amber-200 keeps
  // the existing red `error` semantically reserved for the cap-exceeded
  // ramp. Phase 4 progress bars use:
  //   fraction 0.0–0.7   → primary   (blue)
  //   fraction 0.7–0.9   → warning   (amber)
  //   fraction 0.9–1.0   → error     (red)
  static const Color warning = Color(0xFFE65100);       // amber-900
  static const Color warningContainer = Color(0xFFFFE0B2); // amber-200

  // ── Gradients ─────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primaryContainer],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [surface, surfaceContainerLow],
  );

  // ── Shadows ───────────────────────────────────────────────────────────────
  static List<BoxShadow> ambientShadow = [
    BoxShadow(
      color: onSurface.withValues(alpha: 0.06),
      blurRadius: 32,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> cardShadow = [
    BoxShadow(
      color: onSurface.withValues(alpha: 0.04),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}

/// Spacing scale (Stitch spacingScale: 2)
class AppSpacing {
  AppSpacing._();
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;
}

/// Border radius tokens
class AppRadius {
  AppRadius._();
  static const double xs = 4.0;
  static const double sm = 8.0;   // roundness: ROUND_EIGHT
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double full = 100.0;

  static BorderRadius get cardRadius => BorderRadius.circular(lg);
  static BorderRadius get buttonRadius => BorderRadius.circular(xl);
  static BorderRadius get inputRadius => BorderRadius.circular(md);
  static BorderRadius get chipRadius => BorderRadius.circular(sm);
}

/// The main FocusFlow ThemeData — Cognitive Sanctuary
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final textTheme = _buildTextTheme();
    return ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
        inversePrimary: AppColors.inversePrimary,
      ),
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onBackground,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
          textStyle: GoogleFonts.manrope(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.2,
          ),
          animationDuration: const Duration(milliseconds: 300),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.ghostBorder, width: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonRadius),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.inputRadius,
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        labelStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        hintStyle: GoogleFonts.inter(color: AppColors.onSurfaceVariant),
        floatingLabelStyle: GoogleFonts.inter(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      dividerTheme: const DividerThemeData(color: Colors.transparent, thickness: 0),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Display — Manrope, tight letter spacing
      displayLarge: GoogleFonts.manrope(
        fontSize: 57,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * 57,
        color: AppColors.onBackground,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * 45,
        color: AppColors.onBackground,
      ),
      displaySmall: GoogleFonts.manrope(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.02 * 36,
        color: AppColors.onBackground,
      ),
      // Headlines
      headlineLarge: GoogleFonts.manrope(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: AppColors.onBackground,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: AppColors.onBackground,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.onBackground,
      ),
      // Titles
      titleLarge: GoogleFonts.manrope(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackground,
      ),
      titleMedium: GoogleFonts.manrope(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackground,
      ),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.onBackground,
      ),
      // Body — Inter
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: AppColors.onBackground,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      ),
      // Labels
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: AppColors.onBackground,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: AppColors.onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}

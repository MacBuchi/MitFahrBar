/// theme.dart – Material-3-Theme der Marke RideBuddy, Light und Dark
/// aus einer Basis.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData lightTheme() => _base(Brightness.light);
ThemeData darkTheme() => _base(Brightness.dark);

ThemeData _base(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        brightness: brightness,
      ).copyWith(
        primary: isDark ? AppColors.brandBright : AppColors.brand,
        surface: isDark ? AppColors.darkBackground : null,
      );

  final text = Typography.material2021(
    platform: TargetPlatform.android,
  ).let(isDark);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Überschriften in der Display-Schrift, alles andere in der Textschrift.
    fontFamily: AppFonts.body,
    textTheme: text.copyWith(
      displayLarge: text.displayLarge?.copyWith(fontFamily: AppFonts.display),
      displayMedium: text.displayMedium?.copyWith(fontFamily: AppFonts.display),
      displaySmall: text.displaySmall?.copyWith(fontFamily: AppFonts.display),
      headlineLarge: text.headlineLarge?.copyWith(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: AppFonts.display,
        fontWeight: FontWeight.w700,
        fontSize: 20,
        letterSpacing: -0.2,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        textStyle: const TextStyle(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.m),
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

extension _TypographyPick on Typography {
  TextTheme let(bool isDark) => isDark ? white : black;
}

/// theme.dart – Material-3-Theme, Light und Dark aus einer Basis.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData lightTheme() => _base(Brightness.light);
ThemeData darkTheme() => _base(Brightness.dark);

ThemeData _base(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.seed,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.xs,
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}

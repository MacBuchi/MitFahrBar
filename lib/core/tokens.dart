/// tokens.dart – Zentrale Design-Tokens. In Screens niemals rohe
/// Farb-/Pixelwerte verwenden, immer diese Klassen bzw. das Theme.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  /// Seed für ColorScheme.fromSeed (Light + Dark).
  static const seed = Color(0xFF2E7D32); // sattes Grün: fair, ökologisch

  /// Status-Farben der Teilnahme-Kacheln (auf colorScheme abgestimmt).
  static const driver = Color(0xFF2E7D32);
  static const passenger = Color(0xFF1565C0);
  static const oneWay = Color(0xFF9A6800);
}

abstract final class AppSpacing {
  AppSpacing._();

  static const xs = 4.0;
  static const s = 8.0;
  static const m = 16.0;
  static const l = 24.0;
  static const xl = 32.0;
}

abstract final class AppRadius {
  AppRadius._();

  static const s = 8.0;
  static const m = 12.0;
  static const l = 20.0;
}

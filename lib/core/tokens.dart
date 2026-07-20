/// tokens.dart – Zentrale Design-Tokens der Marke RideBuddy.
///
/// Quelle: Design-Set „RideBuddy Design Set". Maßgeblich sind die dort
/// gezeigten Farbflächen (Cyan/Teal-Familie); die Bildunterschriften der
/// Palette stammen noch aus einer früheren Lila-Variante und wurden
/// bewusst nicht übernommen.
///
/// In Screens niemals rohe Farb-/Pixelwerte verwenden, immer diese Klassen
/// bzw. das Theme.
library;

import 'package:flutter/material.dart';

abstract final class AppColors {
  AppColors._();

  /// Markenfarbe – Basis des ColorScheme und der Verläufe.
  static const brand = Color(0xFF0891B2);

  /// Heller Markenton, Endpunkt des Verlaufs.
  static const brandBright = Color(0xFF22D3EE);

  /// Zwischenton für Flächen und Hover.
  static const brandLight = Color(0xFF06B6D4);

  /// Akzent für Details (Radnaben, Links auf dunklem Grund).
  static const accent = Color(0xFF67E8F9);

  /// „Eco" – CO₂-Ersparnis und Mitfahren.
  static const eco = Color(0xFF10D98E);

  /// Tiefdunkles Marken-Blauschwarz.
  static const ink = Color(0xFF062028);

  /// Sehr helles Cyan als Papierton.
  static const paper = Color(0xFFECFEFF);

  /// Hintergrund und Flächen der dunklen Markenwelt.
  static const darkBackground = Color(0xFF06171C);
  static const darkSurface = Color(0xFF0B2831);

  /// Zurückhaltender Text auf dunklem Grund.
  static const muted = Color(0xFF6F909A);

  /// Markenverlauf („Motion") – für Logo, Icon und Hero-Flächen.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandBright],
  );

  /// Status der Teilnahme an einer Fahrt.
  static const driver = brand;
  static const passenger = Color(0xFF0F9D6B);
  static const oneWay = Color(0xFFB45309);
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

  /// Kachel-/Icon-Radius der Marke (App-Icon: 46 auf 200 px).
  static const brandTile = 24.0;
}

/// Schriftfamilien der Marke.
abstract final class AppFonts {
  AppFonts._();

  /// Wortmarke und Überschriften.
  static const display = 'SpaceGrotesk';

  /// Fließtext und Bedienelemente.
  static const body = 'Manrope';
}

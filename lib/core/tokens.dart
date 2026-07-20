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

/// Farben der Stimmungs-Gesichter aus dem Design-Set „RideBuddy Smiley Set".
///
/// Die Vorlage ist in oklch notiert, was Flutter nicht kennt; die Werte hier
/// sind die nach sRGB umgerechneten Entsprechungen. Deshalb gilt: **nicht von
/// Hand nachjustieren** — bei einer Änderung im Design-Set neu umrechnen,
/// sonst driftet die Skala auseinander.
///
/// Der Farbton wandert über die Skala von Grün nach Rot; `ink` ist jeweils
/// der dunkle Ton für Augen und Mund desselben Gesichts.
abstract final class AppFace {
  AppFace._();

  static const ecstaticFill = Color(0xFF4AC06C);
  static const ecstaticInk = Color(0xFF004C1A);
  static const happyFill = Color(0xFF87B73A);
  static const happyInk = Color(0xFF2C4700);
  static const goodFill = Color(0xFFBBB326);
  static const goodInk = Color(0xFF4A4400);
  static const neutralFill = Color(0xFFE4B33F);
  static const neutralInk = Color(0xFF5E4300);
  static const mehFill = Color(0xFFE88B0E);
  static const mehInk = Color(0xFF693100);
  static const sadFill = Color(0xFFE56731);
  static const sadInk = Color(0xFF671800);
  static const angryFill = Color(0xFFDB4241);
  static const angryInk = Color(0xFF65000A);

  /// Träne des traurigen Gesichts.
  static const tear = Color(0xFF4BAEED);

  /// „Celebrating" steht außerhalb der Skala: kein Bewertungsschritt,
  /// sondern die Auszeichnung eines Erfolgs.
  static const celebrateFill = Color(0xFFF9DD73);
  static const celebrateInk = Color(0xFF643400);
  static const celebrateTongue = Color(0xFFEC5A63);
  static const confettiGold = Color(0xFFEDCC48);
  static const confettiGreen = Color(0xFF55C975);
  static const confettiRed = Color(0xFFF66D67);
  static const confettiViolet = Color(0xFFDCB8FF);
}

/// Maße der Diagramme (gezeichnet in `core/widgets/charts.dart`).
///
/// Die Daten sind das Einzige, was laut sein darf: dünne Marken, haarfeine
/// Achsen, und getrennt wird durch Fläche statt durch Rahmen.
abstract final class AppChart {
  AppChart._();

  /// Höchste Balkenstärke; was im Raster übrig bleibt, ist bewusst Luft.
  static const barMaxThickness = 20.0;

  /// Abgerundetes Datenende; an der Grundlinie bleibt der Balken eckig.
  static const barEndRadius = 4.0;

  /// Trennung zweier Flächen – in Hintergrundfarbe, nie als Rahmen.
  static const surfaceGap = 2.0;

  /// Grundlinie und Achsen.
  static const hairline = 1.0;

  /// Höhe der Zeichenfläche des Monats-Diagramms.
  static const columnPlotHeight = 104.0;

  /// Zeilenhöhe eines gestapelten Balkens.
  static const stackedBarThickness = 14.0;
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

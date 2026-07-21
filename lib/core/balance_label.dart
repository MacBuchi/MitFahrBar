/// balance_label.dart – Punktestand in Worten.
///
/// „2,5 Punkte" sagt nicht, in welche Richtung sie zeigen. Punkte sind
/// zero-sum: negativ heißt, dass die Gruppe einem noch Fahrten schuldet —
/// genau andersherum, als eine nackte Zahl sich anfühlt. Eine Formulierung
/// für Dashboard und Wochenplaner, damit keine zweite Wahrheit entsteht.
library;

import 'package:intl/intl.dart';

String balanceLabel(double points, NumberFormat format) {
  if (points.abs() < 0.05) return 'ausgeglichen';
  if (points < 0) return 'schuldet ${format.format(points.abs())}';
  return 'hat ${format.format(points)} gut';
}

/// Kompakte Vorzeichen-Schreibweise fürs enge Wochenraster: „+1,5" / „−2" /
/// „0". Das typografische Minus (U+2212) statt Bindestrich — gleiche Breite
/// wie das Plus, die Spalte flattert nicht.
String signedPoints(double points, NumberFormat format) {
  if (points.abs() < 0.05) return '0';
  final value = format.format(points.abs());
  return points < 0 ? '−$value' : '+$value';
}

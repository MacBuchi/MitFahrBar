/// chart_data.dart – Aggregationen für die Diagramme auf der Startseite.
///
/// Bewusst reine Funktionen ohne Flutter-Bezug: dadurch testbar, und die
/// Kennzahlen bleiben – wie überall in der App – berechnet statt gespeichert.
library;

import '../models/trip.dart';

/// Ein Monat der Zeitachse samt Anzahl Fahrten.
class MonthBucket {
  const MonthBucket({
    required this.year,
    required this.month,
    required this.trips,
  });

  final int year;
  final int month;
  final int trips;

  /// Erster Tag des Monats – für die Achsenbeschriftung.
  DateTime get date => DateTime(year, month);
}

/// Fahrten je Monat für die letzten [months] Monate, aufsteigend sortiert.
///
/// Monate ohne Fahrt sind enthalten und stehen auf 0: Die Lücken gehören zum
/// Bild, sonst täuscht die Achse eine gleichmäßige Aktivität vor.
List<MonthBucket> tripsPerMonth(
  List<Trip> trips, {
  int months = 12,
  DateTime? now,
}) {
  if (months <= 0) return const [];

  final today = now ?? DateTime.now();
  final counts = <int, int>{};
  for (final trip in trips) {
    final key = trip.date.year * 12 + (trip.date.month - 1);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final newest = today.year * 12 + (today.month - 1);
  final oldest = newest - (months - 1);
  return [
    for (var key = oldest; key <= newest; key++)
      MonthBucket(
        year: key ~/ 12,
        month: key % 12 + 1,
        trips: counts[key] ?? 0,
      ),
  ];
}

/// Eine Zeile des Teilnahme-Diagramms: wie eine Person unterwegs war.
///
/// Die Reihenfolge der Felder ist zugleich die Stapelreihenfolge und
/// sachlich sortiert danach, wie viel man mitgenommen wurde: 0 / 0,5 / 1,0.
class ParticipationRow {
  const ParticipationRow({
    required this.label,
    required this.driven,
    required this.oneWay,
    required this.ridden,
  });

  final String label;

  /// Tage selbst gefahren.
  final int driven;

  /// Tage nur eine Richtung mitgefahren.
  final int oneWay;

  /// Tage voll mitgefahren.
  final int ridden;

  int get total => driven + oneWay + ridden;
}

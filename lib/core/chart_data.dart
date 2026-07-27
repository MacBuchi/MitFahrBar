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

/// Wie viele Monate das Diagramm abdecken muss, damit die **erste** Fahrt
/// darin liegt (#119).
///
/// Vorher stand das Fenster fest auf zwölf Monaten. Eine Gruppe, die seit
/// Jahren fährt, sah damit nur ihr letztes Jahr.
///
/// Zwei Grenzen, beide nicht kosmetisch:
/// * **Mindestens [floor]**: Eine junge Gruppe bekäme sonst ein gestauchtes
///   Diagramm aus zwei Säulen. Leere Monate gehören ins Bild — dieselbe
///   Begründung wie bei [tripsPerMonth].
/// * **Höchstens [cap]**: Ein einzelnes falsch getipptes Datum weit in der
///   Vergangenheit streckte die Achse sonst dauerhaft, und alle echten Monate
///   quetschten sich in den rechten Rand. (Fahrten in der *Zukunft* fängt
///   [tripsPerMonth] bereits ab, weil es nie über den laufenden Monat
///   hinaus zählt — genau so ein Ausreißer steckt im Erst-Import der Gruppe.)
int monthsToCover(
  List<Trip> trips,
  DateTime now, {
  int floor = 12,
  int cap = 60,
}) {
  final newest = now.year * 12 + (now.month - 1);
  var oldest = newest;
  for (final trip in trips) {
    final key = trip.date.year * 12 + (trip.date.month - 1);
    // Was nach heute liegt, zählt nicht — sonst verlängerte ein Vertipper in
    // die Zukunft das Fenster, obwohl die Fahrt gar nicht gezeichnet wird.
    if (key < oldest) oldest = key;
  }
  return (newest - oldest + 1).clamp(floor, cap);
}

/// Gerundete Werte für die Wertachse, von 0 bis mindestens [maxValue].
///
/// **Beginnt immer bei 0.** Eine abgeschnittene Wertachse verfälscht bei
/// Säulen die Länge — der optische Vergleich ist genau das, wofür die Form
/// gewählt wurde.
///
/// Die Schrittweite ist die kleinste aus 1/2/5/10/20/25/50/…, mit der
/// [count] Schritte über [maxValue] hinauskommen; so stehen an der Achse
/// glatte Zahlen statt krummer Bruchteile des Maximums.
List<int> axisTicks(int maxValue, {int count = 4}) {
  if (count < 1) return const [0];
  if (maxValue <= 0) return [0, 1];

  var magnitude = 1;
  while (true) {
    for (final factor in const [1, 2, 5]) {
      final step = factor * magnitude;
      if (step * count >= maxValue) {
        return [for (var i = 0; i <= count; i++) i * step];
      }
    }
    magnitude *= 10;
  }
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

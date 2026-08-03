/// stats_data.dart – Aggregationen für die Statistik-Seite.
///
/// Reine Funktionen ohne Flutter-Bezug, wie `chart_data.dart` — getrennt
/// davon, weil jene Datei die Startseite versorgt und diese die
/// Statistik-Seite. Gemeinsam bleibt die Linie: Kennzahlen werden berechnet,
/// nie gespeichert; Konstanten werden beim Lesen eingesetzt und sind hier
/// als solche dokumentiert.
library;

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'chart_data.dart';
import 'fairness.dart';
import 'price_series.dart';

/// Fahrten je Woche für die Karte „Fahrten pro Woche".
///
/// Bewusst OHNE Preisbezug: `SavingsChart.tripCounts` hängt am Preisarchiv
/// und fällt mit ihm aus — die Frage „wann wurde gefahren" braucht keinen
/// Preis. Solo-Fahrten zählen mit, wie dort: Gefahren ist gefahren.
class WeeklyTripBars {
  const WeeklyTripBars({
    required this.weeks,
    required this.counts,
    required this.average,
    required this.recordIndex,
    required this.recordWeek,
    required this.recordCount,
  });

  /// Die gezeigten Wochen, endend in der Woche von `now`.
  final List<IsoWeek> weeks;

  /// Fahrten je Woche, parallel zu [weeks]. Null-Wochen bleiben stehen —
  /// eine ausgelassene Woche stauchte den Zeitraum (dieselbe Falle wie im
  /// Ersparnis-Diagramm).
  final List<int> counts;

  /// Ø über die GEZEIGTEN Wochen inklusive Null-Wochen — die Linie muss zu
  /// den Balken passen, nicht zu einer anderen Grundgesamtheit.
  final double average;

  /// Index der Rekordwoche in [weeks] — oder `null`, wenn der Rekord vor dem
  /// Fenster liegt. Dann wird KEIN Balken markiert: Der höchste Balken im
  /// Ausschnitt wäre nicht der Rekord, und ihn so einzufärben behauptete es.
  final int? recordIndex;

  /// Die Rekordwoche über die GANZE Historie (kann außerhalb liegen).
  final IsoWeek recordWeek;

  final int recordCount;
}

/// Rechnet [WeeklyTripBars] über die letzten [window] Wochen bis heute.
///
/// Fahrten nach der laufenden Woche zählen nicht — sonst streckte ein
/// Vertipper in die Zukunft das Bild (dieselbe Lehre wie bei
/// `savingsWindow`, #160). `null`, wenn im Fenster nichts gefahren wurde:
/// Eine Karte, die nichts weiß, sagt besser nichts.
WeeklyTripBars? weeklyTripBars(
  List<Trip> trips, {
  required DateTime now,
  int window = 12,
}) {
  final current = IsoWeek.of(now);
  final all = <IsoWeek, int>{};
  for (final trip in trips) {
    final week = IsoWeek.of(trip.date);
    if (current.compareTo(week) < 0) continue;
    all[week] = (all[week] ?? 0) + 1;
  }
  if (all.isEmpty) return null;

  var start = current;
  for (var i = 1; i < window; i++) {
    start = IsoWeek.of(start.monday.subtract(const Duration(days: 7)));
  }
  final weeks = weeksBetween(start, current);
  final counts = [for (final week in weeks) all[week] ?? 0];
  if (counts.every((count) => count == 0)) return null;

  // Rekord über die ganze Historie; Gleichstand → die früheste Woche, denn
  // sie hat den Rekord aufgestellt, die späteren haben ihn nur eingestellt.
  var recordWeek = all.keys.first;
  var recordCount = 0;
  all.forEach((week, count) {
    if (count > recordCount ||
        (count == recordCount && week.compareTo(recordWeek) < 0)) {
      recordWeek = week;
      recordCount = count;
    }
  });
  final indexInWindow = weeks.indexOf(recordWeek);

  return WeeklyTripBars(
    weeks: weeks,
    counts: counts,
    average: counts.fold<int>(0, (sum, count) => sum + count) / counts.length,
    recordIndex: indexInWindow < 0 ? null : indexInWindow,
    recordWeek: recordWeek,
    recordCount: recordCount,
  );
}

/// „KW 27" — mit Jahr („KW 27/2024"), sobald es nicht das von [reference]
/// ist. Dieselbe Lektion wie bei `axisLabels`: Ohne Jahreszahl liest sich
/// eine alte Woche wie eine aktuelle.
String weekShortLabel(IsoWeek week, {required IsoWeek reference}) =>
    week.year == reference.year
    ? 'KW ${week.week}'
    : 'KW ${week.week}/${week.year}';

/// Runde Beträge, an denen die Ersparnis-Kurve einen Meilenstein trägt:
/// 50, 100, 250, 500, 1000, 2500, … — aufsteigend, endlos.
Iterable<int> _euroLadder() sync* {
  var scale = 1;
  while (true) {
    for (final base in const [50, 100, 250]) {
      yield base * scale;
    }
    scale *= 10;
  }
}

/// Größter erreichter runder Betrag und die Woche der Erst-Überschreitung —
/// `null`, solange nicht einmal die 50 € erreicht sind.
({int amount, int weekIndex})? savingsMilestone(SavingsChart chart) {
  int? amount;
  for (final rung in _euroLadder()) {
    if (rung > chart.total) break;
    amount = rung;
  }
  if (amount == null) return null;
  for (var i = 0; i < chart.group.length; i++) {
    if (chart.group[i] >= amount) return (amount: amount, weekIndex: i);
  }
  return null;
}

/// Hochrechnung „bis Jahresende": Stand am Jahresende, wenn das Tempo der
/// letzten bis zu zwölf Kurven-Wochen so weiterläuft.
///
/// Reine Anzeige, kein Eintrag in der Zukunft — und ehrlich benannt („bei
/// eurem Tempo"). `null`, wenn die Kurve zu kurz ist, das Tempo nicht
/// positiv ist oder das Jahr keine ganze Woche mehr übrig hat: Eine
/// Hochrechnung ohne Spielraum wiederholte nur die Summe.
double? yearEndProjection(SavingsChart chart, {required DateTime now}) {
  if (chart.group.length < 4) return null;
  final span = chart.group.length - 1 < 12 ? chart.group.length - 1 : 12;
  final pace =
      (chart.group.last - chart.group[chart.group.length - 1 - span]) / span;
  if (pace <= 0) return null;

  // Der 28. Dezember liegt per ISO-Definition immer in der letzten Woche.
  final current = IsoWeek.of(now);
  final lastOfYear = IsoWeek.of(DateTime(now.year, 12, 28));
  final remaining = weeksBetween(current, lastOfYear).length - 1;
  if (remaining <= 0) return null;
  return chart.total + pace * remaining;
}

/// Vergleichsgröße „Tankfüllung": 50 Liter zum Diesel-Preis aus den
/// Parametern — eine grobe Anschauung, keine Abrechnung. Beim Lesen
/// eingesetzt, nie gespeichert.
const double kTankLiters = 50;

int tankEquivalents(double totalSaved, AppSettings settings) {
  final tankPrice = kTankLiters * settings.dieselPricePerLiter;
  if (tankPrice <= 0 || totalSaved <= 0) return 0;
  return totalSaved ~/ tankPrice;
}

/// CO₂ je Liter Kraftstoff (Verbrennung, gerundete Standardwerte).
///
/// Entschieden 2026-08-03: gerechnet wird NICHT mit einem pauschalen
/// kg/km-Faktor, sondern je Person aus ihrem eingetragenen Verbrauch und
/// ihrer Spritart — exakt die Form von [savedCostsFor], nur mit kg/l statt
/// €/l. E-Autos bleiben außen vor (Faktor 0): Ihr Strommix wäre eine
/// zweite Schätz-Konstante, und die Zahl soll tragen, nicht raten.
const double kCo2PerLiterDiesel = 2.65;
const double kCo2PerLiterPetrol = 2.37;

/// Ein Baum bindet grob 21 kg CO₂ im Jahr — Anschauungswert für die Kachel.
const double kCo2PerTreeYear = 21;

double _co2PerLiter(EnergyType? energy) => switch (energy) {
  EnergyType.diesel => kCo2PerLiterDiesel,
  EnergyType.petrol => kCo2PerLiterPetrol,
  EnergyType.electric || null => 0,
};

/// Eingespartes CO₂ einer Person — dieselbe Formel wie die Ersparnis
/// ([savedCostsFor]), mit kg/l an der Stelle des Preises. Ohne Verbrauch
/// oder Energieart 0, nie geschätzt.
double savedCo2KgFor({
  required Person person,
  required double days,
  required double commuteKm,
}) => savedCostsFor(
  person: person,
  pricePerUnit: _co2PerLiter(person.energyType),
  days: days,
  commuteKm: commuteKm,
);

/// Eingespartes CO₂ der ganzen Gruppe. Wie bei der Ersparnis spart eine
/// 1-way-Mitfahrt den vollen Tag (`ridden + oneWay`).
double groupSavedCo2Kg(
  Map<String, PersonStats> stats,
  List<Person> persons,
  AppSettings settings,
) {
  final byId = {for (final person in persons) person.id: person};
  var sum = 0.0;
  for (final s in stats.values) {
    final person = byId[s.personId];
    if (person == null) continue;
    sum += savedCo2KgFor(
      person: person,
      days: (s.ridden + s.oneWay).toDouble(),
      commuteKm: settings.commuteKm,
    );
  }
  return sum;
}

/// Das nächste Etappenziel des CO₂-Rings: 10, 25, 50, 100, 250, … — der
/// erste Wert oberhalb von [kg]. Ehrlich statt willkürlich: kein
/// gespeichertes Ziel, ein sichtbar wanderndes Etappenziel.
double nextCo2Milestone(double kg) {
  var scale = 1;
  while (true) {
    for (final base in const [10, 25, 50]) {
      final rung = base * scale;
      if (rung > kg) return rung.toDouble();
    }
    scale *= 10;
  }
}

/// Vermiedene Solo-Kilometer: die Mitfahr-Tage GENAU der Personen, die in
/// die CO₂-Summe eingehen — die Kachel erklärt die Ring-Zahl, also müssen
/// beide dieselben Personen zählen. Wer elektrisch fährt oder keinen
/// Verbrauch eingetragen hat, steht in beiden nicht drin.
double avoidedSoloKm(
  Map<String, PersonStats> stats,
  List<Person> persons,
  AppSettings settings,
) {
  final byId = {for (final person in persons) person.id: person};
  var km = 0.0;
  for (final s in stats.values) {
    final person = byId[s.personId];
    if (person == null || person.consumptionPer100km == null) continue;
    if (_co2PerLiter(person.energyType) == 0) continue;
    km += (s.ridden + s.oneWay) * settings.commuteKm * 2;
  }
  return km;
}

/// Das Raster der Heatmap „Euer Wochen-Muster": Wer fährt an welchem
/// Wochentag wie oft?
class WeekdayMatrix {
  const WeekdayMatrix({
    required this.personIds,
    required this.weekdays,
    required this.counts,
    required this.max,
  });

  /// Zeilen, absteigend nach Fahr-Tagen; Gleichstand nach Id — sonst
  /// wechselte die Reihenfolge zwischen zwei Aufbauten ohne Datenänderung.
  final List<String> personIds;

  /// Spalten als `DateTime.weekday`-Werte: Mo–Fr immer, Sa/So nur wenn dort
  /// je gefahren wurde — keine dauerhaft leeren Spalten, keine versteckten
  /// Fahrten.
  final List<int> weekdays;

  /// `counts[zeile][spalte]` = Tage gefahren.
  final List<List<int>> counts;

  /// Höchster Zellwert, für die Intensitäts-Skala (≥ 1).
  final int max;
}

/// Zählt GEFAHRENE Tage je Person und Wochentag. Solo-Fahrten zählen nicht —
/// wie in allen Kennzahlen (#61) und bewusst anders als die Wochen-Säulen,
/// die dem `tripCounts`-Vorbild folgen: Dort geht es um „wann wurde
/// gefahren", hier um „wer fährt wann" — und eine Solo-Fahrt ist kein
/// Fahren für die Gemeinschaft.
WeekdayMatrix? weekdayDriveMatrix(List<Trip> trips) {
  final perPerson = <String, Map<int, int>>{};
  var saturday = false;
  var sunday = false;
  for (final trip in trips) {
    if (isSoloTrip(trip)) continue;
    final driver = trip.driverId;
    if (driver == null) continue;
    final weekday = trip.date.weekday;
    if (weekday == DateTime.saturday) saturday = true;
    if (weekday == DateTime.sunday) sunday = true;
    final row = perPerson.putIfAbsent(driver, () => {});
    row[weekday] = (row[weekday] ?? 0) + 1;
  }
  if (perPerson.isEmpty) return null;

  final weekdays = [
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    if (saturday) DateTime.saturday,
    if (sunday) DateTime.sunday,
  ];
  int totalOf(String id) =>
      perPerson[id]!.values.fold(0, (sum, count) => sum + count);
  final ids = perPerson.keys.toList()
    ..sort((a, b) {
      final byTotal = totalOf(b).compareTo(totalOf(a));
      return byTotal != 0 ? byTotal : a.compareTo(b);
    });
  final counts = [
    for (final id in ids)
      [for (final weekday in weekdays) perPerson[id]![weekday] ?? 0],
  ];
  var max = 0;
  for (final row in counts) {
    for (final count in row) {
      if (count > max) max = count;
    }
  }
  return WeekdayMatrix(
    personIds: ids,
    weekdays: weekdays,
    counts: counts,
    max: max,
  );
}

/// „Mittwochs fährt fast immer Ben" — die stärkste Wochentags-Dominanz.
class WeekdayDominance {
  const WeekdayDominance({
    required this.personId,
    required this.weekday,
    required this.count,
    required this.share,
  });

  final String personId;

  /// `DateTime.weekday`-Wert.
  final int weekday;

  final int count;

  /// Anteil dieser Person an allen Fahrten des Wochentags (0..1].
  final double share;
}

/// Sucht die stärkste Dominanz über alle Wochentage.
///
/// Guards gegen Kleinstdaten: unter [minCount] Fahrten oder unter [minShare]
/// Anteil gibt es keine Aussage — drei Fahrten sind kein Muster. Bei
/// Gleichstand gewinnt der höhere Anteil, dann die höhere Anzahl, dann der
/// frühere Wochentag — deterministisch, sonst wechselte die Pointe zwischen
/// zwei Aufbauten.
WeekdayDominance? weekdayDominance(
  WeekdayMatrix matrix, {
  int minCount = 4,
  double minShare = 0.6,
}) {
  WeekdayDominance? best;
  for (var col = 0; col < matrix.weekdays.length; col++) {
    var columnTotal = 0;
    var bestRow = -1;
    var bestCount = 0;
    for (var row = 0; row < matrix.personIds.length; row++) {
      final count = matrix.counts[row][col];
      columnTotal += count;
      if (count > bestCount) {
        bestCount = count;
        bestRow = row;
      }
    }
    if (bestCount < minCount) continue;
    final share = bestCount / columnTotal;
    if (share < minShare) continue;
    if (best == null ||
        share > best.share ||
        (share == best.share && bestCount > best.count)) {
      best = WeekdayDominance(
        personId: matrix.personIds[bestRow],
        weekday: matrix.weekdays[col],
        count: bestCount,
        share: share,
      );
    }
  }
  return best;
}

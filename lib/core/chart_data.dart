/// chart_data.dart – Aggregationen für die Diagramme auf der Startseite.
///
/// Bewusst reine Funktionen ohne Flutter-Bezug: dadurch testbar, und die
/// Kennzahlen bleiben – wie überall in der App – berechnet statt gespeichert.
library;

import '../models/app_settings.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'fairness.dart';
import 'price_series.dart';

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

/// Die Ersparnis-Kurven über die Wochen (#Startseite).
///
/// Parallele Listen über **einer** Wochenachse: [weeks] gibt die Achse vor,
/// [group] und jeder Eintrag in [perPerson] sind genauso lang. Das ist die
/// Form, die der Painter braucht — er setzt die Punkte über ihren Index,
/// eine ausgelassene Woche stauchte also den Zeitraum, statt eine Lücke zu
/// zeigen (dieselbe Falle wie beim Preis-Diagramm).
class SavingsChart {
  const SavingsChart({
    required this.weeks,
    required this.group,
    required this.perPerson,
    required this.carriedOver,
    required this.estimatedFrom,
    required this.tripCounts,
  });

  final List<IsoWeek> weeks;

  /// Kumulierte Ersparnis der ganzen Gruppe, je Woche.
  final List<double> group;

  /// Fahrten je Woche — die blassen Säulen hinter den Kurven. Sie ersetzen
  /// das frühere Monats-Diagramm (#119, #129) und beantworten dieselbe
  /// Frage — *wann* wurde gefahren — auf derselben Zeitachse wie die
  /// Ersparnis, statt auf einer zweiten daneben. Solo-Fahrten zählen mit,
  /// wie im Monats-Diagramm: Gefahren ist gefahren, nur gespart wird dabei
  /// nichts.
  final List<int> tripCounts;

  /// Dasselbe je Person; nur Personen mit Ersparnis > 0 stehen drin.
  final Map<String, List<double>> perPerson;

  /// Was vor [weeks] schon aufgelaufen war. Die Kurven starten darauf und
  /// nicht bei 0 — sonst behauptete ein verkürztes Fenster, die Gruppe habe
  /// vorher nichts gespart.
  final double carriedOver;

  /// Ab welchem Index die Linie **dieser Person** einen ungemessenen Preis
  /// mitträgt; fehlt der Eintrag, ist ihre Kurve durchweg gemessen.
  ///
  /// **Je Linie, nicht global** — teuer gelernt am 02.08.2026: Für Strom
  /// gibt es keine Messung, er ist immer die Konstante aus den Parametern.
  /// Eine gruppenweite Markierung strichelte deshalb, sobald *eine* Person
  /// elektrisch fährt, auch die Linie von jemandem, dessen Diesel Woche für
  /// Woche gemessen ist — die Kennzeichnung sagte dann über niemanden mehr
  /// etwas.
  ///
  /// **Ab da, nicht nur dort:** Die Kurve ist kumuliert, also steckt eine
  /// geschätzte Woche in jeder folgenden Summe. Nur die eine Woche zu
  /// kennzeichnen behauptete, danach sei wieder alles gemessen.
  ///
  /// Wochen **ohne** Fahrt zählen nicht mit: Dort wird nichts gespart, ihr
  /// überbrückter Preis geht in keine Summe ein.
  final Map<String, int> estimatedFrom;

  /// Die Gruppenlinie ist die Summe — sie trägt jede Schätzung mit, also ab
  /// der frühesten von allen.
  int? get groupEstimatedFrom => estimatedFrom.isEmpty
      ? null
      : estimatedFrom.values.reduce((a, b) => a < b ? a : b);

  double get total => group.isEmpty ? carriedOver : group.last;
}

/// Kumulierte Ersparnis je ISO-Woche — je Person und für die Gruppe.
///
/// **Jede Woche rechnet mit dem Preis dieser Woche.** Genau dafür gibt es
/// das Preisarchiv: Über dreieinhalb Jahre lag Diesel zwischen 1,46 € und
/// 2,26 €, und eine einzige Konstante über den ganzen Zeitraum verteilt die
/// Ersparnis auf die falschen Wochen — sie behauptet, eine Mitfahrt im
/// Herbst 2023 habe so viel gespart wie eine im Januar 2026.
///
/// **Ohne gespeicherte Preise ist das Ergebnis exakt die alte Rechnung.**
/// [weeklySeries] füllt dann jede Woche mit der Konstante aus den
/// Parametern, und [savedCostsFor] ist dieselbe Formel wie in
/// [PersonStats.savedCosts]. Das ist kein Zufall, sondern die Bedingung
/// dafür, dass Kachel und Diagramm nie zwei Wahrheiten zeigen —
/// `test/chart_data_test.dart` nagelt die Gleichheit fest.
///
/// [trips] darf die ganze Historie enthalten; was vor [from] liegt, landet
/// in [SavingsChart.carriedOver] statt unter den Tisch zu fallen.
SavingsChart weeklySavings({
  required List<Trip> trips,
  required List<Person> persons,
  required AppSettings settings,
  required Iterable<PricePoint> storedPrices,
  required IsoWeek from,
  required IsoWeek to,
}) {
  final weeks = weeksBetween(from, to);
  final byId = {for (final person in persons) person.id: person};
  final index = {for (var i = 0; i < weeks.length; i++) weeks[i]: i};

  // Je Energieart eine Preisreihe über dasselbe Fenster. Nur die wirklich
  // gebrauchten: Eine Gruppe ohne Elektroauto soll keine Stromreihe
  // auflösen müssen.
  final needed = <PriceSeries>{
    for (final person in persons)
      if (person.energyType != null) _seriesFor(person.energyType!),
  };
  final prices = <PriceSeries, Map<IsoWeek, PricePoint>>{
    for (final series in needed)
      series: {
        for (final point in weeklySeries(
          series: series,
          from: from,
          to: to,
          stored: storedPrices,
          settings: settings,
        ))
          point.week: point,
      },
  };

  final perWeek = <String, List<double>>{};
  final estimatedFrom = <String, int>{};
  final tripCounts = List<int>.filled(weeks.length, 0);
  var carriedOver = 0.0;

  for (final trip in trips) {
    final tripSlot = index[IsoWeek.of(trip.date)];
    if (tripSlot != null) tripCounts[tripSlot]++;

    if (isSoloTrip(trip)) continue;
    final week = IsoWeek.of(trip.date);
    final slot = index[week];

    for (final entry in trip.participations.entries) {
      // Nur Mitfahrten sparen etwas: Wer selbst fährt, zahlt ja.
      if (entry.value == ParticipationStatus.driver) continue;
      final person = byId[entry.key];
      if (person == null || person.energyType == null) continue;

      final series = _seriesFor(person.energyType!);
      final point = slot == null ? null : prices[series]?[week];
      final saved = savedCostsFor(
        person: person,
        // Vor dem Fenster gibt es keine Preisreihe — dort trägt die
        // Konstante. Der Übertrag ist eine Zahl, keine Kurve; ihn genau zu
        // rechnen hieße, die Reihe über die ganze Historie aufzulösen.
        pricePerUnit: point?.value ?? constantFor(series, settings),
        days: 1,
        commuteKm: settings.commuteKm,
      );
      if (saved == 0) continue;

      if (slot == null) {
        carriedOver += saved;
        continue;
      }
      (perWeek[entry.key] ??= List<double>.filled(weeks.length, 0))[slot] +=
          saved;
      // „Geschätzt" heißt: ein KRAFTSTOFF-Preis, den niemand gemessen hat.
      // Strom kommt planmäßig aus den Parametern („nicht aus dem Netz",
      // sagt der Preis-Screen) — die eingetragene Konstante ist dort die
      // beste verfügbare Wahrheit, keine Schätzung. Zählte sie mit, wäre
      // die Linie jeder E-Auto-Gruppe für immer gestrichelt: eine Warnung,
      // die nie verschwinden kann, und damit Lärm.
      if (series.isMeasurable && point != null && point.isEstimate) {
        final known = estimatedFrom[entry.key];
        if (known == null || slot < known) estimatedFrom[entry.key] = slot;
      }
    }
  }

  // Aufsummieren: erst je Person, daraus die Gruppe. Andersherum gerechnet
  // könnten beide auseinanderlaufen, sobald eine Person herausfällt.
  final perPerson = <String, List<double>>{};
  final group = List<double>.filled(weeks.length, carriedOver);
  for (final entry in perWeek.entries) {
    var running = 0.0;
    final line = <double>[];
    for (var i = 0; i < weeks.length; i++) {
      running += entry.value[i];
      line.add(running);
      group[i] += running;
    }
    if (running > 0) perPerson[entry.key] = line;
  }

  return SavingsChart(
    weeks: weeks,
    group: group,
    perPerson: perPerson,
    carriedOver: carriedOver,
    // Nur Personen, die auch eine Linie bekommen: Wer nichts gespart hat,
    // hat keine Kurve, die man kennzeichnen könnte.
    estimatedFrom: {
      for (final entry in estimatedFrom.entries)
        if (perPerson.containsKey(entry.key)) entry.key: entry.value,
    },
    tripCounts: tripCounts,
  );
}

/// Welche Preisreihe eine Energieart bezahlt.
///
/// Benzin rechnet mit **E5**, nicht E10 — dieselbe Zuordnung wie
/// `constantFor` und `priceForEnergy`. Läuft eine der drei Stellen weg,
/// rechnet die Kachel mit einem anderen Preis als das Diagramm.
PriceSeries _seriesFor(EnergyType energy) => switch (energy) {
  EnergyType.electric => PriceSeries.housePower,
  EnergyType.diesel => PriceSeries.diesel,
  EnergyType.petrol => PriceSeries.e5,
};

/// Das Wochenfenster, das alle Fahrten trägt — die Zeitachse des
/// Ersparnis-Diagramms.
///
/// Endet bei der letzten Fahrt, nicht bei heute: Eine kumulierte Kurve läuft
/// sonst als waagerechte Linie durch jede fahrfreie Zeit und behauptet
/// Aktivität, wo keine war. Dieselbe Begründung wie bei `chartWindow` im
/// Preis-Diagramm.
(IsoWeek, IsoWeek)? savingsWindow(List<Trip> trips, {int minWeeks = 8}) {
  if (trips.isEmpty) return null;
  var first = IsoWeek.of(trips.first.date);
  var last = first;
  for (final trip in trips) {
    final week = IsoWeek.of(trip.date);
    if (week.compareTo(first) < 0) first = week;
    if (week.compareTo(last) > 0) last = week;
  }
  // Eine junge Gruppe bekäme sonst zwei Punkte statt einer Kurve.
  var from = last;
  for (var i = 1; i < minWeeks; i++) {
    from = IsoWeek.of(from.monday.subtract(const Duration(days: 7)));
  }
  return (first.compareTo(from) < 0 ? first : from, last);
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

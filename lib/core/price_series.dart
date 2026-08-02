/// price_series.dart – Preisreihen je ISO-Woche.
///
/// Drei reine Aufgaben, bewusst ohne Flutter-Bezug und damit testbar:
/// das Wochenraster, die Verdichtung von Stichproben zu einem Wochenwert
/// und das Zusammenführen mit den Fallback-Konstanten aus den Settings.
///
/// Die Konstanten werden hier eingesetzt und **nicht** gespeichert. Läge
/// eine Konstante in `price_week`, müsste eine Änderung der Parameter die
/// Historie umschreiben — und sie sähe später aus wie eine Messung. Gleiche
/// Linie wie überall: Kennzahlen werden berechnet, nie gespeichert.
library;

import '../models/app_settings.dart';

/// Die fünf Reihen, für die es je Gruppe und Woche einen Wert gibt.
///
/// Die ersten drei werden gemessen, die beiden Strom-Reihen bestehen
/// vorerst ausschließlich aus der Konstante der Gruppe — die Reihe gibt es
/// trotzdem, damit eine spätere Quelle nur einen Schreiber braucht und
/// keinen Umbau.
enum PriceSeries {
  diesel('diesel'),
  e5('e5'),
  e10('e10'),
  housePower('house_power'),
  chargingPower('charging_power');

  const PriceSeries(this.key);

  /// Wert der Spalte `series` in `price_week`. Nur die Kraftstoffe kommen
  /// dort vor; die Strom-Reihen tragen ihn für Diagramm-Schlüssel.
  final String key;

  /// Ob die Reihe aus Stichproben entsteht. Für die beiden Strom-Reihen
  /// gibt es heute keine Quelle, sie sind immer [PriceOrigin.constant].
  bool get isMeasurable =>
      this == PriceSeries.diesel ||
      this == PriceSeries.e5 ||
      this == PriceSeries.e10;

  static PriceSeries? fromKey(String key) {
    for (final series in PriceSeries.values) {
      if (series.key == key) return series;
    }
    return null;
  }
}

/// Woher ein Wochenwert stammt — im Diagramm sichtbar zu machen.
///
/// [mixed] entsteht an der Naht zwischen importierter Vergangenheit und
/// gemessener Gegenwart, [constant] überall dort, wo keine Messung vorliegt.
enum PriceOrigin { measured, imported, mixed, constant }

/// Eine Kalenderwoche nach ISO 8601 (Montag beginnt, Woche 1 enthält den
/// ersten Donnerstag).
///
/// Gerechnet wird durchgehend in UTC: Eine Zeitumstellung darf ein Datum
/// nicht in die Nachbarwoche schieben.
class IsoWeek implements Comparable<IsoWeek> {
  const IsoWeek(this.year, this.week);

  factory IsoWeek.of(DateTime date) {
    final day = DateTime.utc(date.year, date.month, date.day);
    // Der Donnerstag derselben Woche entscheidet über das ISO-Jahr — das
    // ist die Definition, und sie ist der Grund, warum der 31.12. in
    // Woche 1 des Folgejahres liegen kann.
    final thursday = day.add(Duration(days: 4 - day.weekday));
    final jan1 = DateTime.utc(thursday.year, 1, 1);
    final ordinal = thursday.difference(jan1).inDays + 1;
    return IsoWeek(thursday.year, (ordinal - 1) ~/ 7 + 1);
  }

  final int year;
  final int week;

  /// Montag dieser Woche, 00:00 UTC.
  DateTime get monday {
    // Der 4. Januar liegt per Definition immer in Woche 1.
    final jan4 = DateTime.utc(year, 1, 4);
    final firstMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return firstMonday.add(Duration(days: (week - 1) * 7));
  }

  IsoWeek get next => IsoWeek.of(monday.add(const Duration(days: 7)));

  @override
  int compareTo(IsoWeek other) => year != other.year
      ? year.compareTo(other.year)
      : week.compareTo(other.week);

  @override
  bool operator ==(Object other) =>
      other is IsoWeek && other.year == year && other.week == week;

  @override
  int get hashCode => Object.hash(year, week);

  @override
  String toString() => '$year-W${week.toString().padLeft(2, '0')}';
}

/// Lückenlose Folge von Wochen, [from] und [to] eingeschlossen.
///
/// Lücken gehören ins Bild — eine Achse, die nur die Wochen mit Daten
/// zeigt, täuscht eine durchgehende Reihe vor.
List<IsoWeek> weeksBetween(IsoWeek from, IsoWeek to) {
  if (from.compareTo(to) > 0) return const [];
  final weeks = <IsoWeek>[];
  var current = from;
  while (current.compareTo(to) <= 0) {
    weeks.add(current);
    current = current.next;
  }
  return weeks;
}

/// Eine Stichprobe: was eine Station zu einem Zeitpunkt verlangt hat.
class PriceSample {
  const PriceSample({
    required this.capturedAt,
    required this.stationId,
    this.e5,
    this.e10,
    this.diesel,
  });

  final DateTime capturedAt;
  final String stationId;

  /// Fehlende Werte sind `null`, nicht 0: Nicht jede Station führt alle
  /// Sorten, und eine geschlossene meldet gar keinen Preis. Eine 0 im
  /// Perzentil zöge den Wochenwert gegen den Boden.
  final double? e5;
  final double? e10;
  final double? diesel;

  double? valueOf(PriceSeries series) => switch (series) {
    PriceSeries.e5 => e5,
    PriceSeries.e10 => e10,
    PriceSeries.diesel => diesel,
    PriceSeries.housePower || PriceSeries.chargingPower => null,
  };
}

/// Perzentil mit linearer Interpolation zwischen den Rangwerten.
///
/// [fraction] 0.1 heißt: der Wert, den 10 % der Stichproben unterbieten.
///
/// **Hat bewusst keinen Aufrufer in `lib/`.** Verdichtet wird in SQL
/// (`rollup_fuel_weeks`), weil `percentile_cont` genau dies rechnet und der
/// Lauf neben den Daten sitzt; der spätere Import der Vergangenheit läuft in
/// Python. Eine einzige Implementierung ist damit gar nicht zu haben — eine
/// einzige *Definition* schon, und die steht hier: [defaultPercentile] ist
/// die Zahl, an die `test/schema_test.dart` das SQL festnagelt, und die
/// Tests dieser Funktion sind die ausführbare Beschreibung dessen, was
/// `percentile_cont` tun muss. Wer sie löscht, nimmt der Zahl ihr Zuhause.
double percentile(List<double> values, double fraction) {
  if (values.isEmpty) {
    throw ArgumentError.value(values, 'values', 'darf nicht leer sein');
  }
  if (fraction < 0 || fraction > 1) {
    throw ArgumentError.value(fraction, 'fraction', 'muss in [0,1] liegen');
  }
  final sorted = [...values]..sort();
  if (sorted.length == 1) return sorted.first;

  final position = (sorted.length - 1) * fraction;
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - lower);
}

/// Das Ergebnis einer Wochenverdichtung.
class WeekAggregate {
  const WeekAggregate({
    required this.value,
    required this.sampleCount,
    required this.stationCount,
  });

  final double value;
  final int sampleCount;

  /// Wie viele verschiedene Stationen beigetragen haben. Bei sehr wenigen
  /// ist ein 10-%-Perzentil faktisch „der günstigste von dreien" — das soll
  /// die Oberfläche sagen können, statt es zu verschweigen.
  final int stationCount;
}

/// Standard-Perzentil der Wochenverdichtung.
///
/// Nicht das Minimum: Man tankt nie genau beim billigsten Anbieter zum
/// billigsten Zeitpunkt. Das Perzentil ist zudem die einzige Definition,
/// die für gemessene und für später importierte Daten dieselbe Frage
/// beantwortet — sonst entstünde an der Naht eine Stufe, die keine
/// Preisänderung ist.
const double defaultPercentile = 0.10;

/// Verdichtet die Stichproben **einer** Woche zu je einem Wert pro Reihe.
///
/// Reihen ohne brauchbare Stichprobe fehlen im Ergebnis — sie werden später
/// aus der Konstante gefüllt und als solche markiert, statt hier still
/// erfunden zu werden.
Map<PriceSeries, WeekAggregate> aggregateWeek(
  List<PriceSample> samples, {
  double fraction = defaultPercentile,
}) {
  final result = <PriceSeries, WeekAggregate>{};
  for (final series in PriceSeries.values) {
    if (!series.isMeasurable) continue;

    final values = <double>[];
    final stations = <String>{};
    for (final sample in samples) {
      final value = sample.valueOf(series);
      if (value == null) continue;
      values.add(value);
      stations.add(sample.stationId);
    }
    if (values.isEmpty) continue;

    result[series] = WeekAggregate(
      value: percentile(values, fraction),
      sampleCount: values.length,
      stationCount: stations.length,
    );
  }
  return result;
}

/// Ein Punkt der Wochenreihe, wie ihn das Diagramm zeichnet.
class PricePoint {
  const PricePoint({
    required this.week,
    required this.series,
    required this.value,
    required this.origin,
    this.sampleCount = 0,
    this.stationCount = 0,
  });

  final IsoWeek week;
  final PriceSeries series;
  final double value;
  final PriceOrigin origin;
  final int sampleCount;
  final int stationCount;

  /// Gestrichelt und heller zu zeichnen: kein gemessener Wert, sondern die
  /// Konstante aus den Gruppensettings.
  bool get isConstant => origin == PriceOrigin.constant;
}

/// Die Konstante, mit der eine Reihe gefüllt wird, wenn nichts gemessen ist.
double constantFor(PriceSeries series, AppSettings settings) =>
    switch (series) {
      PriceSeries.diesel => settings.dieselPricePerLiter,
      PriceSeries.e5 => settings.petrolPricePerLiter,
      PriceSeries.e10 => settings.e10PricePerLiter,
      PriceSeries.housePower => settings.electricityPricePerKwh,
      PriceSeries.chargingPower => settings.chargingPricePerKwh,
    };

/// Lückenlose Wochenreihe von [from] bis [to].
///
/// [stored] sind die gemessenen bzw. importierten Wochen (aus `price_week`);
/// jede Woche, die dort fehlt, wird aus der Konstante gefüllt und trägt
/// [PriceOrigin.constant]. Genau diese Markierung macht das Diagramm
/// ehrlich: Eine erfundene Linie unterscheidet sich sonst nicht von einer
/// gemessenen.
List<PricePoint> weeklySeries({
  required PriceSeries series,
  required IsoWeek from,
  required IsoWeek to,
  required Iterable<PricePoint> stored,
  required AppSettings settings,
}) {
  final known = <IsoWeek, PricePoint>{
    for (final point in stored)
      if (point.series == series) point.week: point,
  };
  final fallback = constantFor(series, settings);

  return [
    for (final week in weeksBetween(from, to))
      known[week] ??
          PricePoint(
            week: week,
            series: series,
            value: fallback,
            origin: PriceOrigin.constant,
          ),
  ];
}

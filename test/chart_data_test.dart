/// chart_data_test.dart – Aggregation der Startseiten-Diagramme.
library;

import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

Trip tripOn(DateTime date) =>
    Trip(id: date.toIso8601String(), date: date, participations: const {});

/// Ein Fahrtag: [driver] fährt, alle [riders] fahren voll mit.
Trip rideOn(DateTime date, String driver, List<String> riders) => Trip(
  id: '$date-$driver',
  date: date,
  participations: {
    driver: ParticipationStatus.driver,
    for (final rider in riders) rider: ParticipationStatus.passenger,
  },
);

const anna = Person(
  id: 'anna',
  name: 'Anna',
  active: true,
  energyType: EnergyType.diesel,
  consumptionPer100km: 6,
);
const ben = Person(
  id: 'ben',
  name: 'Ben',
  active: true,
  energyType: EnergyType.petrol,
  consumptionPer100km: 8,
);

/// Ohne Verbrauch gibt es keine Ersparnis — bewusst nicht geschätzt.
const clara = Person(id: 'clara', name: 'Clara', active: true);

PricePoint week(int year, int isoWeek, PriceSeries series, double value) =>
    PricePoint(
      week: IsoWeek(year, isoWeek),
      series: series,
      value: value,
      origin: PriceOrigin.measured,
    );

void main() {
  group('axisTicks', () {
    test('beginnt immer bei 0', () {
      for (final max in [1, 7, 8, 40, 137]) {
        expect(axisTicks(max).first, 0, reason: 'maxValue $max');
      }
    });

    test('deckt das Maximum ab', () {
      for (final max in [1, 3, 7, 8, 9, 23, 40, 137, 1001]) {
        expect(
          axisTicks(max).last,
          greaterThanOrEqualTo(max),
          reason: 'sonst ragte die höchste Säule über die Achse hinaus',
        );
      }
    });

    test('nimmt runde Schritte', () {
      expect(axisTicks(8), [0, 2, 4, 6, 8]);
      expect(axisTicks(7), [0, 2, 4, 6, 8]);
      expect(axisTicks(3), [0, 1, 2, 3, 4]);
      expect(axisTicks(23), [0, 10, 20, 30, 40]);
    });

    test('ohne Fahrten bleibt eine brauchbare Skala', () {
      expect(axisTicks(0), [0, 1]);
    });

    test('die Schrittzahl ist einstellbar', () {
      expect(axisTicks(8, count: 2), hasLength(3));
    });
  });

  test('ParticipationRow summiert alle Teilnahmearten', () {
    const row = ParticipationRow(
      label: 'Test',
      driven: 3,
      oneWay: 2,
      ridden: 5,
    );

    expect(row.total, 10);
  });

  group('weeklySavings', () {
    const settings = AppSettings();
    // Zwei Fahrten in aufeinanderfolgenden Wochen, Rollen getauscht.
    final trips = [
      rideOn(DateTime(2026, 7, 8), 'anna', ['ben', 'clara']),
      rideOn(DateTime(2026, 7, 15), 'ben', ['anna']),
    ];
    const persons = [anna, ben, clara];

    test('ohne gespeicherte Preise ist es exakt die alte Rechnung', () {
      // Das ist die Bedingung, unter der Kachel und Diagramm dieselbe Zahl
      // zeigen dürfen: Die Wochenrechnung ist eine Verallgemeinerung der
      // Konstanten-Rechnung, keine zweite. Läuft eine der beiden weg,
      // stünden auf der Startseite zwei Summen für dasselbe.
      final stats = computeStats(trips, settings);
      final byId = {for (final p in persons) p.id: p};
      final expected = stats.values.fold<double>(
        0,
        (sum, s) => sum + s.savedCosts(settings, byId[s.personId]!),
      );

      final (from, to) = savingsWindow(trips)!;
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: from,
        to: to,
      );

      expect(chart.total, closeTo(expected, 1e-9));
      expect(expected, greaterThan(0), reason: 'sonst prüft der Test nichts');
    });

    test('jede Woche rechnet mit dem Preis dieser Woche', () {
      // Ben fährt am 08.07. (KW 28) mit, Anna am 15.07. (KW 29). Ein
      // Diesel-Preissprung zwischen den Wochen darf nur Anna treffen.
      final cheap = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.0),
          week(2026, 29, PriceSeries.diesel, 1.0),
          week(2026, 28, PriceSeries.e5, 1.0),
          week(2026, 29, PriceSeries.e5, 1.0),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );
      final spike = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.0),
          week(2026, 29, PriceSeries.diesel, 2.0),
          week(2026, 28, PriceSeries.e5, 1.0),
          week(2026, 29, PriceSeries.e5, 1.0),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );

      // Anna: 6 l/100 km, 30 km einfach, also 60 km → 3,6 l. Ein Euro mehr
      // je Liter sind 3,60 € mehr.
      expect(spike.total - cheap.total, closeTo(3.6, 1e-9));
      expect(
        spike.perPerson['ben'],
        cheap.perPerson['ben'],
        reason: 'Bens Mitfahrt lag in der Woche VOR dem Sprung',
      );
    });

    test('die Gruppenkurve ist die Summe der Personenkurven', () {
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );

      for (var i = 0; i < chart.weeks.length; i++) {
        final sum = chart.perPerson.values.fold<double>(
          chart.carriedOver,
          (total, line) => total + line[i],
        );
        expect(chart.group[i], closeTo(sum, 1e-9), reason: 'Woche $i');
      }
    });

    test('die Kurve steigt nie', () {
      // Kumuliert heißt monoton: Ein Knick nach unten wäre ein Vorzeichen-
      // oder Reihenfolgefehler und im Bild sofort falsch.
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 20),
        to: const IsoWeek(2026, 30),
      );

      for (var i = 1; i < chart.group.length; i++) {
        expect(chart.group[i], greaterThanOrEqualTo(chart.group[i - 1]));
      }
    });

    test('was vor dem Fenster liegt, geht als Übertrag ein', () {
      // Sonst behauptete ein verkürztes Fenster, die Gruppe habe vorher
      // nichts gespart — und die Kachel widerspräche dem Diagramm.
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 29),
        to: const IsoWeek(2026, 29),
      );

      expect(chart.carriedOver, greaterThan(0));
      expect(chart.group.first, greaterThan(chart.carriedOver));
    });

    test('ohne Verbrauch spart eine Person nichts', () {
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );

      expect(
        chart.perPerson.containsKey('clara'),
        isFalse,
        reason:
            'Ein angenommener Verbrauch stünde in der Gesamtsumme, ohne dass '
            'ihn jemand eingetragen hätte.',
      );
    });

    test('die Fahrten je Woche stehen als Säulen bereit', () {
      // Sie ersetzen das Monats-Diagramm auf derselben Zeitachse. Die
      // Solo-Fahrt zählt hier MIT — gefahren ist gefahren, nur gespart
      // wird dabei nichts (dritter Test unten).
      final chart = weeklySavings(
        trips: [
          ...trips,
          Trip(
            id: 'solo',
            date: DateTime(2026, 7, 16),
            participations: const {'anna': ParticipationStatus.driver},
          ),
        ],
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 30),
      );

      expect(chart.tripCounts, [1, 2, 0]);
    });

    test('eine Solo-Fahrt zählt nicht', () {
      final chart = weeklySavings(
        trips: [
          Trip(
            id: 'solo',
            date: DateTime(2026, 7, 8),
            participations: const {'anna': ParticipationStatus.driver},
          ),
        ],
        persons: persons,
        settings: settings,
        storedPrices: const [],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 28),
      );

      expect(chart.total, 0);
    });

    test('ein ungemessener Preis markiert die Kurve ab dort', () {
      // Anna fährt in KW 29 mit (Diesel), Ben in KW 28 (Benzin). Gemessen
      // ist nur KW 28 — Annas Linie trägt also ab Index 1 eine Schätzung.
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.6),
          week(2026, 28, PriceSeries.e5, 1.8),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 30),
      );

      expect(chart.estimatedFrom['anna'], 1);
      expect(chart.groupEstimatedFrom, 1);
    });

    test('eine geschätzte Linie zieht die anderen nicht mit', () {
      // Der Fehler, den erst der Demo-Build zeigte (02.08.2026): Eine
      // gruppenweite Markierung strichelte ALLE Linien, sobald eine
      // einzige eine ungemessene Woche trug — auch die von jemandem,
      // dessen Preis Woche für Woche gemessen ist.
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        // Diesel beide Wochen gemessen, E5 gar nicht: Bens Benzin-Linie
        // ist geschätzt, Annas Diesel-Linie nicht.
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.6),
          week(2026, 29, PriceSeries.diesel, 1.6),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );

      expect(
        chart.estimatedFrom.containsKey('anna'),
        isFalse,
        reason: 'Annas Diesel ist in beiden Wochen gemessen',
      );
      expect(chart.estimatedFrom['ben'], 0, reason: 'E5 ist nie gemessen');
      // Die Gruppenlinie IST die Summe und trägt Bens Schätzung mit — sie
      // darf sich nicht sauberer geben, als sie ist.
      expect(chart.groupEstimatedFrom, 0);
    });

    test('Strom aus den Parametern gilt nicht als Schätzung', () {
      // Strom kommt planmäßig aus den Parametern — der Preis-Screen sagt
      // es wörtlich („nicht aus dem Netz"). Die eingetragene Konstante ist
      // die beste verfügbare Wahrheit. Zählte sie als Schätzung, wäre die
      // Linie jeder E-Auto-Gruppe für immer gestrichelt: eine Warnung, die
      // nie verschwinden kann, und damit Lärm (gesehen im Demo-Build am
      // 02.08.2026 — die „Zusammen"-Linie war durchweg gestrichelt, nur
      // weil eine Person elektrisch fährt).
      const stromer = Person(
        id: 'dora',
        name: 'Dora',
        active: true,
        energyType: EnergyType.electric,
        consumptionPer100km: 16,
      );
      final chart = weeklySavings(
        trips: [
          rideOn(DateTime(2026, 7, 8), 'anna', ['dora']),
          rideOn(DateTime(2026, 7, 15), 'dora', ['anna']),
        ],
        persons: [anna, stromer],
        settings: settings,
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.6),
          week(2026, 29, PriceSeries.diesel, 1.6),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 29),
      );

      expect(chart.estimatedFrom, isEmpty);
      expect(chart.groupEstimatedFrom, isNull);
    });

    test('sind alle Fahrwochen gemessen, ist nichts geschätzt', () {
      final chart = weeklySavings(
        trips: trips,
        persons: persons,
        settings: settings,
        storedPrices: [
          week(2026, 28, PriceSeries.diesel, 1.6),
          week(2026, 29, PriceSeries.diesel, 1.6),
          week(2026, 28, PriceSeries.e5, 1.8),
          week(2026, 29, PriceSeries.e5, 1.8),
        ],
        from: const IsoWeek(2026, 28),
        to: const IsoWeek(2026, 30),
      );

      expect(
        chart.estimatedFrom,
        isEmpty,
        reason:
            'KW 30 ist zwar überbrückt, aber dort fuhr niemand — ihr Preis '
            'geht in keine Summe ein.',
      );
      expect(chart.groupEstimatedFrom, isNull);
    });
  });

  group('savingsWindow', () {
    test('ohne Fahrten gibt es kein Fenster', () {
      expect(savingsWindow(const []), isNull);
    });

    test('endet bei der letzten Fahrt, nicht heute', () {
      // Eine kumulierte Kurve liefe sonst als waagerechte Linie durch jede
      // fahrfreie Zeit und behauptete Aktivität, wo keine war.
      final (_, to) = savingsWindow([
        tripOn(DateTime(2026, 7, 8)),
        tripOn(DateTime(2026, 7, 15)),
      ])!;

      expect(to, const IsoWeek(2026, 29));
    });

    test('reicht bis zur ersten Fahrt zurück', () {
      final (from, _) = savingsWindow([
        tripOn(DateTime(2023, 1, 11)),
        tripOn(DateTime(2026, 7, 15)),
      ])!;

      expect(from, const IsoWeek(2023, 2));
    });

    test('eine junge Gruppe bekommt trotzdem eine Kurve', () {
      final (from, to) = savingsWindow([tripOn(DateTime(2026, 7, 15))])!;

      expect(weeksBetween(from, to), hasLength(8));
    });
  });
}

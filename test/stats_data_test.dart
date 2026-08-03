/// stats_data_test.dart – Aggregationen der Statistik-Seite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/stats_data.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';

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

/// Ohne Verbrauch gibt es keine Ersparnis und kein CO₂ — nicht geschätzt.
const clara = Person(id: 'clara', name: 'Clara', active: true);

/// E-Auto: spart Geld, aber bewusst kein CO₂ (Faktor 0).
const dora = Person(
  id: 'dora',
  name: 'Dora',
  active: true,
  energyType: EnergyType.electric,
  consumptionPer100km: 18,
);

const settings = AppSettings();

/// Montag der KW 30/2026 — fester Anker wie in den übrigen Chart-Tests.
final monday30 = DateTime(2026, 7, 20);

void main() {
  group('weeklyTripBars', () {
    test('zwölf Wochen bis heute, Null-Wochen bleiben stehen', () {
      final bars = weeklyTripBars([
        tripOn(DateTime(2026, 7, 8)), // KW 28
        tripOn(DateTime(2026, 7, 20)), // KW 30
      ], now: monday30)!;

      expect(bars.weeks, hasLength(12));
      expect(
        bars.weeks.last,
        const IsoWeek(2026, 30),
        reason: 'die Achse endet in der laufenden Woche',
      );
      expect(
        bars.counts[bars.weeks.indexOf(const IsoWeek(2026, 29))],
        0,
        reason:
            'eine fahrfreie Woche steht als Null im Bild — sie auszulassen '
            'stauchte den Zeitraum',
      );
    });

    test('der Durchschnitt rechnet die Null-Wochen mit', () {
      final bars = weeklyTripBars([
        tripOn(DateTime(2026, 7, 8)),
        tripOn(DateTime(2026, 7, 9)),
        tripOn(DateTime(2026, 7, 20)),
      ], now: monday30)!;

      expect(
        bars.average,
        closeTo(3 / 12, 1e-9),
        reason:
            'die Ø-Linie muss zu den gezeigten Balken passen, nicht zu einer '
            'anderen Grundgesamtheit',
      );
    });

    test('der Rekord im Fenster markiert seinen Balken', () {
      final bars = weeklyTripBars([
        tripOn(DateTime(2026, 7, 8)),
        tripOn(DateTime(2026, 7, 9)),
        tripOn(DateTime(2026, 7, 10)),
        tripOn(DateTime(2026, 7, 20)),
      ], now: monday30)!;

      expect(bars.recordWeek, const IsoWeek(2026, 28));
      expect(bars.recordCount, 3);
      expect(bars.recordIndex, bars.weeks.indexOf(const IsoWeek(2026, 28)));
    });

    test('der Rekord außerhalb des Fensters markiert keinen Balken', () {
      final bars = weeklyTripBars([
        // KW 3/2025 — vier Fahrten, weit vor dem 12-Wochen-Fenster.
        tripOn(DateTime(2025, 1, 13)),
        tripOn(DateTime(2025, 1, 14)),
        tripOn(DateTime(2025, 1, 15)),
        tripOn(DateTime(2025, 1, 16)),
        tripOn(DateTime(2026, 7, 20)),
      ], now: monday30)!;

      expect(
        bars.recordIndex,
        isNull,
        reason:
            'der höchste Balken im Ausschnitt ist nicht der Rekord — ihn zu '
            'markieren behauptete es',
      );
      expect(bars.recordWeek, const IsoWeek(2025, 3));
      expect(bars.recordCount, 4);
    });

    test('eine künftige Fahrt zählt nicht', () {
      final bars = weeklyTripBars([
        tripOn(DateTime(2026, 7, 20)),
        // Der 2027-Vertipper aus dem Erst-Import (dieselbe Lehre wie #160).
        tripOn(DateTime(2027, 11, 19)),
        tripOn(DateTime(2027, 11, 20)),
      ], now: monday30)!;

      expect(bars.weeks.last, const IsoWeek(2026, 30));
      expect(
        bars.recordWeek,
        const IsoWeek(2026, 30),
        reason: 'auch der Rekord darf nicht aus der Zukunft kommen',
      );
    });

    test('bei Gleichstand hält die früheste Woche den Rekord', () {
      final bars = weeklyTripBars([
        tripOn(DateTime(2026, 7, 8)), // KW 28
        tripOn(DateTime(2026, 7, 15)), // KW 29
      ], now: monday30)!;

      expect(
        bars.recordWeek,
        const IsoWeek(2026, 28),
        reason: 'sie hat den Rekord aufgestellt, die spätere nur eingestellt',
      );
    });

    test('ohne Fahrt im Fenster gibt es keine Karte', () {
      expect(weeklyTripBars(const [], now: monday30), isNull);
      expect(
        weeklyTripBars([tripOn(DateTime(2025, 1, 13))], now: monday30),
        isNull,
        reason: 'nur uralte Fahrten — zwölf leere Balken sagen nichts',
      );
    });
  });

  group('weekShortLabel', () {
    test('im Referenzjahr reicht die Wochennummer', () {
      expect(
        weekShortLabel(
          const IsoWeek(2026, 27),
          reference: const IsoWeek(2026, 30),
        ),
        'KW 27',
      );
    });

    test('ein anderes Jahr steht dabei', () {
      expect(
        weekShortLabel(
          const IsoWeek(2024, 27),
          reference: const IsoWeek(2026, 30),
        ),
        'KW 27/2024',
        reason: 'ohne Jahreszahl liest sich eine alte Woche wie eine aktuelle',
      );
    });
  });

  group('savingsMilestone', () {
    SavingsChart chart(List<double> group, {double carriedOver = 0}) =>
        SavingsChart(
          weeks: [for (var i = 0; i < group.length; i++) IsoWeek(2026, i + 1)],
          group: group,
          perPerson: const {},
          carriedOver: carriedOver,
          estimatedFrom: const {},
          tripCounts: [for (final _ in group) 0],
        );

    test('unter 50 € gibt es keinen Meilenstein', () {
      expect(savingsMilestone(chart([10, 30, 49])), isNull);
    });

    test('nennt den größten erreichten runden Betrag und seine Woche', () {
      final milestone = savingsMilestone(chart([20, 60, 120]))!;

      expect(milestone.amount, 100);
      expect(
        milestone.weekIndex,
        2,
        reason: 'die Woche der Erst-Überschreitung, nicht die letzte',
      );
    });

    test('die Leiter läuft 50, 100, 250, 500 …', () {
      expect(savingsMilestone(chart([60]))!.amount, 50);
      expect(savingsMilestone(chart([260]))!.amount, 250);
      expect(savingsMilestone(chart([700]))!.amount, 500);
      expect(savingsMilestone(chart([1200]))!.amount, 1000);
    });
  });

  group('yearEndProjection', () {
    SavingsChart chart(List<double> group) => SavingsChart(
      weeks: [for (var i = 0; i < group.length; i++) IsoWeek(2026, i + 1)],
      group: group,
      perPerson: const {},
      carriedOver: 0,
      estimatedFrom: const {},
      tripCounts: [for (final _ in group) 0],
    );

    test('rechnet das Tempo auf die Restwochen des Jahres hoch', () {
      // 8 Wochen à +10 €; KW 30 von 53 (2026 hat 53 ISO-Wochen) → 23 Wochen
      // übrig → 80 + 230.
      final projection = yearEndProjection(
        chart([10, 20, 30, 40, 50, 60, 70, 80]),
        now: monday30,
      );

      expect(projection, closeTo(310, 1e-9));
    });

    test('ohne positives Tempo gibt es keine Hochrechnung', () {
      expect(
        yearEndProjection(chart([80, 80, 80, 80, 80]), now: monday30),
        isNull,
        reason: 'eine flache Kurve hochzurechnen wiederholte nur die Summe',
      );
    });

    test('unter vier Kurven-Wochen gibt es keine Hochrechnung', () {
      expect(yearEndProjection(chart([10, 20, 30]), now: monday30), isNull);
    });

    test('in der letzten Woche des Jahres gibt es nichts hochzurechnen', () {
      expect(
        yearEndProjection(
          chart([10, 20, 30, 40, 50]),
          now: DateTime(2026, 12, 28),
        ),
        isNull,
      );
    });
  });

  group('tankEquivalents', () {
    test('teilt durch 50 Liter zum Diesel-Preis aus den Parametern', () {
      // Default 1,70 €/l → 85 € je Tankfüllung.
      expect(tankEquivalents(170, settings), 2);
      expect(tankEquivalents(84, settings), 0);
      expect(tankEquivalents(0, settings), 0);
    });
  });

  group('CO₂', () {
    test('spiegelt savedCostsFor — dieselbe Formel, kg/l statt €/l', () {
      final co2 = savedCo2KgFor(person: anna, days: 2, commuteKm: 30);
      final costs = savedCostsFor(
        person: anna,
        pricePerUnit: kCo2PerLiterDiesel,
        days: 2,
        commuteKm: 30,
      );

      expect(co2, closeTo(costs, 1e-9));
      expect(
        co2,
        closeTo(6 * 2.65 * 2 * 30 * 2 / 100, 1e-9),
        reason: 'Verbrauch × kg/l × Tage × km × 2 / 100',
      );
    });

    test('E-Auto und fehlender Verbrauch tragen 0 bei', () {
      expect(
        savedCo2KgFor(person: dora, days: 5, commuteKm: 30),
        0,
        reason: 'E-Autos sind außen vor — kein geschätzter Strommix',
      );
      expect(savedCo2KgFor(person: clara, days: 5, commuteKm: 30), 0);
    });

    test('die Gruppensumme zählt Mitfahr-Tage inkl. 1-way voll', () {
      final trips = [
        rideOn(DateTime(2026, 7, 8), 'ben', ['anna']),
        rideOn(DateTime(2026, 7, 9), 'ben', ['anna']),
      ];
      final stats = computeStats(trips, settings);

      final expected = savedCo2KgFor(person: anna, days: 2, commuteKm: 30);
      expect(
        groupSavedCo2Kg(stats, const [anna, ben, clara], settings),
        closeTo(expected, 1e-9),
        reason: 'nur Mitfahrten sparen; Ben fuhr selbst',
      );
    });

    test('das Etappenziel ist der nächste Wert der 10/25/50-Leiter', () {
      expect(nextCo2Milestone(0), 10);
      expect(nextCo2Milestone(10), 25);
      expect(nextCo2Milestone(87), 100);
      expect(nextCo2Milestone(250), 500);
    });

    test('vermiedene Solo-km zählen genau die CO₂-Personen', () {
      final trips = [
        rideOn(DateTime(2026, 7, 8), 'ben', ['anna', 'clara', 'dora']),
      ];
      final stats = computeStats(trips, settings);

      expect(
        avoidedSoloKm(stats, const [anna, ben, clara, dora], settings),
        closeTo(60, 1e-9),
        reason:
            'nur Anna (Diesel) zählt: Clara hat keinen Verbrauch, Dora fährt '
            'elektrisch — die Kachel erklärt die Ring-Zahl, beide müssen '
            'dieselben Personen zählen',
      );
    });
  });

  group('weekdayDriveMatrix', () {
    test('zählt gefahrene Tage je Person und Wochentag', () {
      final matrix = weekdayDriveMatrix([
        rideOn(DateTime(2026, 7, 6), 'anna', ['ben']), // Mo
        rideOn(DateTime(2026, 7, 13), 'anna', ['ben']), // Mo
        rideOn(DateTime(2026, 7, 8), 'ben', ['anna']), // Mi
      ])!;

      expect(matrix.weekdays, [1, 2, 3, 4, 5]);
      expect(matrix.personIds, [
        'anna',
        'ben',
      ], reason: 'absteigend nach Fahr-Tagen');
      expect(matrix.counts[0][0], 2, reason: 'Anna montags');
      expect(matrix.counts[1][2], 1, reason: 'Ben mittwochs');
      expect(matrix.max, 2);
    });

    test('eine Samstagsfahrt öffnet die Sa-Spalte', () {
      final matrix = weekdayDriveMatrix([
        rideOn(DateTime(2026, 7, 6), 'anna', ['ben']), // Mo
        rideOn(DateTime(2026, 7, 11), 'anna', ['ben']), // Sa
      ])!;

      expect(
        matrix.weekdays,
        [1, 2, 3, 4, 5, 6],
        reason:
            'keine dauerhaft leere Spalte, aber auch keine versteckte Fahrt',
      );
    });

    test('Solo-Fahrten zählen nicht', () {
      expect(
        weekdayDriveMatrix([rideOn(DateTime(2026, 7, 6), 'anna', [])]),
        isNull,
        reason: 'eine Solo-Fahrt ist kein Fahren für die Gemeinschaft (#61)',
      );
    });
  });

  group('weekdayDominance', () {
    WeekdayMatrix matrixOf(List<Trip> trips) => weekdayDriveMatrix(trips)!;

    test('findet den dominierten Wochentag', () {
      final dominance = weekdayDominance(
        matrixOf([
          rideOn(DateTime(2026, 6, 3), 'ben', ['anna']), // Mi
          rideOn(DateTime(2026, 6, 10), 'ben', ['anna']), // Mi
          rideOn(DateTime(2026, 6, 17), 'ben', ['anna']), // Mi
          rideOn(DateTime(2026, 6, 24), 'ben', ['anna']), // Mi
          rideOn(DateTime(2026, 7, 1), 'anna', ['ben']), // Mi
        ]),
      )!;

      expect(dominance.personId, 'ben');
      expect(dominance.weekday, DateTime.wednesday);
      expect(dominance.count, 4);
      expect(dominance.share, closeTo(0.8, 1e-9));
    });

    test('unter vier Fahrten gibt es keine Aussage', () {
      expect(
        weekdayDominance(
          matrixOf([
            rideOn(DateTime(2026, 6, 3), 'ben', ['anna']),
            rideOn(DateTime(2026, 6, 10), 'ben', ['anna']),
            rideOn(DateTime(2026, 6, 17), 'ben', ['anna']),
          ]),
        ),
        isNull,
        reason: 'drei Fahrten sind kein Muster',
      );
    });

    test('unter 60 % Anteil gibt es keine Aussage', () {
      expect(
        weekdayDominance(
          matrixOf([
            rideOn(DateTime(2026, 6, 3), 'ben', ['anna']),
            rideOn(DateTime(2026, 6, 10), 'ben', ['anna']),
            rideOn(DateTime(2026, 6, 17), 'ben', ['anna']),
            rideOn(DateTime(2026, 6, 24), 'ben', ['anna']),
            rideOn(DateTime(2026, 7, 1), 'anna', ['ben']),
            rideOn(DateTime(2026, 7, 8), 'anna', ['ben']),
            rideOn(DateTime(2026, 7, 15), 'anna', ['ben']),
          ]),
        ),
        isNull,
        reason: '4 von 7 sind kein „fast immer"',
      );
    });
  });
}

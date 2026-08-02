/// stats_insights_test.dart – die Insight-Karten der Statistik-Seite.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/stats_insights.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/trip.dart';

/// Ein Fahrtag: [driver] fährt, alle [riders] fahren voll mit.
Trip rideOn(DateTime date, String driver, List<String> riders) => Trip(
  id: '$date-$driver',
  date: date,
  participations: {
    driver: ParticipationStatus.driver,
    for (final rider in riders) rider: ParticipationStatus.passenger,
  },
);

const settings = AppSettings();
const names = {'anna': 'Anna', 'ben': 'Ben'};

/// Montag der KW 30/2026 — fester Anker wie in den übrigen Chart-Tests.
final monday30 = DateTime(2026, 7, 20);

PersonStats statsWithDays(String id, int days) => PersonStats(
  personId: id,
  driven: days,
  ridden: 0,
  oneWay: 0,
  carried: 0,
  points: 0,
);

SavingsChart chartOf(List<double> group, {double carriedOver = 0}) =>
    SavingsChart(
      weeks: [for (var i = 0; i < group.length; i++) IsoWeek(2026, i + 1)],
      group: group,
      perPerson: const {},
      carriedOver: carriedOver,
      estimatedFrom: const {},
      tripCounts: [for (final _ in group) 0],
    );

void main() {
  group('distanceInsight', () {
    test('nennt Personen-km und das erreichte Ziel', () {
      // 4 Anwesenheits-Tage × 60 km = 240 km — über München (230), unter Wien.
      final trips = [
        rideOn(DateTime(2026, 7, 8), 'anna', ['ben']),
        rideOn(DateTime(2026, 7, 9), 'anna', ['ben']),
      ];
      final insight = distanceInsight(computeStats(trips, settings), settings)!;

      expect(
        insight.value,
        '240 km seid ihr zusammen gefahren — einmal bis München.',
        reason:
            'Personen-km wie die Kachel auf der Übersicht — die Formulierung '
            '„zusammen" trägt das mit',
      );
    });

    test('unter dem ersten Ziel gibt es keine Karte', () {
      final trips = [
        rideOn(DateTime(2026, 7, 8), 'anna', ['ben']),
      ];
      expect(distanceInsight(computeStats(trips, settings), settings), isNull);
    });

    test('oberhalb der Städte übernehmen Erde und Mond', () {
      final earth = distanceInsight({
        'anna': statsWithDays('anna', 700), // 42 000 km
      }, settings)!;
      expect(earth.value, contains('einmal um die Erde'));

      final moon = distanceInsight({
        'anna': statsWithDays('anna', 6500), // 390 000 km
      }, settings)!;
      expect(moon.value, contains('einmal bis zum Mond'));
    });
  });

  group('bestWeekInsight', () {
    test('findet die Woche mit der größten Ersparnis', () {
      final insight = bestWeekInsight(chartOf([10, 30, 35]))!;

      // Erwartung mit demselben Formatter: `NumberFormat.currency` setzt ein
      // geschütztes Leerzeichen vor das €-Zeichen.
      final euro = NumberFormat.currency(locale: 'de', symbol: '€');
      expect(
        insight.value,
        'KW 2: ${euro.format(20)} gespart — eure stärkste Woche.',
        reason: 'die Differenzen sind 10 / 20 / 5 — die Mitte gewinnt',
      );
    });

    test('der Übertrag zählt nicht als Ersparnis-Woche', () {
      expect(
        bestWeekInsight(chartOf([5, 5], carriedOver: 5)),
        isNull,
        reason:
            'die Kurve startet auf dem Übertrag — er ist keine Woche, in der '
            'gespart wurde',
      );
    });

    test('eine alte Woche trägt ihr Jahr', () {
      const chart = SavingsChart(
        weeks: [IsoWeek(2025, 52), IsoWeek(2026, 1)],
        group: [20, 25],
        perPerson: {},
        carriedOver: 0,
        estimatedFrom: {},
        tripCounts: [0, 0],
      );

      expect(bestWeekInsight(chart)!.value, startsWith('KW 52/2025:'));
    });
  });

  group('kmHeroInsight', () {
    test('kürt die Person mit den meisten Fahr-Tagen des Monats', () {
      final trips = [
        rideOn(DateTime(2026, 7, 6), 'anna', ['ben']),
        rideOn(DateTime(2026, 7, 8), 'anna', ['ben']),
        rideOn(DateTime(2026, 7, 13), 'anna', ['ben']),
        rideOn(DateTime(2026, 7, 15), 'ben', ['anna']),
      ];
      final insight = kmHeroInsight(trips, settings, names, now: monday30)!;

      expect(insight.title, 'Kilometerheld · Juli');
      expect(insight.value, 'Anna — 180 km am Steuer. 🏆');
    });

    test('am Monatsanfang springt der Vormonat ein', () {
      final trips = [
        rideOn(DateTime(2026, 7, 6), 'ben', ['anna']),
      ];
      final insight = kmHeroInsight(
        trips,
        settings,
        names,
        now: DateTime(2026, 8, 1),
      )!;

      expect(
        insight.title,
        'Kilometerheld · Juli',
        reason: 'ein leerer laufender Monat hätte sonst nie einen Helden',
      );
      expect(insight.value, contains('Ben'));
    });

    test('Solo-Fahrten machen niemanden zum Helden', () {
      final trips = [rideOn(DateTime(2026, 7, 6), 'anna', [])];
      expect(kmHeroInsight(trips, settings, names, now: monday30), isNull);
    });
  });

  group('streakInsight', () {
    List<Trip> ridesOn(List<DateTime> dates) => [
      for (final date in dates) rideOn(date, 'anna', ['ben']),
    ];

    test('Kalenderlücken brechen die Serie nicht', () {
      final insight = streakInsight(
        ridesOn([
          DateTime(2026, 7, 6),
          DateTime(2026, 7, 8),
          DateTime(2026, 7, 13), // Wochenende dazwischen
          DateTime(2026, 7, 15),
          DateTime(2026, 7, 20),
        ]),
      )!;

      expect(
        insight.value,
        '5 Fahrtage in Folge ohne Solo-Fahrt — die Serie läuft noch.',
        reason: 'ein fahrfreier Tag ist kein Scheitern',
      );
    });

    test('ein Solo-Tag bricht die Serie', () {
      final trips = [
        ...ridesOn([
          DateTime(2026, 7, 1),
          DateTime(2026, 7, 2),
          DateTime(2026, 7, 3),
          DateTime(2026, 7, 6),
          DateTime(2026, 7, 7),
        ]),
        rideOn(DateTime(2026, 7, 8), 'anna', []), // solo
        ...ridesOn([DateTime(2026, 7, 9), DateTime(2026, 7, 10)]),
      ];
      final insight = streakInsight(trips)!;

      expect(
        insight.value,
        '5 Fahrtage in Folge ohne Solo-Fahrt.',
        reason: 'die Serie endete am Solo-Tag — kein „läuft noch"',
      );
    });

    test('unter fünf Tagen ist eine Serie keine Geschichte', () {
      expect(
        streakInsight(
          ridesOn([
            DateTime(2026, 7, 6),
            DateTime(2026, 7, 7),
            DateTime(2026, 7, 8),
            DateTime(2026, 7, 9),
          ]),
        ),
        isNull,
      );
    });
  });

  group('rotateInsights', () {
    List<StatsInsight> available(int n) => [
      for (var i = 0; i < n; i++)
        StatsInsight(
          kind: StatsInsightKind.values[i % StatsInsightKind.values.length],
          title: 'T$i',
          value: 'V$i',
        ),
    ];

    test('dieselbe Woche zeigt dieselben Karten', () {
      final a = rotateInsights(available(4), now: monday30);
      final b = rotateInsights(
        available(4),
        now: DateTime(2026, 7, 24), // Freitag derselben Woche
      );

      expect([for (final i in a) i.title], [for (final i in b) i.title]);
      expect(a, hasLength(2));
    });

    test('die nächste Woche rückt weiter', () {
      final thisWeek = rotateInsights(available(4), now: monday30);
      final nextWeek = rotateInsights(available(4), now: DateTime(2026, 7, 27));

      expect(
        [for (final i in nextWeek) i.title],
        isNot([for (final i in thisWeek) i.title]),
        reason: 'wöchentlich wechselnd — das ist das Versprechen der Sektion',
      );
    });

    test('weniger Karten als Plätze zeigen alle', () {
      expect(rotateInsights(available(1), now: monday30), hasLength(1));
    });
  });
}

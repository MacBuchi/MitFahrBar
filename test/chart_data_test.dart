/// chart_data_test.dart – Aggregation der Startseiten-Diagramme.
library;

import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

Trip tripOn(DateTime date) =>
    Trip(id: date.toIso8601String(), date: date, participations: const {});

void main() {
  // Fester Bezugspunkt: sonst wandert das Fenster mit dem Testdatum.
  final now = DateTime(2026, 7, 20);

  group('tripsPerMonth', () {
    test('liefert genau die letzten Monate, endend im aktuellen', () {
      final buckets = tripsPerMonth(const [], months: 12, now: now);

      expect(buckets, hasLength(12));
      expect(buckets.first.year, 2025);
      expect(buckets.first.month, 8);
      expect(buckets.last.year, 2026);
      expect(buckets.last.month, 7);
    });

    test('zählt Fahrten in ihren Monat', () {
      final buckets = tripsPerMonth(
        [
          tripOn(DateTime(2026, 7, 1)),
          tripOn(DateTime(2026, 7, 31)),
          tripOn(DateTime(2026, 6, 15)),
        ],
        months: 12,
        now: now,
      );

      expect(buckets.last.trips, 2, reason: 'zwei Fahrten im Juli');
      expect(buckets[buckets.length - 2].trips, 1);
    });

    test('Monate ohne Fahrt bleiben enthalten und stehen auf 0', () {
      final buckets = tripsPerMonth(
        [tripOn(DateTime(2026, 7, 1))],
        months: 3,
        now: now,
      );

      expect(buckets.map((b) => b.trips), [0, 0, 1]);
    });

    test('Fahrten außerhalb des Fensters werden nicht gezählt', () {
      final buckets = tripsPerMonth(
        [
          tripOn(DateTime(2024, 1, 5)), // deutlich davor
          tripOn(DateTime(2026, 4, 5)), // im Fenster
        ],
        months: 6,
        now: now,
      );

      expect(buckets.fold<int>(0, (sum, b) => sum + b.trips), 1);
    });

    test('Jahreswechsel verschiebt die Monate korrekt', () {
      final buckets = tripsPerMonth(
        const [],
        months: 3,
        now: DateTime(2026, 1, 15),
      );

      expect(buckets.map((b) => '${b.year}-${b.month}'), [
        '2025-11',
        '2025-12',
        '2026-1',
      ]);
    });

    test('ohne Monate gibt es nichts zu zeichnen', () {
      expect(tripsPerMonth(const [], months: 0, now: now), isEmpty);
    });
  });

  // Das Zeitfenster des Monats-Diagramms (#119): so weit zurück, wie die
  // Gruppe wirklich fährt.
  group('monthsToCover', () {
    test('ohne Fahrten bleibt es beim Jahr', () {
      expect(monthsToCover(const [], now), 12);
    });

    test('kurze Historie wird nicht gestaucht', () {
      expect(
        monthsToCover([tripOn(DateTime(2026, 5, 4))], now),
        12,
        reason:
            'Zwei Säulen nebeneinander wären kein Diagramm — leere Monate '
            'gehören ins Bild.',
      );
    });

    test('lange Historie reicht bis zur ersten Fahrt', () {
      // Januar 2023 bis Juli 2026 sind 43 Monate einschließlich beider.
      expect(monthsToCover([tripOn(DateTime(2023, 1, 9))], now), 43);
    });

    test('ein Ausreißer weit zurück wird gekappt', () {
      expect(
        monthsToCover([tripOn(DateTime(2009, 3, 1))], now),
        60,
        reason:
            'Ein falsch getipptes Jahr darf die Achse nicht dauerhaft '
            'strecken und alle echten Monate an den Rand quetschen.',
      );
    });

    test('eine Fahrt in der Zukunft verlängert das Fenster nicht', () {
      expect(
        monthsToCover([tripOn(DateTime(2027, 11, 19))], now),
        12,
        reason:
            'Genau so ein Datum steckt im Erst-Import — gezeichnet wird es '
            'ohnehin nicht, also darf es auch nichts verschieben.',
      );
    });
  });

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
}

/// chart_data_test.dart – Aggregation der Startseiten-Diagramme.
library;

import 'package:fahrgemeinschaft/core/chart_data.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
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

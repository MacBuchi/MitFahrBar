/// fairness_test.dart – Unit-Tests der Punkte-Logik + Excel-Backtest.
library;

import 'dart:convert';
import 'dart:io';

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/models/app_settings.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = AppSettings();

Trip trip(String date, Map<String, ParticipationStatus> parts) =>
    Trip(id: date, date: DateTime.parse(date), participations: parts);

void main() {
  group('computeStats', () {
    test('Punkte: mitgenommen − mitgefahren − 0,5 × 1-way', () {
      final trips = [
        // A fährt, B+C voll dabei, D nur eine Richtung.
        trip('2026-01-05', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
          'c': ParticipationStatus.passenger,
          'd': ParticipationStatus.oneWay,
        }),
        // B fährt, A dabei.
        trip('2026-01-06', {
          'b': ParticipationStatus.driver,
          'a': ParticipationStatus.passenger,
        }),
      ];
      final stats = computeStats(trips, settings);

      expect(stats['a']!.carried, 2.5);
      expect(stats['a']!.points, 1.5); // 2.5 mitgenommen − 1 Mitfahrt
      expect(stats['b']!.points, 0); // 1 mitgenommen − 1 Mitfahrt
      expect(stats['c']!.points, -1);
      expect(stats['d']!.points, -0.5);
      expect(stats['a']!.driveShare, 0.5);
      expect(stats['a']!.lastDrive, DateTime.parse('2026-01-05'));
    });

    test('Punktesumme über alle Personen ist null (zero-sum)', () {
      final trips = [
        trip('2026-01-05', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
          'c': ParticipationStatus.oneWay,
        }),
        trip('2026-01-06', {
          'c': ParticipationStatus.driver,
          'a': ParticipationStatus.oneWay,
        }),
      ];
      final stats = computeStats(trips, settings);
      final sum = stats.values.fold<double>(0, (acc, s) => acc + s.points);
      expect(sum, closeTo(0, 1e-9));
    });
  });

  group('rankPresent / suggestDriver', () {
    test('reine Punkte-Sicht: wenigste Punkte ist dran', () {
      final trips = [
        trip('2026-01-05', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        }),
        trip('2026-01-06', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        }),
      ];
      final stats = computeStats(trips, settings);
      const pointsOnly = AppSettings(pointsWeight: 1.0);
      expect(suggestDriver(['a', 'b'], stats, pointsOnly), 'b');
    });

    test(
      'Konzept-Beispiel: Vielmitnehmer ist an kleinen Tagen wieder dran',
      () {
        // A: +12 Punkte, aber nur 10 % Fahranteil (fährt selten, dann voll).
        // B: −3 Punkte, 25 % Fahranteil.
        // Nach reinen Punkten wäre immer B dran; kombiniert entsteht
        // Gleichstand und es fährt, wessen letzte Fahrt länger her ist (A).
        final aStats = PersonStats(
          personId: 'a',
          driven: 10,
          ridden: 88,
          oneWay: 0,
          carried: 100, // 100 − 88 = +12 Punkte
          points: 12,
          lastDrive: DateTime.parse('2026-01-02'),
        );
        final bStats = PersonStats(
          personId: 'b',
          driven: 20,
          ridden: 60,
          oneWay: 0,
          carried: 57, // 57 − 60 = −3 Punkte
          points: -3,
          lastDrive: DateTime.parse('2026-07-01'),
        );
        final ranking = rankPresent(
          ['a', 'b'],
          {'a': aStats, 'b': bStats},
          settings,
        );

        expect(ranking.first.personId, 'a');
        expect(
          ranking.first.score,
          ranking.last.score,
          reason: 'Rangsumme ist bei diesem Beispiel gleich',
        );
      },
    );

    test('nie Gefahrene stehen bei Gleichstand vorn', () {
      final stats = <String, PersonStats>{};
      final ranking = rankPresent(['x', 'y'], stats, settings);
      expect(ranking, hasLength(2));
      expect(ranking.first.personId, 'x'); // deterministisch alphabetisch
    });

    test('leere Auswahl liefert keinen Vorschlag', () {
      expect(suggestDriver([], {}, settings), isNull);
    });
  });

  group('Excel-Backtest (echte Historie aus .donotsync)', () {
    final file = File('.donotsync/seed/seed.json');

    test('Punkte und Zähler entsprechen exakt der Excel-Auswertung', () {
      if (!file.existsSync()) {
        markTestSkipped('seed.json nicht vorhanden – Backtest übersprungen');
        return;
      }
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final trips = [
        for (final (i, t) in (data['trips'] as List).indexed)
          Trip(
            id: 'seed-$i',
            date: DateTime.parse((t as Map<String, dynamic>)['date'] as String),
            participations: {
              for (final e
                  in (t['participations'] as Map<String, dynamic>).entries)
                e.key: ParticipationStatus.values.byName(e.value as String),
            },
          ),
      ];
      final stats = computeStats(trips, settings);

      // Referenzwerte aus Fahrgemeinschaft.xlsx (Stand Juli 2026).
      expect(stats['Christoph']!.driven, 70);
      expect(stats['Christoph']!.ridden, 135);
      expect(stats['Christoph']!.oneWay, 4);
      expect(stats['Christoph']!.carried, closeTo(137, 1e-9));
      expect(stats['Christoph']!.points, closeTo(0, 1e-9));
      expect(stats['Marcus']!.points, closeTo(-5.5, 1e-9));
      expect(stats['Thorsten']!.points, closeTo(-2, 1e-9));

      final sum = stats.values.fold<double>(0, (acc, s) => acc + s.points);
      expect(sum, closeTo(0, 1e-9));
    });
  });
}

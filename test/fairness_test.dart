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

    // lastDrive beantwortet „wann ist die Person zuletzt gefahren", nicht
    // „wann war sie zuletzt dabei". Wer nur mitfährt, hat gar kein lastDrive —
    // wäre also für die Reihenfolge im Fahrten-Editor unsichtbar, obwohl er
    // jeden Tag im Auto sitzt.
    test('lastParticipation zählt jede Rolle, lastDrive nur das Fahren', () {
      final trips = [
        trip('2026-01-05', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        }),
        trip('2026-03-10', {
          'a': ParticipationStatus.passenger,
          'b': ParticipationStatus.driver,
          'c': ParticipationStatus.oneWay,
        }),
      ];
      final stats = computeStats(trips, settings);

      expect(stats['a']!.lastDrive, DateTime.parse('2026-01-05'));
      expect(stats['a']!.lastParticipation, DateTime.parse('2026-03-10'));
      expect(stats['c']!.lastDrive, isNull);
      expect(
        stats['c']!.lastParticipation,
        DateTime.parse('2026-03-10'),
        reason: 'Reine 1-way-Mitfahrer sind trotzdem dabei gewesen.',
      );
    });

    test('participatedRecently zieht die Grenze bei 60 Tagen', () {
      final stats = computeStats([
        trip('2026-03-01', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        }),
      ], settings);

      final justInside = DateTime.parse('2026-04-30'); // 60 Tage später
      final justOutside = DateTime.parse('2026-05-01'); // 61 Tage später

      expect(stats['a']!.participatedRecently(justInside), isTrue);
      expect(stats['a']!.participatedRecently(justOutside), isFalse);
    });

    test('ohne Teilnahme gilt niemand als Stammgast', () {
      const never = PersonStats(
        personId: 'x',
        driven: 0,
        ridden: 0,
        oneWay: 0,
        carried: 0,
        points: 0,
      );
      expect(never.participatedRecently(DateTime.parse('2026-03-01')), isFalse);
    });

    // Issue #61: Eine Fahrt ganz allein ist keine Fahrgemeinschafts-Fahrt.
    // Sie darf in KEINE Kennzahl eingehen — der Fahranteil steuert seit dem
    // Raten-Trim die Planer-Vorschläge, eine Solo-Fahrt würde sie verzerren.
    group('Solo-Fahrten (Issue #61)', () {
      test('eine Solo-Fahrt erzeugt gar keine Statistik', () {
        final stats = computeStats([
          trip('2026-01-05', {'a': ParticipationStatus.driver}),
        ], settings);
        expect(stats, isEmpty);
      });

      test('Solo-Fahrten verändern keine Kennzahl einer echten Fahrt', () {
        final real = trip('2026-01-05', {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        });
        final withSolo = computeStats([
          real,
          trip('2026-01-06', {'a': ParticipationStatus.driver}),
          trip('2026-01-07', {'b': ParticipationStatus.driver}),
        ], settings);
        final without = computeStats([real], settings);

        for (final id in ['a', 'b']) {
          expect(withSolo[id]!.points, without[id]!.points);
          expect(withSolo[id]!.driven, without[id]!.driven);
          expect(withSolo[id]!.driveShare, without[id]!.driveShare);
          expect(withSolo[id]!.quote, without[id]!.quote);
          expect(
            withSolo[id]!.participationDays,
            without[id]!.participationDays,
            reason: 'Auch Kilometer hängen an den Teilnahmetagen.',
          );
        }
        expect(
          withSolo['a']!.lastDrive,
          DateTime.parse('2026-01-05'),
          reason:
              'Die spätere Solo-Fahrt darf lastDrive nicht anfassen — '
              'eine Wahrheit, nicht zwei.',
        );
      });

      test('isSoloTrip erkennt genau die Ein-Personen-Fahrt', () {
        expect(
          isSoloTrip(trip('2026-01-05', {'a': ParticipationStatus.driver})),
          isTrue,
        );
        expect(
          isSoloTrip(
            trip('2026-01-05', {
              'a': ParticipationStatus.driver,
              'b': ParticipationStatus.oneWay,
            }),
          ),
          isFalse,
        );
      });
    });
  });

  group('rankPresent / suggestDriver', () {
    test('Standard ist „nur Punkte" — der Fahranteil steuert nichts', () {
      // Festgenagelt, weil genau das die Entscheidung aus Issue #38 ist:
      // Steht das Gewicht wieder auf 0.5, ändert sich die Reihenfolge
      // stillschweigend für jede Gruppe.
      expect(const AppSettings().pointsWeight, 1.0);
    });

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
      'Konzept-Beispiel: mit „nur Punkte" ist der Vielmitnehmer nicht dran',
      () {
        // Dasselbe Beispiel wie in KONZEPT.md 3.2, jetzt mit dem seit
        // 2026-07-21 gültigen Standard gerechnet.
        // A: +12 Punkte, aber nur 10 % Fahranteil (fährt selten, dann voll).
        // B: −3 Punkte, 25 % Fahranteil.
        // Das ist die getragene Folge von Issue #38: A baut mit vollem Auto
        // ein Polster auf und kommt an kleinen Tagen seltener dran, obwohl
        // der Fahraufwand pro Fahrt derselbe ist.
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

        expect(ranking.first.personId, 'b');
        expect(
          ranking.first.score,
          lessThan(ranking.last.score),
          reason: 'ohne Fahranteil entsteht hier kein Gleichstand mehr',
        );
      },
    );

    test(
      'der Ausgleich bleibt möglich: mit pointsWeight 0.5 kippt es zurück',
      () {
        // Der Mechanismus aus KONZEPT.md 3.2 ist nicht entfernt, nur nicht
        // mehr der Standard. Ohne diesen Test verschwände die Rückfahrkarte
        // unbemerkt, sobald jemand die Formel „aufräumt".
        const balanced = AppSettings(pointsWeight: 0.5);
        final aStats = PersonStats(
          personId: 'a',
          driven: 10,
          ridden: 88,
          oneWay: 0,
          carried: 100,
          points: 12,
          lastDrive: DateTime.parse('2026-01-02'),
        );
        final bStats = PersonStats(
          personId: 'b',
          driven: 20,
          ridden: 60,
          oneWay: 0,
          carried: 57,
          points: -3,
          lastDrive: DateTime.parse('2026-07-01'),
        );
        final ranking = rankPresent(
          ['a', 'b'],
          {'a': aStats, 'b': bStats},
          balanced,
        );

        // Gleichstand der Rangsumme → es fährt, wessen letzte Fahrt länger
        // her ist, also A.
        expect(ranking.first.personId, 'a');
        expect(ranking.first.score, ranking.last.score);
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

  group('findQuoteExtremes', () {
    PersonStats stats(
      String id, {
      required int driven,
      required double carried,
    }) => PersonStats(
      personId: id,
      driven: driven,
      ridden: 0,
      oneWay: 0,
      carried: carried,
      points: 0,
    );

    // Der Fahraufwand ist pro Fahrt gleich, die Punkte sind es nicht: Wer
    // immer vier Leute mitnimmt, sammelt dreimal so schnell. Genau das soll
    // die Markierung auf der Startseite sichtbar machen.
    test('markiert höchste und niedrigste Quote', () {
      final all = {
        'voll': stats('voll', driven: 10, carried: 30), // Quote 3,0
        'mittel': stats('mittel', driven: 10, carried: 15), // Quote 1,5
        'leer': stats('leer', driven: 10, carried: 10), // Quote 1,0
      };
      final extremes = findQuoteExtremes(all.keys, all);

      expect(extremes.fullestId, 'voll');
      expect(extremes.emptiestId, 'leer');
    });

    test('wer zu selten gefahren ist, bekommt keinen Titel', () {
      final all = {
        'neu': stats('neu', driven: 1, carried: 4), // höchste Quote, aber 1x
        'a': stats('a', driven: 10, carried: 20),
        'b': stats('b', driven: 10, carried: 15),
        'c': stats('c', driven: 10, carried: 10),
      };
      final extremes = findQuoteExtremes(all.keys, all);

      expect(
        extremes.fullestId,
        'a',
        reason:
            'Eine einzelne volle Fahrt darf keinen Titel tragen — sonst '
            'wandert er bei jeder Neuanlage hin und her.',
      );
      expect(extremes.emptiestId, 'c');
    });

    test('unter drei Gefahrenen bleibt die Markierung aus', () {
      final all = {
        'a': stats('a', driven: 10, carried: 30),
        'b': stats('b', driven: 10, carried: 10),
      };
      final extremes = findQuoteExtremes(all.keys, all);

      expect(
        extremes.fullestId,
        isNull,
        reason:
            'Bei zwei Personen wäre einer zwangsläufig voll und der andere '
            'leer, ohne dass das etwas aussagt.',
      );
      expect(extremes.emptiestId, isNull);
    });

    test('bei gleicher Quote wird niemand markiert', () {
      final all = {
        'a': stats('a', driven: 10, carried: 20),
        'b': stats('b', driven: 5, carried: 10),
        'c': stats('c', driven: 4, carried: 8),
      };
      final extremes = findQuoteExtremes(all.keys, all);

      expect(extremes.fullestId, isNull);
      expect(extremes.emptiestId, isNull);
    });

    test('wer nie gefahren ist, zählt nicht mit', () {
      final all = {
        'a': stats('a', driven: 10, carried: 30),
        'b': stats('b', driven: 10, carried: 20),
        'c': stats('c', driven: 10, carried: 10),
        'nie': stats('nie', driven: 0, carried: 0), // quote == null
      };
      final extremes = findQuoteExtremes(all.keys, all);

      expect(extremes.emptiestId, 'c');
      expect(extremes.fullestId, 'a');
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

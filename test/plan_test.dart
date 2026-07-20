/// plan_test.dart – Wochenplanung: Vorwärts-Simulation und Übersteuern.
library;

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/models/app_settings.dart';
import 'package:fahrgemeinschaft/models/plan_ride.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = AppSettings();

/// Montag bis Freitag einer festen Woche — unabhängig vom Testdatum.
final week = [for (var i = 0; i < 5; i++) DateTime(2026, 3, 2 + i)];

/// Alle können ganz — der Normalfall in den meisten Tests.
Map<DateTime, Map<String, PlanRide>> allAvailable(Set<String> ids) => {
  for (final day in week) day: {for (final id in ids) id: PlanRide.full},
};

/// Verfügbarkeit für einen einzelnen Tag, mit ausgewählten 1-way-Personen.
Map<String, PlanRide> ride(Set<String> full, {Set<String> oneWay = const {}}) =>
    {
      for (final id in full) id: PlanRide.full,
      for (final id in oneWay) id: PlanRide.oneWay,
    };

void main() {
  group('planWeek', () {
    // Der Kern des Planers. Ohne Vorwärts-Simulation ändert sich die
    // Statistik erst, wenn eine Fahrt wirklich eingetragen wird — und der
    // Vorschlag wäre an allen fünf Tagen derselbe Mensch.
    test('der Vorschlag wechselt über die Woche', () {
      final plan = planWeek(
        dates: week,
        availability: allAvailable({'a', 'b'}),
        overrides: const {},
        trips: const [],
        settings: settings,
      );

      final drivers = [for (final day in plan) day.driverId];
      expect(
        drivers,
        ['a', 'b', 'a', 'b', 'a'],
        reason:
            'Jeder Tag muss gegen die Statistik inklusive der Vortage '
            'gerechnet werden, sonst fährt rechnerisch immer dieselbe Person.',
      );
    });

    test(
      'eine bereits eingetragene Fahrt zählt, wird aber nicht neu geplant',
      () {
        // Montag ist gefahren: a war Fahrer. Dienstag muss deshalb b treffen.
        final plan = planWeek(
          dates: week,
          availability: allAvailable({'a', 'b'}),
          overrides: const {},
          trips: [
            Trip(
              id: 'real',
              date: week.first,
              participations: const {
                'a': ParticipationStatus.driver,
                'b': ParticipationStatus.passenger,
              },
            ),
          ],
          settings: settings,
        );

        expect(plan.first.confirmed, isTrue);
        expect(plan.first.driverId, 'a');
        expect(
          plan.first.suggestedDriverId,
          isNull,
          reason: 'Für einen gefahrenen Tag gibt es nichts mehr vorzuschlagen.',
        );
        expect(
          plan[1].driverId,
          'b',
          reason:
              'Die echte Fahrt steckt bereits in den Statistiken — sie darf '
              'nicht zusätzlich simuliert und damit doppelt gezählt werden.',
        );
      },
    );

    test('ein übersteuerter Fahrer gewinnt gegen den Vorschlag', () {
      final plan = planWeek(
        dates: week,
        availability: allAvailable({'a', 'b'}),
        overrides: {week.first: 'b'},
        trips: const [],
        settings: settings,
      );

      expect(plan.first.suggestedDriverId, 'a');
      expect(plan.first.driverId, 'b');
      expect(plan.first.isOverridden, isTrue);
    });

    // Sonst zeigt der Plan einen Fahrer an, der abgesagt hat.
    test('ein Übersteuern auf jemanden ohne Verfügbarkeit verfällt', () {
      final plan = planWeek(
        dates: week,
        availability: {
          week.first: ride({'a'}),
        },
        overrides: {week.first: 'b'},
        trips: const [],
        settings: settings,
      );

      expect(plan.first.driverId, 'a');
      expect(plan.first.isOverridden, isFalse);
    });

    test('ohne Verfügbarkeit gibt es keinen Vorschlag', () {
      final plan = planWeek(
        dates: week,
        availability: const {},
        overrides: const {},
        trips: const [],
        settings: settings,
      );

      expect(plan, hasLength(5));
      expect(plan.every((d) => d.driverId == null), isTrue);
      expect(plan.every((d) => d.availableIds.isEmpty), isTrue);
    });

    test('die Simulation verfälscht die echten Fahrten nicht', () {
      final real = [
        Trip(
          id: 'real',
          date: DateTime(2026, 1, 5),
          participations: const {
            'a': ParticipationStatus.driver,
            'b': ParticipationStatus.passenger,
          },
        ),
      ];
      planWeek(
        dates: week,
        availability: allAvailable({'a', 'b'}),
        overrides: const {},
        trips: real,
        settings: settings,
      );

      expect(
        real,
        hasLength(1),
        reason: 'planWeek darf die übergebene Fahrtenliste nicht verändern.',
      );
    });
  });

  group('canConfirmPlan', () {
    final today = DateTime(2026, 3, 4, 14, 30);

    test('am Fahrtag selbst ja', () {
      expect(canConfirmPlan(DateTime(2026, 3, 4), today), isTrue);
    });

    test('rückwirkend ja — nachtragen muss möglich bleiben', () {
      expect(canConfirmPlan(DateTime(2026, 3, 2), today), isTrue);
    });

    // Sonst verschiebt eine im Voraus eingetragene Fahrt die Punkte aller
    // anderen für etwas, das noch gar nicht passiert ist.
    test('für morgen nein', () {
      expect(canConfirmPlan(DateTime(2026, 3, 5), today), isFalse);
    });

    test('die Uhrzeit spielt keine Rolle', () {
      expect(
        canConfirmPlan(
          DateTime(2026, 3, 4, 23, 59),
          DateTime(2026, 3, 4, 0, 1),
        ),
        isTrue,
      );
    });
  });

  group('planningWeek', () {
    test('mitten in der Woche liefert Montag bis Freitag', () {
      final mid = DateTime(2026, 3, 4); // Mittwoch
      final days = planningWeek(mid);

      expect(days, hasLength(5));
      expect(days.first.weekday, DateTime.monday);
      expect(days.last.weekday, DateTime.friday);
      expect(days.first.isAfter(mid), isFalse);
    });

    // Am Wochenende ist die laufende Woche gefahren; ein Plan dafür wäre
    // Rückschau statt Planung.
    test('am Wochenende liegt die geplante Woche in der Zukunft', () {
      final saturday = DateTime(2026, 3, 7);
      expect(saturday.weekday, DateTime.saturday);

      final days = planningWeek(saturday);
      expect(days.first.weekday, DateTime.monday);
      expect(
        days.first.isAfter(saturday),
        isTrue,
        reason: 'Sonst plant man den bereits vergangenen Montag.',
      );
    });

    test('der Sonntag gehört noch zur alten Woche, geplant wird die neue', () {
      final sunday = DateTime(2026, 3, 8);
      expect(sunday.weekday, DateTime.sunday);

      final days = planningWeek(sunday);
      expect(days.first, DateTime(2026, 3, 9));
    });
  });

  group('1-way in der Planung', () {
    test(
      'wer nur eine Richtung fährt, wird nicht als Fahrer vorgeschlagen',
      () {
        // b hätte als Nächster fahren müssen (keine Historie, alphabetisch
        // wäre a dran, aber b ist der einzige mit vollem Weg).
        final plan = planWeek(
          dates: [week.first],
          availability: {
            week.first: ride({'b'}, oneWay: {'a'}),
          },
          overrides: const {},
          trips: const [],
          settings: settings,
        );

        expect(plan.first.driverId, 'b');
        expect(plan.first.oneWayIds, {'a'});
        expect(plan.first.availableIds, ['a', 'b']);
      },
    );

    test('sind alle nur eine Richtung unterwegs, gibt es keinen Fahrer', () {
      // Ein halber Weg stellt kein Auto. Lieber kein Vorschlag als einer,
      // der nicht fahren kann.
      final plan = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride(const {}, oneWay: {'a', 'b'}),
        },
        overrides: const {},
        trips: const [],
        settings: settings,
      );

      expect(plan.first.driverId, isNull);
      expect(plan.first.availableIds, ['a', 'b']);
    });

    test('ein Übersteuern auf eine 1-way-Person verfällt', () {
      final plan = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'b'}, oneWay: {'a'}),
        },
        overrides: {week.first: 'a'},
        trips: const [],
        settings: settings,
      );

      expect(plan.first.driverId, 'b', reason: 'a kann an dem Tag nicht');
      expect(plan.first.isOverridden, isFalse);
    });

    test('die Simulation bucht 1-way als halbe Mitfahrt', () {
      // Der Nachweis, dass der Status bis in die Punkte durchschlägt. d hat
      // aus der Historie +1,5 Punkte (eine Fahrt mit einem vollen Mitfahrer
      // und einem 1-way).
      final history = [
        Trip(
          id: 'history',
          date: DateTime(2026, 2, 2),
          participations: const {
            'd': ParticipationStatus.driver,
            'x': ParticipationStatus.passenger,
            'y': ParticipationStatus.oneWay,
          },
        ),
      ];

      // Montag fährt a und nimmt c und e mit; d ist an dem Tag nicht dabei.
      // Als 1-way bringt das a 2 × 0,5 = 1,0 Punkte, als volle Mitfahrt
      // 2 × 1 = 2,0. Am Dienstag stehen a und d zur Wahl — und d liegt mit
      // 1,5 genau dazwischen.
      List<String?> driversFor({required bool halfWay}) {
        final plan = planWeek(
          dates: [week[0], week[1]],
          availability: {
            week[0]: halfWay
                ? ride({'a'}, oneWay: {'c', 'e'})
                : ride({'a', 'c', 'e'}),
            week[1]: ride({'a', 'd'}),
          },
          overrides: const {},
          trips: history,
          settings: settings,
        );
        return [for (final day in plan) day.driverId];
      }

      expect(
        driversFor(halfWay: true),
        ['a', 'a'],
        reason: 'a steht mit 1,0 unter d (1,5) und ist erneut dran.',
      );
      expect(
        driversFor(halfWay: false),
        ['a', 'd'],
        reason:
            'Würde 1-way wie eine volle Mitfahrt gebucht, käme a auf 2,0 '
            'und läge über d — der Dienstag fiele anders aus.',
      );
    });
  });

  group('mostCarryingDriver', () {
    PlannedDay day(DateTime date, String? driver, List<String> available) =>
        PlannedDay(date: date, availableIds: available, driverId: driver);

    test('zählt die Mitfahrer über die ganze Woche', () {
      // a fährt zweimal mit je einem Mitfahrer, b einmal mit dreien.
      final plan = [
        day(week[0], 'a', ['a', 'b']),
        day(week[1], 'a', ['a', 'c']),
        day(week[2], 'b', ['b', 'a', 'c', 'd']),
      ];
      expect(mostCarryingDriver(plan), 'b');
    });

    test('der Fahrer zählt sich nicht selbst', () {
      final plan = [
        day(week[0], 'a', ['a']),
      ];
      expect(
        mostCarryingDriver(plan),
        isNull,
        reason: 'Allein zu fahren ist kein Mitnehmen.',
      );
    });

    test('bei Gleichstand gibt es keine Auszeichnung', () {
      // Eine Auszeichnung, die zwei Namen tragen könnte und sich einen
      // aussucht, wäre schlechter als keine.
      final plan = [
        day(week[0], 'a', ['a', 'b']),
        day(week[1], 'b', ['b', 'a']),
      ];
      expect(mostCarryingDriver(plan), isNull);
    });

    test('ohne Fahrer gibt es nichts zu feiern', () {
      final plan = [
        day(week[0], null, ['a', 'b']),
      ];
      expect(mostCarryingDriver(plan), isNull);
    });

    test('eine 1-way-Mitfahrt zählt als ganzer Kopf', () {
      // Die Auszeichnung feiert ein volles Auto, nicht den Punktestand —
      // ein besetzter Platz ist ein besetzter Platz.
      final plan = [
        PlannedDay(
          date: week[0],
          availableIds: const ['a', 'b', 'c'],
          oneWayIds: const {'b', 'c'},
          driverId: 'a',
        ),
        day(week[1], 'd', ['d', 'e']),
      ];
      expect(mostCarryingDriver(plan), 'a');
    });
  });
}

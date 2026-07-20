/// plan_test.dart – Wochenplanung: Vorwärts-Simulation und Übersteuern.
library;

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/models/app_settings.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter_test/flutter_test.dart';

const settings = AppSettings();

/// Montag bis Freitag einer festen Woche — unabhängig vom Testdatum.
final week = [for (var i = 0; i < 5; i++) DateTime(2026, 3, 2 + i)];

Map<DateTime, Set<String>> allAvailable(Set<String> ids) => {
  for (final day in week) day: ids,
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
          week.first: {'a'},
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
}

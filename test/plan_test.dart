/// plan_test.dart – Wochenplanung: Vorwärts-Simulation und Übersteuern.
library;

import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/seat_choice.dart';
import 'package:mitfahrbar/models/trip.dart';
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

    // Issue #85: Die Gruppe trägt Fahrten meist direkt im Editor ein — dann
    // gibt es keine angetippte Verfügbarkeit, und das Raster zeigte nur den
    // Fahrer. Ein eingetragener Tag muss die Fahrt zeigen, nicht die Planung.
    test('ein eingetragener Tag zeigt alle Teilnehmer der Fahrt (#85)', () {
      final plan = planWeek(
        dates: week,
        // Niemand hat Verfügbarkeit angetippt — die Fahrt kam aus dem Editor.
        availability: const {},
        overrides: const {},
        trips: [
          Trip(
            id: 'real',
            date: week.first,
            participations: const {
              'a': ParticipationStatus.driver,
              'b': ParticipationStatus.passenger,
              'c': ParticipationStatus.oneWay,
            },
          ),
        ],
        settings: settings,
      );

      expect(
        plan.first.availableIds,
        ['a', 'b', 'c'],
        reason:
            'Die Teilnehmer der echten Fahrt gehören ins Raster, auch ohne '
            'angetippte Verfügbarkeit — sonst zeigt der Planer nur den Fahrer.',
      );
      expect(plan.first.oneWayIds, {
        'c',
      }, reason: 'Der 1-way-Status kommt aus der Fahrt.');
      expect(plan.first.driverId, 'a');
    });

    test('bei Widerspruch gewinnt die Fahrt gegen die Planung (#85)', () {
      final plan = planWeek(
        dates: week,
        availability: {
          // b hatte „nur eine Richtung" angetippt, fuhr aber voll mit.
          week.first: ride({'a'}, oneWay: {'b'}),
        },
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

      expect(
        plan.first.oneWayIds,
        isEmpty,
        reason:
            'Wer laut Fahrt voll mitgefahren ist, steht nicht mehr als '
            '„nur eine Richtung" im Raster — die Fahrt ist die Wahrheit.',
      );
    });

    test('ein übersteuerter Fahrer gewinnt gegen den Vorschlag', () {
      final plan = planWeek(
        dates: week,
        availability: allAvailable({'a', 'b'}),
        overrides: {
          week.first: {'b'},
        },
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
        overrides: {
          week.first: {'b'},
        },
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

    // #131: Ab Freitagmittag ist die Woche gedanklich vorbei — Planer und
    // Banner blicken gemeinsam auf die kommende Woche.
    test('der Freitagvormittag gehört noch zur laufenden Woche', () {
      final fridayMorning = DateTime(2026, 3, 6, 11, 59);
      expect(fridayMorning.weekday, DateTime.friday);
      expect(planningWeek(fridayMorning).first, DateTime(2026, 3, 2));
    });

    test('ab Freitag 12 Uhr wird die kommende Woche geplant', () {
      final fridayNoon = DateTime(2026, 3, 6, 12);
      expect(planningWeek(fridayNoon).first, DateTime(2026, 3, 9));
    });
  });

  // Der Tag, den das Banner auf der Übersicht zeigt (#122).
  group('nextRide', () {
    /// Die Standardwoche, alle vier Tage offen und besetzt.
    List<PlannedDay> plan({
      Set<DateTime> confirmed = const {},
      Set<DateTime> empty = const {},
    }) => [
      for (final day in week)
        PlannedDay(
          date: day,
          availableIds: empty.contains(day) ? const [] : const ['a', 'b'],
          oneWayIds: const {},
          suggestedDriverIds: empty.contains(day) ? const [] : const ['a'],
          cars: empty.contains(day)
              ? const []
              : const [
                  PlannedCar(driverId: 'a', fullIds: ['b']),
                ],
          confirmed: confirmed.contains(day),
        ),
    ];

    test('mitten in der Woche steht der laufende Tag vorn', () {
      final wednesday = DateTime(2026, 3, 4);
      expect(nextRide(plan(), wednesday)?.date, wednesday);
    });

    // #131: Der Vormittag gehört der heutigen Fahrt, der Nachmittag der
    // morgigen — gewechselt wird exakt um 12:00.
    test('um 11:59 bleibt der heutige Tag stehen', () {
      final beforeNoon = DateTime(2026, 3, 4, 11, 59);
      expect(nextRide(plan(), beforeNoon)?.date, DateTime(2026, 3, 4));
    });

    test('ab 12 Uhr blickt das Banner auf morgen', () {
      final noon = DateTime(2026, 3, 4, 12);
      expect(nextRide(plan(), noon)?.date, DateTime(2026, 3, 5));
    });

    // Ohne diesen Riegel bliebe das Banner den ganzen Abend auf einem Tag
    // stehen, der längst gefahren und eingetragen ist.
    test('ein eingetragener Tag rückt auf den nächsten weiter', () {
      final wednesday = DateTime(2026, 3, 4);
      final thursday = DateTime(2026, 3, 5);

      expect(
        nextRide(plan(confirmed: {wednesday}), wednesday)?.date,
        thursday,
        reason: 'Die Fahrt existiert — der Tag ist erledigt.',
      );
    });

    test('vergangene Tage der Woche zählen nicht', () {
      final thursday = DateTime(2026, 3, 5);
      expect(nextRide(plan(), thursday)?.date, thursday);
    });

    // „Noch niemand verfügbar" ist keine Fahrt, über die sich etwas sagen
    // ließe — dann lieber den nächsten Tag zeigen, an dem etwas steht.
    test('ein Tag ohne Verfügbare wird übersprungen', () {
      final wednesday = DateTime(2026, 3, 4);
      final thursday = DateTime(2026, 3, 5);

      expect(nextRide(plan(empty: {wednesday}), wednesday)?.date, thursday);
    });

    test('ohne offenen Tag bleibt nichts übrig', () {
      final friday = DateTime(2026, 3, 6);
      expect(nextRide(plan(confirmed: {friday}), friday), isNull);
      expect(nextRide(const [], friday), isNull);
    });

    // Ab Freitagmittag liefert planningWeek die kommende Woche — das Banner
    // zeigt dann deren Montag, statt leer zu bleiben (#131). Am Samstag und
    // Sonntag gilt derselbe Weg.
    test('ab Freitagmittag zeigt das Banner den Montag der neuen Woche', () {
      final fridayNoon = DateTime(2026, 3, 6, 12);
      final nextWeek = [
        for (final day in planningWeek(fridayNoon))
          PlannedDay(
            date: day,
            availableIds: const ['a', 'b'],
            oneWayIds: const {},
            suggestedDriverIds: const ['a'],
            cars: const [
              PlannedCar(driverId: 'a', fullIds: ['b']),
            ],
            confirmed: false,
          ),
      ];

      expect(nextRide(nextWeek, fridayNoon)?.date, DateTime(2026, 3, 9));
    });
  });

  group('isoWeekNumber', () {
    // Der Planer-Kopf zeigt die KW (#84) — ISO 8601: Woche 1 ist die mit
    // dem ersten Donnerstag des Jahres.
    test('Woche 1 beginnt notfalls im alten Jahr', () {
      // Montag, 29.12.2025 — der Donnerstag der Woche ist der 1.1.2026.
      expect(isoWeekNumber(DateTime(2025, 12, 29)), 1);
    });

    test('der 4. Januar liegt immer in Woche 1', () {
      expect(isoWeekNumber(DateTime(2026, 1, 4)), 1);
    });

    test('ein Jahr kann 53 Wochen haben', () {
      // 2020 endete mit KW 53; Neujahr 2021 (Freitag) gehört noch dazu.
      expect(isoWeekNumber(DateTime(2020, 12, 31)), 53);
      expect(isoWeekNumber(DateTime(2021, 1, 1)), 53);
    });

    test('mitten im Jahr stimmt die Nummer', () {
      expect(isoWeekNumber(DateTime(2026, 7, 24)), 30);
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
        overrides: {
          week.first: {'a'},
        },
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

  group('Sitzplätze in der Fahrerwahl', () {
    // Ohne Historie sind alle punktgleich; die Reihenfolge entscheidet dann
    // alphabetisch — a wäre dran. Mit Sitzplätzen muss b gewinnen, weil in
    // as Auto nicht alle passen.
    test('ein Auto mit genug Plätzen wird bevorzugt', () {
      final plan = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c', 'd'}),
        },
        overrides: const {},
        trips: const [],
        settings: settings,
        seats: const {'a': 2, 'b': 5},
      );

      expect(plan.first.driverId, 'b');
    });

    test('passt niemandes Auto allein, wird der Tag aufgeteilt', () {
      // Vier Leute, lauter Zweisitzer: Statt der alten Rückfalllinie
      // („bester Vorschlag trotz zu kleinem Auto") fahren jetzt zwei
      // Autos — genau der Fall, für den Issue #62 gebaut wurde.
      final plan = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c', 'd'}),
        },
        overrides: const {},
        trips: const [],
        settings: settings,
        seats: const {'a': 2, 'b': 2, 'c': 2, 'd': 2},
      );

      expect(plan.first.driverIds, ['a', 'b']);
    });

    test('ohne gepflegte Sitzplätze ändert sich nichts', () {
      List<String?> driversFor(Map<String, int> seats) => [
        for (final day in planWeek(
          dates: week,
          availability: allAvailable({'a', 'b'}),
          overrides: const {},
          trips: const [],
          settings: settings,
          seats: seats,
        ))
          day.driverId,
      ];

      expect(driversFor(const {}), ['a', 'b', 'a', 'b', 'a']);
      expect(
        driversFor(const {'a': 5}),
        driversFor(const {}),
        reason:
            'Ein einzelner gepflegter Wert darf die anderen nicht '
            'aussortieren — sonst bestraft die App unvollständige Daten.',
      );
    });

    test('ein zu kleines Auto schließt nicht vom Übersteuern aus', () {
      // Die Sitzplätze steuern den Vorschlag, nicht die freie Wahl: Wer von
      // Hand jemanden setzt, weiß, was er tut.
      final plan = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c'}),
        },
        overrides: {
          week.first: {'a'},
        },
        trips: const [],
        settings: settings,
        seats: const {'a': 2, 'b': 5},
      );

      expect(plan.first.driverId, 'a');
      expect(plan.first.isOverridden, isTrue);
    });
  });

  group('celebratedDrivers', () {
    /// Plan-Tag mit genau einem Auto, das alle Verfügbaren außer dem Fahrer
    /// mitnimmt — die Kurzform für die meisten Fälle.
    PlannedDay day(
      DateTime date,
      String? driver,
      List<String> available, {
      Set<String> oneWay = const {},
    }) => PlannedDay(
      date: date,
      availableIds: available,
      oneWayIds: oneWay,
      cars: [
        if (driver != null)
          PlannedCar(
            driverId: driver,
            fullIds: [
              for (final id in available)
                if (id != driver && !oneWay.contains(id)) id,
            ],
            oneWayIds: [
              for (final id in available)
                if (id != driver && oneWay.contains(id)) id,
            ],
          ),
      ],
    );

    // Vorgabe wie in AppSettings — die Tests unten pinnen zusätzlich,
    // dass der Faktor wirklich aus dem Parameter kommt.
    Set<String> celebrated(List<PlannedDay> plan, {double factor = 0.5}) =>
        celebratedDrivers(plan, oneWayFactor: factor);

    test('gefeiert wird der vollste einzelne Tag, nicht die Wochensumme', () {
      // a fährt zweimal mit je einem Mitfahrer (Summe 2), b einmal mit
      // dreien — b hat den vollsten Tag, die Summe zählt nicht.
      final plan = [
        day(week[0], 'a', ['a', 'b']),
        day(week[1], 'a', ['a', 'c']),
        day(week[2], 'b', ['b', 'a', 'c', 'd']),
      ];
      expect(celebrated(plan), {'b'});
    });

    test('der Fahrer zählt sich nicht selbst', () {
      final plan = [
        day(week[0], 'a', ['a']),
      ];
      expect(
        celebrated(plan),
        isEmpty,
        reason: 'Allein zu fahren ist kein Mitnehmen.',
      );
    });

    test('bei Gleichstand werden alle gefeiert', () {
      // Entschieden 2026-07-22: mehrere volle Autos, mehrere Konfettis.
      final plan = [
        day(week[0], 'a', ['a', 'b']),
        day(week[1], 'b', ['b', 'a']),
      ];
      expect(celebrated(plan), {'a', 'b'});
    });

    test('derselbe Fahrer zweimal am Maximum bleibt ein Eintrag', () {
      final plan = [
        day(week[0], 'a', ['a', 'b']),
        day(week[1], 'a', ['a', 'c']),
      ];
      expect(celebrated(plan), {'a'});
    });

    test('ohne Fahrer gibt es nichts zu feiern', () {
      final plan = [
        day(week[0], null, ['a', 'b']),
      ];
      expect(celebrated(plan), isEmpty);
    });

    test('eine 1-way-Mitfahrt zählt halb — wie in den Punkten (#59)', () {
      // a nimmt drei 1-way mit (3 × 0,5 = 1,5), d einen ganzen (1,0):
      // a gewinnt. Zwei ganze (2,0) schlagen wiederum die drei halben.
      final oneWayDay = day(
        week[0],
        'a',
        ['a', 'b', 'c', 'f'],
        oneWay: {'b', 'c', 'f'},
      );
      expect(
        celebrated([
          oneWayDay,
          day(week[1], 'd', ['d', 'e']),
        ]),
        {'a'},
      );
      expect(
        celebrated([
          oneWayDay,
          day(week[1], 'd', ['d', 'e', 'g']),
        ]),
        {'d'},
        reason: 'Zwei ganze Mitfahrten (2,0) schlagen drei halbe (1,5).',
      );
    });

    test('der 1-way-Faktor kommt aus den Settings, nicht aus der Formel', () {
      // Zwei 1-way von a gegen eine volle Mitfahrt von d: Mit der Vorgabe
      // 0,5 steht es 1,0 zu 1,0 — Gleichstand. Ein anderer Faktor kippt
      // den Sieger in beide Richtungen; der Parameter wirkt also wirklich.
      final plan = [
        day(week[0], 'a', ['a', 'b', 'c'], oneWay: {'b', 'c'}),
        day(week[1], 'd', ['d', 'e']),
      ];
      expect(celebrated(plan), {'a', 'd'});
      expect(celebrated(plan, factor: 0.25), {'d'});
      expect(celebrated(plan, factor: 1.0), {'a'});
    });

    test('nur 1-way-Mitfahrten sind trotzdem ein Hajo wert', () {
      // Halbe Punkte sind mehr als null — der einzige Fahrer der Woche
      // mit einer 1-way-Mitfahrt bekommt das Konfetti.
      final plan = [
        day(week[0], 'a', ['a', 'b'], oneWay: {'b'}),
      ];
      expect(celebrated(plan), {'a'});
    });
  });

  // Issue #60: Vorschau, was die geplante Woche an Punkten und Fahrrate
  // ändern würde — Geplantes berührt die echten Punkte weiterhin nie.
  group('statsWithPlannedWeek', () {
    test('geplante Tage zählen wie Fahrten — inklusive 1-way', () {
      final days = [
        PlannedDay(
          date: week[0],
          availableIds: const ['a', 'b', 'c'],
          oneWayIds: const {'c'},
          cars: const [
            PlannedCar(driverId: 'a', fullIds: ['b'], oneWayIds: ['c']),
          ],
        ),
      ];
      final stats = statsWithPlannedWeek(days, const [], settings);

      expect(stats['a']!.points, 1.5); // 1 voll + 0,5 × 1-way mitgenommen
      expect(stats['b']!.points, -1);
      expect(stats['c']!.points, -0.5);
      expect(stats['a']!.driveShare, 1);
    });

    test('bestätigte Tage werden nicht doppelt gezählt', () {
      final confirmedTrip = Trip(
        id: 'echt',
        date: week[0],
        participations: const {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        },
      );
      final days = [
        PlannedDay(
          date: week[0],
          availableIds: const ['a', 'b'],
          confirmed: true,
          cars: const [
            PlannedCar(driverId: 'a', fullIds: ['b'], tripId: 'echt'),
          ],
        ),
      ];
      final stats = statsWithPlannedWeek(days, [confirmedTrip], settings);

      expect(
        stats['a']!.driven,
        1,
        reason: 'Der Tag steckt schon in den echten Fahrten.',
      );
      expect(stats['a']!.points, 1);
    });

    test('ein geplanter Solo-Tag fällt über die Solo-Regel heraus', () {
      final days = [
        PlannedDay(
          date: week[0],
          availableIds: const ['a'],
          cars: const [PlannedCar(driverId: 'a')],
        ),
      ];
      expect(
        statsWithPlannedWeek(days, const [], settings),
        isEmpty,
        reason: 'Issue #61 gilt auch für die Vorschau.',
      );
    });

    test('Tage ohne Fahrer ändern nichts', () {
      final days = [
        PlannedDay(date: week[0], availableIds: const ['a', 'b']),
      ];
      expect(statsWithPlannedWeek(days, const [], settings), isEmpty);
    });
  });

  group('Fahrraten-Trim (suggestPlanDriver in planWeek)', () {
    Trip trip(
      int day, {
      required String driver,
      List<String> passengers = const [],
    }) => Trip(
      id: 't$day',
      // Februar — vor der Planwoche (2. März), also reine Historie.
      date: DateTime(2026, 2, day),
      participations: {
        driver: ParticipationStatus.driver,
        for (final p in passengers) p: ParticipationStatus.passenger,
      },
    );

    // Historie mit Punktgleichstand (a und b je +2), aber verschiedener
    // Fahrrate: a fuhr 1 von 2 Anwesenheiten (0,5), b 3 von 4 (0,75).
    // Wichtig: a ist zuletzt gefahren — der alte Tie-Break („am längsten
    // nicht gefahren") nähme also b. Wählt der Planer trotzdem a für den
    // kleinen Tag, war es beweisbar der Trim.
    List<Trip> history() => [
      trip(1, driver: 'b', passengers: ['c']),
      trip(2, driver: 'b', passengers: ['d']),
      trip(3, driver: 'b', passengers: ['a']),
      trip(4, driver: 'a', passengers: ['b', 'c', 'd']),
    ];

    test('bei Punktgleichstand: Wenigfahrer auf den kleinen Tag, '
        'Vielfahrer auf den vollen', () {
      // Mittwoch ist klein (2 Leute), Donnerstag voll (4, davon fahren nur
      // a und b in Frage — c und d sind 1-way). Der Trim gibt a (Rate 0,5)
      // den kleinen Tag; am vollen Tag ist b dann laut Punkten dran.
      final plan = planWeek(
        dates: [week[2], week[3]],
        availability: {
          week[2]: ride({'a', 'b'}),
          week[3]: ride({'a', 'b'}, oneWay: {'c', 'd'}),
        },
        overrides: const {},
        trips: history(),
        settings: settings,
      );

      expect(plan[0].suggestedDriverId, 'a', reason: 'kleiner Tag → a');
      expect(plan[1].suggestedDriverId, 'b', reason: 'voller Tag → b');
    });

    test('mehr als 6 Punkte Abstand überstimmt der Trim nie', () {
      // a liegt uneinholbar vorn (+9), b weit hinten (−3): zwölf Punkte
      // Abstand bei maximaler Raten-Spreizung (a fuhr immer, b nie). Die
      // Trim-Autorität endet bei kRateBalance · 1 · 1 = 6 Punkten — egal
      // wie groß der Tag ist, es fährt der Punktärmere. Wer den Deckel
      // weiter anhebt, sieht diesen Test kippen.
      final trips = [
        trip(1, driver: 'a', passengers: ['b', 'c', 'd']),
        trip(2, driver: 'a', passengers: ['b', 'c', 'd']),
        trip(3, driver: 'a', passengers: ['b', 'c', 'd']),
      ];
      final plan = planWeek(
        dates: [week[2], week[3]],
        availability: {
          week[2]: ride({'a', 'b'}),
          week[3]: ride({'a', 'b'}, oneWay: {'c', 'd'}),
        },
        overrides: const {},
        trips: trips,
        settings: settings,
      );

      expect(plan[0].suggestedDriverId, 'b');
      // Auch nach dem simulierten Mittwoch trennen a und b noch zehn
      // Punkte — der volle Tag geht wieder an b, der Deckel (6) reicht
      // nicht heran.
      expect(plan[1].suggestedDriverId, 'b');
    });

    test('bis 6 Punkte Abstand darf der Trim den vollen Tag umverteilen', () {
      // Der Unterschied zwischen Deckel 2 (bis v0.30.x) und Deckel 6
      // (Zielflotten-Entscheidung 2026-07-24): a führt mit 4 Punkten
      // Abstand (+2 vs. −2) bei maximaler Raten-Spreizung (a fuhr 2 von
      // 2, b 0 von 2). Am vollen Montag gilt
      //   wirksam(a) = 2 − 6 · (1,0 − 0,5) · 1 = −1
      //   wirksam(b) = −2 − 6 · (0,0 − 0,5) · 1 = +1
      // — der Vielfahrer nimmt den vollen Tag, denn seine Rate steigt
      // dort pro gewonnenem Punkt kaum. Mit Deckel 2 (Brücke max. 2 < 4
      // Punkte Abstand) führe hier noch b.
      final trips = [
        trip(1, driver: 'a', passengers: ['b']),
        trip(2, driver: 'a', passengers: ['b']),
      ];
      final plan = planWeek(
        dates: [week[0], week[1]],
        availability: {
          week[0]: ride({'a', 'b'}, oneWay: {'c', 'd'}),
          week[1]: ride({'a', 'b'}),
        },
        overrides: const {},
        trips: trips,
        settings: settings,
      );

      expect(
        plan[0].suggestedDriverId,
        'a',
        reason: 'Voller Tag: 6 · Δ-Rate 1,0 überbrückt die 4 Punkte.',
      );
      expect(
        plan[1].suggestedDriverId,
        'b',
        reason: 'Kleiner Tag danach: der Wenigfahrer ist ohnehin dran.',
      );
    });

    test('gleich große Tage lassen alles beim Alten', () {
      // dayFactor ist überall 0 — der Trim hebt sich auf, es gilt die
      // reine Punktereihenfolge samt bisherigem Tie-Break: b ist am
      // längsten nicht gefahren und kommt zuerst, danach a.
      final plan = planWeek(
        dates: [week[2], week[3]],
        availability: {
          week[2]: ride({'a', 'b'}),
          week[3]: ride({'a', 'b'}),
        },
        overrides: const {},
        trips: history(),
        settings: settings,
      );

      expect(plan[0].suggestedDriverId, 'b');
      expect(plan[1].suggestedDriverId, 'a');
    });
  });

  // Issue #62: Reicht kein einzelnes Auto, teilt der Planer den Tag auf so
  // wenige Autos wie möglich. Die Punkte bestimmen weiter, WER fährt.
  group('Mehrere Autos (Issue #62)', () {
    PlannedDay planDay({
      required Map<String, PlanRide> rides,
      Map<String, int> seats = const {},
      Set<String> override = const {},
      List<Trip> trips = const [],
    }) => planWeek(
      dates: [week.first],
      availability: {week.first: rides},
      overrides: override.isEmpty ? const {} : {week.first: override},
      trips: trips,
      settings: settings,
      seats: seats,
    ).first;

    test('ein Auto genügt, solange eines reicht', () {
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd', 'e'}),
        seats: const {'a': 5, 'b': 4, 'c': 4, 'd': 4, 'e': 4},
      );

      expect(day.cars, hasLength(1));
      expect(day.driverId, 'a');
    });

    test('ein großes Auto schlägt zwei kleine — auch gegen die Fairness', () {
      // g steht in der Fairness-Reihenfolge ganz hinten, hat aber als
      // Einziger Platz für alle sieben: Es bleibt bei einem Auto.
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd', 'e', 'f', 'g'}),
        seats: const {'a': 4, 'b': 4, 'c': 4, 'd': 4, 'e': 4, 'f': 4, 'g': 7},
      );

      expect(
        day.driverIds,
        ['g'],
        reason: 'Weniger Autos schlagen die Fairness-Reihenfolge (Regel 1+2).',
      );
    });

    test('reicht kein einzelnes Auto, fahren so wenige wie möglich', () {
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd', 'e', 'f'}),
        seats: const {'a': 4, 'b': 4, 'c': 4, 'd': 4, 'e': 4, 'f': 4},
      );

      expect(day.driverIds, hasLength(2), reason: '2 × 4 Plätze ≥ 6 Leute');
      expect(day.driverIds, ['a', 'b']);
    });

    test('unter ausreichenden Kombinationen entscheiden die Punkte', () {
      // a und b haben +2, c und d −2 — jede Zweier-Kombination hätte genug
      // Plätze, also fahren die Punktärmsten.
      final history = [
        Trip(
          id: 't1',
          date: DateTime(2026, 2, 1),
          participations: const {
            'a': ParticipationStatus.driver,
            'c': ParticipationStatus.passenger,
            'd': ParticipationStatus.passenger,
          },
        ),
        Trip(
          id: 't2',
          date: DateTime(2026, 2, 2),
          participations: const {
            'b': ParticipationStatus.driver,
            'c': ParticipationStatus.passenger,
            'd': ParticipationStatus.passenger,
          },
        ),
      ];
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd', 'e', 'f'}),
        seats: const {'a': 4, 'b': 4, 'c': 4, 'd': 4, 'e': 4, 'f': 4},
        trips: history,
      );

      expect(day.driverIds, ['c', 'd']);
    });

    test('wer den Tag nicht mehr abdecken kann, wird übersprungen', () {
      // a wäre laut Fairness zuerst dran, aber mit as Zweisitzer kommen
      // selbst zwei Autos nicht auf acht Plätze — b und c müssen fahren.
      final day = planDay(
        rides: ride({'a', 'b', 'c'}, oneWay: {'d', 'e', 'f', 'g', 'h'}),
        seats: const {'a': 2, 'b': 4, 'c': 4},
      );

      expect(day.driverIds, ['b', 'c']);
    });

    test('die Mitfahrer verteilen sich ausgeglichen und deterministisch', () {
      // Vier Mitfahrer auf zwei Vierersitzer: abwechselnd ins Auto mit den
      // meisten freien Plätzen, Gleichstand geht ans erste. 1-way belegt
      // dabei einen Sitz wie jeder andere.
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}, oneWay: {'e', 'f'}),
        seats: const {'a': 4, 'b': 4, 'c': 4, 'd': 4},
      );

      expect(day.driverIds, ['a', 'b']);
      expect(day.cars[0].fullIds, ['c']);
      expect(day.cars[0].oneWayIds, ['e']);
      expect(day.cars[1].fullIds, ['d']);
      expect(day.cars[1].oneWayIds, ['f']);
    });

    test('die Simulation bucht je Auto eine Pseudo-Fahrt', () {
      final plan = planWeek(
        dates: [week[0], week[1]],
        availability: {
          week[0]: ride({'a', 'b', 'c', 'd', 'e', 'f'}),
          week[1]: ride({'a', 'b'}),
        },
        overrides: const {},
        trips: const [],
        settings: settings,
        seats: const {'a': 4, 'b': 4, 'c': 4, 'd': 4, 'e': 4, 'f': 4},
      );

      expect(plan.first.driverIds, ['a', 'b']);
      final preview = statsWithPlannedWeek([plan.first], const [], settings);
      expect(preview['a']!.points, 2);
      expect(
        preview['b']!.points,
        2,
        reason: 'Das „Mitgenommen" des Tages teilt sich auf beide Fahrer.',
      );
      expect(
        plan[1].driverId,
        'a',
        reason:
            'Hätte nur einer die vier Montags-Punkte bekommen, wäre am '
            'Dienstag zwingend der andere dran.',
      );
    });

    test('ein Auto ohne Mitfahrer zählt als Solo-Fahrt nicht', () {
      // Drei Leute auf zwei Zweisitzer: Das zweite Auto fährt leer hinterher
      // und bringt seinem Fahrer nichts — genau wie der echte Eintrag später
      // auch (Issue #61). Wer das „repariert", zählt Solo-Fahrten doppelt.
      final day = planDay(
        rides: ride({'a', 'b', 'c'}),
        seats: const {'a': 2, 'b': 2, 'c': 2},
      );

      expect(day.driverIds, ['a', 'b']);
      final preview = statsWithPlannedWeek([day], const [], settings);
      expect(preview['a']!.points, 1);
      expect(preview['b'], isNull, reason: 'Solo-Auto ist unsichtbar (#61).');
    });

    test('reichen selbst alle Autos nicht, fahren alle Kandidaten', () {
      // Zwei Zweisitzer für fünf Leute: Die Sitzprüfung fällt weg — lieber
      // zu wenige Plätze als ein Tag ohne Fahrer (die alte Rückfalllinie,
      // verallgemeinert).
      final day = planDay(
        rides: ride({'a', 'b'}, oneWay: {'c', 'd', 'e'}),
        seats: const {'a': 2, 'b': 2},
      );

      expect(day.driverIds, ['a', 'b']);
    });

    test('ein Mehrfach-Übersteuern ersetzt den ganzen Vorschlag', () {
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        override: {'c', 'd'},
      );

      expect(day.suggestedDriverIds, ['a']);
      expect(day.driverIds, ['c', 'd']);
      expect(day.isOverridden, isTrue);
    });

    test('ein Übersteuern verfällt je Person, nicht als Ganzes', () {
      // z hat keine Verfügbarkeit — nur dieser Teil des Übersteuerns
      // verfällt, der Rest bleibt.
      final partial = planDay(rides: ride({'a', 'b'}), override: {'b', 'z'});
      expect(partial.driverIds, ['b']);
      expect(partial.isOverridden, isTrue);

      // Verfallen alle, gilt wieder der Vorschlag.
      final lapsed = planDay(rides: ride({'a', 'b'}), override: {'z'});
      expect(lapsed.driverIds, ['a']);
      expect(lapsed.isOverridden, isFalse);

      // Und wer von Hand genau den Vorschlag wählt, hat nichts übersteuert.
      final same = planDay(rides: ride({'a', 'b'}), override: {'a'});
      expect(same.isOverridden, isFalse);
    });
  });

  // #189, Stufe B2: Das Einverständnis eines Mitfahrers mit einer Abfahrt.
  // Kein freies Auto-Wählen — ein Pin ist ein Ja zu den Bedingungen eines
  // Autos, ein Ausschluss ein Nein. Entschieden am 07.08.
  group('Sitz-Entscheidungen (#189)', () {
    SeatChoice choice(
      String personId,
      String driverId, {
      bool accepted = true,
      String terms = '',
      DateTime? decidedAt,
    }) => SeatChoice(
      date: week.first,
      personId: personId,
      driverId: driverId,
      accepted: accepted,
      terms: terms,
      decidedAt: decidedAt ?? DateTime(2026, 3, 1, 12),
    );

    PlannedDay planDay({
      required Map<String, PlanRide> rides,
      Map<String, int> seats = const {},
      Set<String> override = const {},
      List<SeatChoice> choices = const [],
      Map<String, GroupDefaults> carDefaults = const {},
    }) => planWeek(
      dates: [week.first],
      availability: {week.first: rides},
      overrides: override.isEmpty ? const {} : {week.first: override},
      trips: const [],
      settings: settings,
      seats: seats,
      seatChoices: {week.first: choices},
      carDefaults: {week.first: carDefaults},
    ).first;

    test('ein Pin setzt die Person in genau dieses Auto', () {
      // Automatisch säße c bei b — dessen Auto hat mehr freie Plätze. Der
      // Pin muss also wirklich etwas umbiegen; ein Pin auf das Auto, in dem
      // man ohnehin landete, bewiese nichts.
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 2, 'b': 3, 'c': 2, 'd': 2},
        choices: [choice('c', 'a')],
      );

      expect(day.driverIds, ['a', 'b']);
      expect(day.cars[0].fullIds, ['c']);
      expect(day.cars[1].fullIds, ['d']);
    });

    test('wer zuerst gepinnt hat, bleibt — der Nachrang wird verteilt', () {
      // Auto a hat EINEN Mitfahrerplatz; c und d pinnen beide dorthin.
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 2, 'b': 3, 'c': 2, 'd': 2},
        choices: [
          choice('d', 'a', decidedAt: DateTime(2026, 3, 1, 8)),
          choice('c', 'a', decidedAt: DateTime(2026, 3, 1, 9)),
        ],
      );

      expect(day.cars[0].fullIds, ['d'], reason: 'd hat zuerst gepinnt.');
      expect(
        day.cars[1].fullIds,
        ['c'],
        reason:
            'c fällt in die automatische Verteilung — nicht aus dem Tag, '
            'und nicht dauerhaft aus dem Wunsch-Auto.',
      );
    });

    test('eine Zusage gilt nur zu ihren Bedingungen', () {
      // c hat zu 06:45 ja gesagt; das Auto steht inzwischen auf 05:30. Die
      // Zusage ist veraltet und wirkt nicht — sonst wäre sie ein
      // Blankoscheck für jede spätere Zeit. Derselbe Aufbau wie beim
      // Pin-Test: Gültig zöge der Pin c zu a, veraltet läuft c automatisch
      // zu b.
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 2, 'b': 3, 'c': 2, 'd': 2},
        choices: [choice('c', 'a', terms: '06:45||')],
        carDefaults: const {'a': GroupDefaults(outboundTime: DayTime(5, 30))},
      );

      expect(day.cars[1].fullIds, contains('c'));
      expect(day.cars[0].fullIds, isNot(contains('c')));
    });

    test('ein Ausschluss hält die Person aus dem Auto heraus', () {
      final day = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 3, 'b': 3, 'c': 2, 'd': 2},
        choices: [choice('d', 'a', accepted: false)],
      );

      expect(day.cars[0].fullIds, isNot(contains('d')));
      expect(day.cars[1].fullIds, contains('d'));
    });

    test('ein Nein verfällt, wenn die Abweichung zurückgenommen wurde', () {
      // d hat zu 05:30 nein gesagt; die Abweichung ist weg. Bliebe das Nein
      // bestehen, gäbe es dauerhaft zwei Autos wegen einer Zeit, die es
      // nicht mehr gibt.
      final day = planDay(
        rides: ride({'a', 'b'}, oneWay: const {}),
        seats: const {'a': 5, 'b': 5},
        choices: [choice('b', 'a', accepted: false, terms: '05:30||')],
      );

      expect(day.cars, hasLength(1));
      expect(day.cars[0].fullIds, ['b']);
    });

    test('schließt jemand das einzige Auto aus, entsteht ein zweites', () {
      // Der Kern der Entscheidung vom 07.08.: „Zu diesen Bedingungen fahre
      // ich dort nicht mit" heißt, jemand anderes muss fahren. Wer, sagen
      // die Punkte.
      final day = planDay(
        rides: ride({'a', 'b', 'c'}),
        seats: const {'a': 5, 'b': 5, 'c': 5},
        choices: [choice('c', 'a', accepted: false)],
      );

      expect(day.driverIds, hasLength(2));
      expect(day.driverIds.first, 'a');
      expect(
        day.cars.last.carries('c'),
        isTrue,
        reason: 'Das zweite Auto existiert, damit c mitkommt.',
      );
      expect(
        day.isOverridden,
        isFalse,
        reason:
            'Das Zusatzauto ist Teil des VORSCHLAGS — kein Mensch hat die '
            'Fahrer-Menge gesetzt.',
      );
    });

    test('das Zusatzauto entsteht auch an einem übersteuerten Tag', () {
      // Genau dort entsteht der Fall: Die Zeit zu setzen schreibt die
      // Fahrer fest (#183), der Tag ist also übersteuert, wenn die
      // Rückfrage kommt.
      final day = planDay(
        rides: ride({'a', 'b', 'c'}),
        seats: const {'a': 5, 'b': 5, 'c': 5},
        override: {'a'},
        carDefaults: const {'a': GroupDefaults(outboundTime: DayTime(5, 30))},
        choices: [
          choice('b', 'a', accepted: false, terms: '05:30||'),
          choice('c', 'a', accepted: false, terms: '05:30||'),
        ],
      );

      expect(day.driverIds, hasLength(2));
      expect(
        day.cars[0].headcount,
        1,
        reason:
            'Beim Spezialfahrer fährt niemand mit — beide haben nein '
            'gesagt.',
      );
    });

    test('das Zusatzauto ist als erzwungen markiert — Platznot nicht', () {
      // Der Umschalter „Wer fährt?" muss beides unterscheiden können (#203):
      // Ein Fahrer, den eine Absage erzwingt, ist nicht abwählbar (die
      // Rechnung setzte ihn sofort zurück); ein Fahrer, der nur wegen der
      // Sitzplätze dazukam, sehr wohl.
      final forced = planDay(
        rides: ride({'a', 'b', 'c'}),
        seats: const {'a': 5, 'b': 5, 'c': 5},
        choices: [choice('c', 'a', accepted: false)],
      );
      expect(forced.driverIds, hasLength(2));
      expect(
        forced.forcedFor.keys,
        [forced.driverIds.last],
        reason: 'Nur der Zusatzfahrer steht drin, nicht der erste.',
      );
      expect(
        forced.forcedFor[forced.driverIds.last],
        ['c'],
        reason: 'Und wer ihn braucht — das ist der Text am Eintrag.',
      );

      // Zwei Autos aus reiner Kapazität: nichts erzwungen, alles abwählbar.
      final tight = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 2, 'b': 2, 'c': 2, 'd': 2},
      );
      expect(tight.driverIds, hasLength(2));
      expect(
        tight.forcedFor,
        isEmpty,
        reason:
            'Platznot ist eine Kapazitätsfrage, keine Absage — hier darf '
            'der Umschalter alles.',
      );
    });

    test('ohne möglichen Zusatzfahrer bleibt die Person sichtbar draußen', () {
      // b (1-way, kann nicht fahren) lehnt das einzige Auto ab, und außer a
      // kann niemand fahren: Es gibt kein Auto für b. Sichtbar draußen ist
      // ehrlich — still hineingesetzt wäre das Nein wertlos.
      final day = planDay(
        rides: ride({'a'}, oneWay: {'b'}),
        seats: const {'a': 5},
        choices: [choice('b', 'a', accepted: false)],
      );

      expect(day.cars, hasLength(1));
      expect(day.cars[0].carries('b'), isFalse);
    });

    test('ein Pin auf einen Fahrer, der nicht fährt, ist verwaist', () {
      // Dieselbe Regel wie bei den Auto-Zeiten: Die Zeile wirkt nicht,
      // solange ihr Fahrer nicht fährt — und niemand räumt sie auf.
      final day = planDay(
        rides: ride({'a', 'b', 'c'}),
        seats: const {'a': 5, 'b': 5, 'c': 5},
        choices: [choice('c', 'z')],
      );

      expect(day.cars, hasLength(1));
      expect(day.cars[0].fullIds, ['b', 'c']);
    });

    test('ohne Entscheidungen rechnet der Tag wie bisher', () {
      // Die Rückwärtskompatibilität in eine Zeile gefasst: leere Maps
      // ändern nichts. Daran hängt auch, dass der Soak-Report gültig
      // bleibt — er misst die automatische Verteilung.
      final without = planDay(
        rides: ride({'a', 'b', 'c', 'd'}),
        seats: const {'a': 2, 'b': 3, 'c': 2, 'd': 2},
      );
      final withEmpty = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c', 'd'}),
        },
        overrides: const {},
        trips: const [],
        settings: settings,
        seats: const {'a': 2, 'b': 3, 'c': 2, 'd': 2},
      ).first;

      expect(without.driverIds, withEmpty.driverIds);
      expect(
        [for (final car in without.cars) car.fullIds],
        [for (final car in withEmpty.cars) car.fullIds],
      );
    });

    // #199: Ein Mitfahrer sucht sich sein Auto aus. Die Ablage kann das
    // längst — was fehlte, war die Oberfläche. Diese Tests halten die zwei
    // Regeln fest, ohne die sie nicht tragen würde.
    group('das Auto wechseln (#199)', () {
      test('von zwei Zusagen gilt die zuletzt getroffene', () {
        // Der Kern: c hat gestern a zugesagt und wählt heute b. Ohne die
        // „je Person höchstens einer"-Regel gewänne die ÄLTERE Zeile —
        // Pins laufen in `decided_at`-Folge und überspringen, wer schon
        // sitzt. Der Tipp täte dann sichtbar nichts, dieselbe Klasse wie
        // der tote „Ich möchte fahren"-Pin aus v0.66.1.
        final day = planDay(
          rides: ride({'a', 'b', 'c', 'd'}),
          seats: const {'a': 3, 'b': 3, 'c': 2, 'd': 2},
          choices: [
            choice('c', 'a', decidedAt: DateTime(2026, 3, 1, 8)),
            choice('c', 'b', decidedAt: DateTime(2026, 3, 1, 9)),
          ],
        );

        expect(day.driverIds, ['a', 'b']);
        expect(
          day.cars[1].fullIds,
          contains('c'),
          reason: 'Die neue Wahl gilt — c sitzt bei b.',
        );
        expect(day.cars[0].fullIds, isNot(contains('c')));
      });

      test('die überholte Zusage bleibt stehen und wirkt nicht', () {
        // Verwaisten-Regel wie bei `plan_car_defaults`: aufgeräumt wird
        // nichts. Fällt die neue Wahl weg (hier: veraltete Bedingungen),
        // greift die alte wieder.
        final day = planDay(
          rides: ride({'a', 'b', 'c', 'd'}),
          seats: const {'a': 3, 'b': 3, 'c': 2, 'd': 2},
          carDefaults: const {'b': GroupDefaults(outboundTime: DayTime(5, 30))},
          choices: [
            choice('c', 'a', decidedAt: DateTime(2026, 3, 1, 8)),
            // Zu leeren Bedingungen zugesagt, das Auto weicht inzwischen ab.
            choice('c', 'b', decidedAt: DateTime(2026, 3, 1, 9)),
          ],
        );

        expect(day.cars[0].fullIds, contains('c'));
      });

      test('freeSeatsForPin zählt nur die festen Zusagen, nicht die '
          'automatisch Verteilten', () {
        // Was der Auswahl-Dialog fragt: „Passt da noch jemand rein?" Ein Pin
        // greift VOR der automatischen Verteilung — wer nur automatisch
        // drinsitzt, wird hinterher neu verteilt und blockiert deshalb
        // nicht. Sonst sperrte der Schirm Autos, in die man gekonnt hätte.
        final persons = {
          for (final id in ['a', 'b', 'c', 'd', 'e'])
            id: Person(id: id, name: id, active: true, seats: 3),
        };
        final day = planDay(
          rides: ride({'a', 'b', 'c', 'd', 'e'}),
          seats: const {'a': 3, 'b': 3, 'c': 3, 'd': 3, 'e': 3},
        );
        expect(day.driverIds, hasLength(2), reason: 'Aufbau: zwei Autos.');
        final other = day.driverIds.first;

        expect(
          freeSeatsForPin(
            day,
            driverId: other,
            personId: 'e',
            persons: persons,
            choices: const [],
            carDefaults: const {},
          ),
          2,
          reason: 'Drei Sitze minus Fahrer, ohne jede Zusage.',
        );

        // Zwei fremde Zusagen auf dasselbe Auto machen es voll — und genau
        // dann sperrt der Dialog den Eintrag, statt einen Tipp anzunehmen,
        // der in `planWeek` still verfiele.
        final full = freeSeatsForPin(
          day,
          driverId: other,
          personId: 'e',
          persons: persons,
          choices: [
            for (final id in day.availableIds)
              if (id != other && id != 'e') choice(id, other),
          ],
          carDefaults: const {},
        );
        expect(full, lessThanOrEqualTo(0));
      });

      test('die eigene Zusage belegt keinen Platz gegen sich selbst', () {
        // Sonst wäre das Auto, in dem man schon fest sitzt, als „voll"
        // gesperrt — und das Häkchen stünde an einem toten Eintrag.
        final persons = {
          for (final id in ['a', 'b'])
            id: Person(id: id, name: id, active: true, seats: 2),
        };
        final day = planDay(
          rides: ride({'a', 'b'}),
          seats: const {'a': 2, 'b': 2},
        );

        expect(
          freeSeatsForPin(
            day,
            driverId: 'a',
            personId: 'b',
            persons: persons,
            choices: [choice('b', 'a')],
            carDefaults: const {},
          ),
          1,
        );
      });
    });
  });

  group('Bestätigte Tage mit mehreren Fahrten', () {
    final twoCars = [
      Trip(
        id: 't1',
        date: week.first,
        participations: const {
          'a': ParticipationStatus.driver,
          'b': ParticipationStatus.passenger,
        },
      ),
      Trip(
        id: 't2',
        date: week.first,
        participations: const {
          'c': ParticipationStatus.driver,
          'd': ParticipationStatus.oneWay,
        },
      ),
    ];

    test('zwei echte Fahrten am selben Tag erscheinen als zwei Autos', () {
      // Bis Issue #62 kollabierte der Tag auf die zuletzt geladene Fahrt.
      final day = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c', 'd'}),
        },
        overrides: const {},
        trips: twoCars,
        settings: settings,
      ).first;

      expect(day.confirmed, isTrue);
      expect(day.driverIds, ['a', 'c']);
      expect(day.cars[0].tripId, 't1');
      expect(day.cars[0].fullIds, ['b']);
      expect(day.cars[1].tripId, 't2');
      expect(day.cars[1].oneWayIds, ['d']);
    });

    test('das Hajo zählt je Auto und die echten Insassen', () {
      // x steht zwar im Raster, saß aber in keinem Auto — zählte die
      // Verfügbarkeit statt der Fahrt, bekäme der falsche Fahrer Konfetti.
      final day = planWeek(
        dates: [week.first],
        availability: {
          week.first: ride({'a', 'b', 'c', 'd', 'x'}),
        },
        overrides: const {},
        trips: twoCars,
        settings: settings,
      ).first;

      expect(
        celebratedDrivers([day], oneWayFactor: 0.5),
        {'a'},
        reason: 'a nimmt 1,0 mit (b voll), c nur 0,5 (d 1-way).',
      );
    });
  });
}

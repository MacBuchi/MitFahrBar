/// push_digest_test.dart – Die Versandregeln der Benachrichtigungen (#101).
///
/// Hier hängt das Verhalten dran, das man auf dem Gerät nur mit sehr viel
/// Geduld prüfen könnte: Fenster, Nachhol-Riegel, Mindestabstand und die
/// Frage, wann ein Tag als „geändert" gilt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/push_digest.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';

void main() {
  // 2026-07-27 ist ein Montag, 2026-07-28 ein Dienstag.
  final tuesday = DateTime(2026, 7, 28);
  final mondayEvening = DateTime(2026, 7, 27, 21, 30);

  const anna = 'a';
  const bernd = 'b';
  const clara = 'c';

  final persons = <String, Person>{
    anna: const Person(id: anna, name: 'Anna', active: true),
    bernd: const Person(id: bernd, name: 'Bernd', active: true),
    clara: const Person(id: clara, name: 'Clara', active: true),
  };

  /// Ein Tag mit Anna am Steuer und Bernd + Clara als Mitfahrern.
  PlannedDay dayWith({
    List<String> available = const [anna, bernd, clara],
    Set<String> oneWay = const {},
    List<PlannedCar> cars = const [
      PlannedCar(driverId: anna, fullIds: [bernd, clara]),
    ],
    bool confirmed = false,
  }) => PlannedDay(
    date: tuesday,
    availableIds: available,
    oneWayIds: oneWay,
    suggestedDriverIds: [for (final car in cars) car.driverId],
    cars: cars,
    confirmed: confirmed,
  );

  Map<String, NotificationPrefs> prefsFor(
    List<String> ids, {
    bool evening = true,
    bool changes = true,
  }) => {
    for (final id in ids)
      id: NotificationPrefs.initial(
        id,
      ).copyWith(eveningEnabled: evening, changesEnabled: changes),
  };

  SentPush sentEvening(String personId, String digest, DateTime at) => SentPush(
    personId: personId,
    planDate: tuesday,
    kind: PushKind.evening,
    digest: digest,
    sentAt: at,
  );

  group('Digest', () {
    test('dieselbe Lage ergibt denselben Wert', () {
      expect(dayDigestFor(dayWith(), bernd), dayDigestFor(dayWith(), bernd));
    });

    test('ein anderer Fahrer ändert ihn', () {
      final other = dayWith(
        cars: const [
          PlannedCar(driverId: bernd, fullIds: [anna, clara]),
        ],
      );
      expect(
        dayDigestFor(other, clara),
        isNot(dayDigestFor(dayWith(), clara)),
        reason: 'Wer morgen fährt, ist die Kerninformation der Nachricht.',
      );
    });

    test('eine geänderte Verfügbarkeit ändert ihn', () {
      final without = dayWith(
        available: const [anna, bernd],
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd]),
        ],
      );
      expect(
        dayDigestFor(without, bernd),
        isNot(dayDigestFor(dayWith(), bernd)),
      );
    });

    test('1-way statt ganz ändert ihn', () {
      final oneWay = dayWith(
        oneWay: const {clara},
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd], oneWayIds: [clara]),
        ],
      );
      expect(
        dayDigestFor(oneWay, bernd),
        isNot(dayDigestFor(dayWith(), bernd)),
      );
    });

    test('wer nicht dabei ist, hat einen festen Wert', () {
      expect(dayDigestFor(dayWith(), 'unbekannt'), removedDigest);
    });

    test('er hängt NICHT an den Punkten', () {
      // Punkte stecken nirgends in PlannedDay — der Test hält fest, dass das
      // so bleibt: Sonst löste jede eingetragene Fahrt eines Vortages eine
      // Änderungs-Nachricht aus, die niemanden interessiert.
      final same = PlannedDay(
        date: tuesday,
        availableIds: const [anna, bernd, clara],
        suggestedDriverIds: const [anna],
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd, clara]),
        ],
      );
      expect(dayDigestFor(same, bernd), dayDigestFor(dayWith(), bernd));
    });
  });

  group('Abend-Push', () {
    test('geht im Fenster an alle Anwesenden mit Einstellung', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna, bernd, clara]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
      );
      expect(due.map((d) => d.personId).toSet(), {anna, bernd, clara});
      expect(due.every((d) => d.kind == PushKind.evening), isTrue);
    });

    test('kommt vor der eingestellten Uhrzeit nicht', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: DateTime(2026, 7, 27, 20, 59),
      );
      expect(due, isEmpty);
    });

    test('wird nach der Abfahrt nicht nachgeholt', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: DateTime(2026, 7, 28, 7, 31),
      );
      expect(
        due,
        isEmpty,
        reason:
            'Nach der Abfahrt nützt die Nachricht nichts mehr — und ein '
            'nachgeholter Lauf nach einem Ausfall darf niemanden wecken.',
      );
    });

    test('holt einen verspäteten Lauf im Fenster nach', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 40),
      );
      expect(due, hasLength(1));
      expect(
        due.single.title,
        startsWith('Heute'),
        reason: 'Am Morgen des Tages ist es nicht mehr „morgen".',
      );
    });

    test('geht nicht an Personen ohne Einstellungs-Zeile', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
      );
      expect(due.map((d) => d.personId), [anna]);
    });

    test('kommt kein zweites Mal', () {
      final digest = dayDigestFor(dayWith(), anna);
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: [sentEvening(anna, digest, mondayEvening)],
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
      );
      expect(due, isEmpty);
    });

    test('bleibt aus, wenn die Person ihn abgeschaltet hat', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna], evening: false),
        sent: const [],
        persons: persons,
        now: mondayEvening,
      );
      expect(due, isEmpty);
    });
  });

  group('Änderungs-Push', () {
    final digestBefore = dayDigestFor(dayWith(), clara);
    final changed = dayWith(
      cars: const [
        PlannedCar(driverId: bernd, fullIds: [anna, clara]),
      ],
    );

    test('meldet den neuen Stand', () {
      final due = dueMessages(
        week: [changed],
        prefs: prefsFor([clara]),
        sent: [sentEvening(clara, digestBefore, mondayEvening)],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(due, hasLength(1));
      expect(due.single.kind, PushKind.change);
      expect(due.single.title, startsWith('Änderung'));
      expect(due.single.body, contains('Bernd fährt'));
    });

    test('bleibt aus, solange sich nichts geändert hat', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([clara]),
        sent: [sentEvening(clara, digestBefore, mondayEvening)],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(due, isEmpty);
    });

    test('kommt nie vor dem Abend-Push', () {
      final due = dueMessages(
        week: [changed],
        prefs: prefsFor([clara], evening: false),
        sent: const [],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(
        due,
        isEmpty,
        reason:
            'Ohne vorherige Ankündigung wäre eine Änderungs-Meldung für die '
            'Empfängerin die erste Nachricht des Tages — und ohne Bezug.',
      );
    });

    test('hält den Mindestabstand ein', () {
      final now = DateTime(2026, 7, 28, 6, 0);
      final sent = [
        sentEvening(clara, digestBefore, mondayEvening),
        SentPush(
          personId: clara,
          planDate: tuesday,
          kind: PushKind.change,
          digest: 'irgendwas-anderes',
          sentAt: now.subtract(const Duration(minutes: 10)),
        ),
      ];
      expect(
        dueMessages(
          week: [changed],
          prefs: prefsFor([clara]),
          sent: sent,
          persons: persons,
          now: now,
        ),
        isEmpty,
      );
      expect(
        dueMessages(
          week: [changed],
          prefs: prefsFor([clara]),
          sent: sent,
          persons: persons,
          now: now.add(const Duration(minutes: 25)),
        ),
        hasLength(1),
      );
    });

    test('bleibt aus, wenn die Person Änderungen abgeschaltet hat', () {
      final due = dueMessages(
        week: [changed],
        prefs: prefsFor([clara], changes: false),
        sent: [sentEvening(clara, digestBefore, mondayEvening)],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(due, isEmpty);
    });
  });

  group('Austrag', () {
    final digestBefore = dayDigestFor(dayWith(), clara);
    final without = dayWith(
      available: const [anna, bernd],
      cars: const [
        PlannedCar(driverId: anna, fullIds: [bernd]),
      ],
    );

    test('sagt genau einmal Bescheid', () {
      final now = DateTime(2026, 7, 28, 6, 0);
      final first = dueMessages(
        week: [without],
        prefs: prefsFor([clara]),
        sent: [sentEvening(clara, digestBefore, mondayEvening)],
        persons: persons,
        now: now,
      );
      expect(first, hasLength(1));
      expect(first.single.title, startsWith('Ausgetragen'));
      expect(first.single.body, contains('nicht mehr eingetragen'));
      expect(first.single.digest, removedDigest);

      // Danach räumen die anderen den Tag weiter um — Clara hört nichts mehr.
      final rebuilt = dayWith(
        available: const [anna, bernd],
        cars: const [
          PlannedCar(driverId: bernd, fullIds: [anna]),
        ],
      );
      final second = dueMessages(
        week: [rebuilt],
        prefs: prefsFor([clara]),
        sent: [
          sentEvening(clara, digestBefore, mondayEvening),
          SentPush(
            personId: clara,
            planDate: tuesday,
            kind: PushKind.change,
            digest: removedDigest,
            sentAt: now,
          ),
        ],
        persons: persons,
        now: now.add(const Duration(hours: 1)),
      );
      expect(
        second,
        isEmpty,
        reason:
            'Der feste Austrags-Digest ist genau dafür da: Wer raus ist, '
            'bekommt nicht bei jedem weiteren Umbau eine Nachricht.',
      );
    });

    test('meldet sich wieder, wenn jemand zurückgetragen wird', () {
      final now = DateTime(2026, 7, 28, 6, 0);
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([clara]),
        sent: [
          sentEvening(clara, digestBefore, mondayEvening),
          SentPush(
            personId: clara,
            planDate: tuesday,
            kind: PushKind.change,
            digest: removedDigest,
            sentAt: now.subtract(const Duration(hours: 1)),
          ),
        ],
        persons: persons,
        now: now,
      );
      expect(due, hasLength(1));
      expect(due.single.title, startsWith('Änderung'));
    });
  });

  test('ein eingetragener Tag löst gar nichts mehr aus', () {
    final due = dueMessages(
      week: [dayWith(confirmed: true)],
      prefs: prefsFor([anna, bernd, clara]),
      sent: const [],
      persons: persons,
      now: mondayEvening,
    );
    expect(
      due,
      isEmpty,
      reason:
          'Existiert die Fahrt, ist der Tag gelaufen — es gibt nichts '
          'mehr zu planen und nichts zu melden.',
    );
  });

  group('Text', () {
    test('sagt der Fahrerin, wen sie mitnimmt', () {
      expect(
        composeBody(dayWith(), anna, persons),
        'Du fährst · dabei: Bernd, Clara',
      );
    });

    test('nennt Mitfahrern die Fahrerin und die anderen', () {
      expect(
        composeBody(dayWith(), bernd, persons),
        'Anna fährt · dabei: Clara',
      );
    });

    test('erwähnt die eigene 1-way-Fahrt', () {
      final day = dayWith(
        oneWay: const {clara},
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd], oneWayIds: [clara]),
        ],
      );
      expect(composeBody(day, clara, persons), contains('nur eine Richtung'));
    });

    test('sagt es, wenn niemand fahren kann', () {
      final day = dayWith(available: const [anna, bernd], cars: const []);
      expect(composeBody(day, anna, persons), startsWith('Kein Fahrer'));
    });

    test('nennt die Zahl der Autos, wenn es mehr als eines ist', () {
      final day = dayWith(
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd]),
          PlannedCar(driverId: clara),
        ],
      );
      expect(composeBody(day, bernd, persons), endsWith('2 Autos'));
    });

    test('unterscheidet heute, morgen und später', () {
      expect(dayLabel(tuesday, mondayEvening), 'Morgen (Di, 28.07.)');
      expect(
        dayLabel(tuesday, DateTime(2026, 7, 28, 6, 0)),
        'Heute (Di, 28.07.)',
      );
      expect(dayLabel(tuesday, DateTime(2026, 7, 25)), 'Di, 28.07.');
    });
  });

  test('die Vorbelegung deckt sich mit den Defaults der Migration', () {
    final migration = File(
      'supabase/migrations/20260726100000_push_notifications.sql',
    ).readAsStringSync();
    final initial = NotificationPrefs.initial('x');

    expect(
      migration,
      contains("evening_time time not null default '${initial.eveningTime}'"),
    );
    expect(
      migration,
      contains(
        "departure_time time not null default '${initial.departureTime}'",
      ),
      reason:
          'Formular-Vorbelegung und DB-Default müssen dasselbe sagen — sonst '
          'bekommt eine von Hand angelegte Zeile andere Zeiten als eine über '
          'den Screen angelegte, und niemand findet den Unterschied.',
    );
  });
}

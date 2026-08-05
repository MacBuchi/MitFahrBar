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
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_note.dart';

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

  // Das Banner auf der Übersicht (#122) spricht dieselbe Sprache wie die
  // Benachrichtigung, kennt aber kein „du": Im Browser und auf nicht
  // zugeordneten Geräten gibt es keine Person, auf die man den Text beziehen
  // könnte.
  group('Text für die ganze Gruppe', () {
    test('nennt Fahrerin und Mitfahrer beim Namen', () {
      expect(
        composeGroupBody(dayWith(), persons),
        'Anna fährt · dabei: Bernd, Clara',
      );
    });

    test('kommt ohne „du" aus', () {
      expect(composeGroupBody(dayWith(), persons), isNot(contains('u fährst')));
    });

    test('zählt über alle Autos zusammen, nicht je Auto', () {
      final day = dayWith(
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd]),
          PlannedCar(driverId: clara),
        ],
      );
      expect(
        composeGroupBody(day, persons),
        'Anna und Clara fahren · dabei: Bernd · 2 Autos',
      );
    });

    test('sagt es, wenn niemand fahren kann', () {
      final day = dayWith(available: const [anna, bernd], cars: const []);
      expect(composeGroupBody(day, persons), 'Kein Fahrer · 2 dabei');
    });

    test('unterscheidet „kein Fahrer" von „alle nur eine Richtung"', () {
      final day = dayWith(
        available: const [anna, bernd],
        oneWay: const {anna, bernd},
        cars: const [],
      );
      expect(
        composeGroupBody(day, persons),
        'Kein Fahrer möglich — alle nur eine Richtung · 2 dabei',
      );
    });

    test('sagt es, wenn die Fahrerin allein fährt', () {
      final day = dayWith(
        available: const [anna],
        cars: const [PlannedCar(driverId: anna)],
      );
      expect(
        composeGroupBody(day, persons),
        'Anna fährt · niemand mitzunehmen',
      );
    });
  });

  group('Anmerkungen (#127)', () {
    PlanNote note(String id, {DateTime? on, String body = 'Komme erst um 9'}) =>
        PlanNote(
          id: id,
          date: on ?? tuesday,
          personId: bernd,
          body: body,
          createdAt: mondayEvening,
        );

    test('eine neue Anmerkung ändert den Digest', () {
      expect(
        dayDigestFor(dayWith(), anna, notes: [note('n1')]),
        isNot(dayDigestFor(dayWith(), anna)),
        reason:
            'Ohne das bliebe der Tag für den Versand-Job unverändert und die '
            'Anmerkung erreichte niemanden.',
      );
    });

    test('eine andere Reihenfolge derselben Anmerkungen ändert ihn NICHT', () {
      final forward = [note('n1'), note('n2'), note('n3')];
      final backward = forward.reversed.toList();
      expect(
        dayDigestFor(dayWith(), anna, notes: backward),
        dayDigestFor(dayWith(), anna, notes: forward),
        reason:
            'DAS ist der eigentliche Riegel: tool/notify.dart liest per '
            'PostgREST, das ohne `order` keine Reihenfolge zusichert. Ohne '
            'die Sortierung im Digest unterschiede sich der Hash zwischen '
            'zwei Läufen ohne jede Datenänderung — jeder Anwesende bekäme im '
            'Abstand des Cooldowns eine „Änderung"-Meldung über eine '
            'Planänderung, die es nie gab, und zwar dauerhaft.',
      );
    });

    test('eine Anmerkung an einem anderen Tag ändert ihn nicht', () {
      expect(
        dayDigestFor(
          dayWith(),
          anna,
          notes: [note('n1', on: DateTime(2026, 7, 29))],
        ),
        dayDigestFor(dayWith(), anna),
        reason:
            'Die Liste kommt flach für die ganze Woche herein — der Digest '
            'muss selbst auf seinen Tag filtern.',
      );
    });

    test('nur die Kennung zählt, nicht der Text', () {
      expect(
        dayDigestFor(dayWith(), anna, notes: [note('n1', body: 'anders')]),
        dayDigestFor(dayWith(), anna, notes: [note('n1')]),
        reason:
            'Es gibt kein Bearbeiten — dieselbe Kennung ist derselbe Eintrag. '
            'Löschen und neu schreiben ergibt eine neue Kennung und damit '
            'richtigerweise eine Meldung.',
      );
    });

    test('wer nicht dabei ist, behält den festen Wert', () {
      expect(
        dayDigestFor(dayWith(), 'unbekannt', notes: [note('n1')]),
        removedDigest,
        reason:
            'Sonst bekäme jemand, der aus dem Tag heraus ist, weiter '
            'Anmerkungs-Meldungen — der feste Wert ist genau der Riegel '
            'dagegen.',
      );
    });

    test('eine Anmerkung löst eine Änderungs-Meldung aus', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna]),
        sent: [sentEvening(anna, dayDigestFor(dayWith(), anna), mondayEvening)],
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
        notes: [note('n1')],
      );
      expect(due, hasLength(1));
      expect(due.single.kind, PushKind.change);
      expect(
        due.single.body,
        contains('Bernd: Komme erst um 9'),
        reason:
            'Der Text steht bewusst drin, nicht nur eine Zahl: Zugestellt '
            'wird über den trägen Job, und eine späte Meldung, die nur '
            '„1 Anmerkung" sagt, wäre zweimal wertlos.',
      );
    });

    test('ohne Abend-Push gibt es keine Anmerkungs-Meldung', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna], evening: false),
        sent: const [],
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
        notes: [note('n1')],
      );
      expect(
        due,
        isEmpty,
        reason:
            'Anmerkungen reisen als Änderungs-Meldung mit und erben deren '
            'Bedingung. Das ist der bewusst gezahlte Preis dafür, dass es '
            'keine eigene Push-Art gibt — der Benachrichtigungs-Screen sagt '
            'es der Nutzerin.',
      );
    });

    test('mehrere Anmerkungen: die jüngste im Text, der Rest gezählt', () {
      final older = PlanNote(
        id: 'n1',
        date: tuesday,
        personId: anna,
        body: 'Ich fahre',
        createdAt: mondayEvening,
      );
      final newer = PlanNote(
        id: 'n2',
        date: tuesday,
        personId: bernd,
        body: 'Komme erst um 9',
        createdAt: mondayEvening.add(const Duration(minutes: 5)),
      );
      // Bewusst in verkehrter Reihenfolge übergeben: Die Auswahl hängt am
      // Zeitstempel, nicht an der Listenposition.
      expect(
        composeGroupBody(dayWith(), persons, notes: [newer, older]),
        endsWith('Bernd: Komme erst um 9 (+1 weitere)'),
      );
    });

    test('ein langer Text wird gekürzt', () {
      final long = note('n1', body: 'A' * 200);
      final body = composeGroupBody(dayWith(), persons, notes: [long]);
      expect(body, contains('…'));
      expect(
        body.length,
        lessThan(140),
        reason:
            'Eine Benachrichtigung wird ohnehin abgeschnitten — lieber '
            'lesbar kurz als vollständig unlesbar (dieselbe Regel wie bei '
            'der Namensliste).',
      );
    });

    test('das Banner und die Nachricht sagen dasselbe', () {
      final n = [note('n1')];
      expect(
        composeGroupBody(dayWith(), persons, notes: n),
        endsWith('Bernd: Komme erst um 9'),
      );
      expect(
        composeBody(dayWith(), clara, persons, notes: n),
        endsWith('Bernd: Komme erst um 9'),
        reason:
            'Zwei Abnehmer, ein Wortschatz: Trüge nur eine der beiden '
            'compose-Funktionen die Anmerkung, zeigte die Übersicht etwas '
            'anderes als das Handy meldet.',
      );
    });
  });

  group('Feste Vorgaben (#139)', () {
    const full = GroupDefaults(
      outboundTime: DayTime(7, 30),
      returnTime: DayTime(16, 30),
      meetingPoint: 'Parkplatz Rathaus',
    );

    test('Banner und Nachricht nennen Abfahrt, Rückfahrt und Treffpunkt', () {
      for (final body in [
        composeGroupBody(dayWith(), persons, defaults: full),
        composeBody(dayWith(), clara, persons, defaults: full),
      ]) {
        expect(body, contains('Abfahrt 07:30'));
        expect(body, contains('Rückfahrt 16:30'));
        expect(body, contains('Treffpunkt Parkplatz Rathaus'));
      }
    });

    test('ohne Vorgaben ändert sich kein Wort', () {
      expect(
        composeGroupBody(dayWith(), persons, defaults: const GroupDefaults()),
        composeGroupBody(dayWith(), persons),
      );
      expect(
        composeBody(dayWith(), clara, persons, defaults: const GroupDefaults()),
        composeBody(dayWith(), clara, persons),
        reason:
            'Wer die Felder nie ausfüllt, soll von der ganzen Sache nichts '
            'merken — kein „Abfahrt —", kein „Treffpunkt unbekannt".',
      );
    });

    test('eine halb gepflegte Vorgabe nennt nur, was da ist', () {
      final body = composeGroupBody(
        dayWith(),
        persons,
        defaults: const GroupDefaults(meetingPoint: 'Rathaus'),
      );
      expect(body, contains('Treffpunkt Rathaus'));
      expect(body, isNot(contains('Abfahrt')));
      expect(body, isNot(contains('Rückfahrt')));
    });

    test('sie stehen vor der Anmerkung', () {
      final body = composeGroupBody(
        dayWith(),
        persons,
        notes: [
          PlanNote(
            id: 'n1',
            date: tuesday,
            personId: bernd,
            body: 'Komme erst um 9',
            createdAt: mondayEvening,
          ),
        ],
        defaults: full,
      );
      expect(
        body.indexOf('Abfahrt 07:30'),
        lessThan(body.indexOf('Bernd: Komme erst um 9')),
        reason:
            'Eine Anmerkung ist die Abweichung von genau diesen Vorgaben — '
            'sie zuletzt zu lesen ist die Reihenfolge, in der man es sich '
            'sagen würde.',
      );
    });

    test('eine geänderte Vorgabe ändert den Digest NICHT', () {
      // Der Kern der Sache. Nähme der Digest die Vorgaben auf, bekäme beim
      // Speichern im Parameter-Screen die halbe Gruppe eine
      // „Änderung"-Meldung über einen Tag, an dem sich nichts getan hat —
      // und der Digest hängt nicht ohne Grund auch nicht an den Punkten.
      expect(dayDigestFor(dayWith(), bernd), dayDigestFor(dayWith(), bernd));

      final before = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna, bernd, clara]),
        sent: [
          for (final id in [anna, bernd, clara])
            sentEvening(id, dayDigestFor(dayWith(), id), mondayEvening),
        ],
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
        defaults: const GroupDefaults(),
      );
      expect(before, isEmpty);

      final after = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([anna, bernd, clara]),
        sent: [
          for (final id in [anna, bernd, clara])
            sentEvening(id, dayDigestFor(dayWith(), id), mondayEvening),
        ],
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
        defaults: full,
      );
      expect(
        after,
        isEmpty,
        reason:
            'Eine neue Abfahrtszeit ist eine Parameter-Änderung, keine '
            'Planänderung: Sie verschiebt keinen Tag und keinen Fahrer.',
      );
    });

    test('eine fällige Meldung trägt sie trotzdem im Text', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([clara]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
        defaults: full,
      );
      expect(due, hasLength(1));
      expect(due.single.body, contains('Treffpunkt Parkplatz Rathaus'));
    });
  });

  group('Bestätigte Tage (#164)', () {
    /// Der Tag ist eingetragen: Anna fährt, Bernd fährt mit. Clara war
    /// verfügbar, steht aber in keinem Auto — `planWeek` vereint für einen
    /// bestätigten Tag Verfügbarkeit UND Fahrt (#85).
    PlannedDay confirmedDay() => dayWith(
      confirmed: true,
      cars: const [
        PlannedCar(driverId: anna, fullIds: [bernd]),
      ],
    );

    test('wer mitfuhr, bekommt den festen Wert', () {
      expect(dayDigestFor(confirmedDay(), anna), confirmedDigest);
      expect(dayDigestFor(confirmedDay(), bernd), confirmedDigest);
    });

    test('wer nicht mitfuhr, ist raus wie ein Ausgetragener', () {
      expect(
        dayDigestFor(confirmedDay(), clara),
        removedDigest,
        reason:
            'Sie steht noch in availableIds, ist aber nicht mitgefahren. Für '
            'sie ist der Tag vorbei — und der Text sagt dasselbe.',
      );
      expect(
        composeBody(confirmedDay(), clara, persons),
        contains('nicht mehr eingetragen'),
      );
    });

    test('das Eintragen selbst löst keine Meldung aus', () {
      // Vorher: geplanter Tag, Abend-Push ist raus. Jetzt ist die Fahrt
      // eingetragen — für Anna und Bernd wechselt der Digest auf 'fix'.
      final due = dueMessages(
        week: [confirmedDay()],
        prefs: prefsFor([anna, bernd]),
        sent: [
          for (final id in [anna, bernd])
            sentEvening(id, dayDigestFor(dayWith(), id), mondayEvening),
        ],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(
        due,
        isEmpty,
        reason:
            'Eine eingetragene Fahrt ist keine Meldung wert — sie ist ja '
            'schon passiert. Ohne den fix-Riegel bekäme die halbe Gruppe '
            'beim Eintragen eine „Änderung".',
      );
    });

    test('eine gelöschte Fahrt meldet sich dagegen', () {
      final due = dueMessages(
        week: [dayWith()],
        prefs: prefsFor([bernd]),
        sent: [sentEvening(bernd, confirmedDigest, mondayEvening)],
        persons: persons,
        now: DateTime(2026, 7, 28, 6, 0),
      );
      expect(due, hasLength(1));
      expect(
        due.single.kind,
        PushKind.change,
        reason:
            'Der Weg HERAUS aus „fix" ist eine echte Änderung: Der Tag ist '
            'wieder Planung, und wer fährt, steht neu zur Debatte.',
      );
    });

    test('am eingetragenen Tag kommt kein Abend-Blick mehr', () {
      final due = dueMessages(
        week: [confirmedDay()],
        prefs: prefsFor([anna, bernd]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
      );
      expect(due, isEmpty);
    });
  });

  group('Abfahrts-Erinnerung (#164)', () {
    const legs = GroupDefaults(
      outboundTime: DayTime(7, 30),
      returnTime: DayTime(16, 30),
    );

    /// Nur die Erinnerung eingeschaltet — Abend-Blick und Änderungen aus.
    ///
    /// Die Trennung ist der Punkt: Das Plan-Fenster (Abend davor bis 7:30)
    /// überlappt das Erinnerungs-Fenster, ein mitlaufender Abend-Push machte
    /// jede Prüfung hier unlesbar. Dass beide Arten NEBENEINANDER bestehen,
    /// prüft der vorletzte Test dieser Gruppe.
    Map<String, NotificationPrefs> remindingPrefs(
      List<String> ids, {
      int lead = defaultReminderLead,
      int? returnLead,
    }) => {
      for (final id in ids)
        id: NotificationPrefs.initial(id).copyWith(
          eveningEnabled: false,
          changesEnabled: false,
          remindersEnabled: true,
          reminderLeadMinutes: lead,
          reminderLeadReturnMinutes: returnLead ?? lead,
        ),
    };

    List<DuePush> at(
      DateTime now, {
      Map<String, NotificationPrefs>? prefs,
      GroupDefaults defaults = legs,
      PlannedDay? day,
      List<SentPush> sent = const [],
    }) => dueMessages(
      week: [day ?? dayWith()],
      prefs: prefs ?? remindingPrefs([anna, bernd, clara]),
      sent: sent,
      persons: persons,
      now: now,
      defaults: defaults,
    );

    /// #168: Hin- und Rückweg starten nicht am selben Ort — fünfzehn
    /// Minuten zum Morgen-Treffpunkt, dreißig zum Treffpunkt für zurück.
    /// Die alte Begründung („wer morgens fünf Minuten braucht, braucht sie
    /// abends auch") ist damit widerlegt, und diese drei Tests halten fest,
    /// dass die beiden Vorläufe wirklich getrennt wirken.
    group('Ein eigener Vorlauf je Richtung (#168)', () {
      test('die Rückfahrt weckt nach ihrem eigenen Vorlauf', () {
        final prefs = remindingPrefs([anna], lead: 15, returnLead: 30);

        // 16:05 — dreißig Minuten vor 16:30 liegt IM Fenster der Rückfahrt,
        // fünfzehn Minuten davor noch nicht.
        final early = at(DateTime(2026, 7, 28, 16, 5), prefs: prefs);
        expect(
          early.map((m) => m.kind),
          contains(PushKind.departureReturn),
          reason: 'Mit 30 Minuten Vorlauf ist 16:05 fällig.',
        );
      });

      test('der Vorlauf der Hinfahrt gilt nicht für die Rückfahrt', () {
        // Umgekehrt: 30 hin, 15 zurück. Um 16:05 darf NICHTS kommen —
        // täte es das, rechnete die Rückfahrt mit dem Wert der Hinfahrt.
        final prefs = remindingPrefs([anna], lead: 30, returnLead: 15);
        expect(at(DateTime(2026, 7, 28, 16, 5), prefs: prefs), isEmpty);
        expect(
          at(DateTime(2026, 7, 28, 16, 20), prefs: prefs).map((m) => m.kind),
          contains(PushKind.departureReturn),
        );
      });

      test('und die Hinfahrt nicht mit dem der Rückfahrt', () {
        final prefs = remindingPrefs([anna], lead: 15, returnLead: 45);
        // 6:50 wäre mit 45 Minuten Vorlauf fällig — mit 15 nicht.
        expect(at(DateTime(2026, 7, 28, 6, 50), prefs: prefs), isEmpty);
        expect(
          at(DateTime(2026, 7, 28, 7, 20), prefs: prefs).map((m) => m.kind),
          contains(PushKind.departureOut),
        );
      });
    });

    test('kommt im Vorlauf-Fenster, für beide Richtungen', () {
      final out = at(DateTime(2026, 7, 28, 7, 20));
      expect(out.map((d) => d.kind).toSet(), {PushKind.departureOut});
      expect(out.map((d) => d.personId).toSet(), {anna, bernd, clara});
      expect(out.first.title, 'Abfahrt 07:30 Uhr');

      final back = at(DateTime(2026, 7, 28, 16, 20));
      expect(back.map((d) => d.kind).toSet(), {PushKind.departureReturn});
      expect(back.first.title, 'Rückfahrt 16:30 Uhr');
    });

    test('kommt nicht zu früh und nicht mehr nach der Abfahrt', () {
      expect(at(DateTime(2026, 7, 28, 7, 14)), isEmpty);
      expect(
        at(DateTime(2026, 7, 28, 7, 30)),
        isEmpty,
        reason:
            'Um 07:30 fährt das Auto. Eine Erinnerung „gleich geht es los" '
            'wäre da eine Erinnerung an etwas, das gerade passiert.',
      );
    });

    test('der Vorlauf verschiebt das Fenster', () {
      // 6:50 liegt bei 15 Minuten Vorlauf weit davor, bei 45 mitten drin.
      expect(
        at(DateTime(2026, 7, 28, 6, 50), prefs: remindingPrefs([anna])),
        isEmpty,
      );
      expect(
        at(
          DateTime(2026, 7, 28, 6, 50),
          prefs: remindingPrefs([anna], lead: 45),
        ),
        hasLength(1),
      );
      expect(
        at(
          DateTime(2026, 7, 28, 6, 44),
          prefs: remindingPrefs([anna], lead: 45),
        ),
        isEmpty,
      );
    });

    test('ohne Opt-in kommt nichts', () {
      expect(
        at(
          DateTime(2026, 7, 28, 7, 20),
          // Alles andere ebenfalls aus — sonst prüfte der Test den
          // Abend-Blick statt der Erinnerung.
          prefs: prefsFor([anna, bernd], evening: false, changes: false),
        ),
        isEmpty,
        reason:
            'Vorgabe AUS: Sie meldet sich an einem Tag, an dem gar nichts '
            'passiert ist — wer das nicht will, soll es nicht abschalten '
            'müssen.',
      );
    });

    test('ohne Gruppenzeit kommt nichts', () {
      expect(
        at(DateTime(2026, 7, 28, 7, 20), defaults: const GroupDefaults()),
        isEmpty,
      );
      // Nur die Hinfahrt gepflegt: dann gibt es abends auch nichts.
      expect(
        at(
          DateTime(2026, 7, 28, 16, 20),
          defaults: const GroupDefaults(outboundTime: DayTime(7, 30)),
        ),
        isEmpty,
      );
    });

    test('nicht an Ausgetragene', () {
      final without = dayWith(
        available: const [anna, bernd],
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd]),
        ],
      );
      expect(
        at(
          DateTime(2026, 7, 28, 7, 20),
          day: without,
        ).map((d) => d.personId).toSet(),
        {anna, bernd},
      );
    });

    test('gerade AM eingetragenen Tag — dafür ist sie da', () {
      final confirmed = dayWith(
        confirmed: true,
        cars: const [
          PlannedCar(driverId: anna, fullIds: [bernd]),
        ],
      );
      final due = at(DateTime(2026, 7, 28, 7, 20), day: confirmed);
      expect(
        due.map((d) => d.personId).toSet(),
        {anna, bernd},
        reason:
            'Der Digest ist hier „fix" — und der ist ausdrücklich NICHT '
            'ausgeschlossen: An einem eingetragenen Tag fährt die Gruppe '
            'gerade, das ist der Moment, für den die Erinnerung gebaut wurde.',
      );
      expect(due.every((d) => d.digest == confirmedDigest), isTrue);
    });

    test('genau einmal je Richtung', () {
      final sent = [
        SentPush(
          personId: anna,
          planDate: tuesday,
          kind: PushKind.departureOut,
          digest: 'egal',
          sentAt: DateTime(2026, 7, 28, 7, 15),
        ),
      ];
      final due = at(
        DateTime(2026, 7, 28, 7, 20),
        prefs: remindingPrefs([anna]),
        sent: sent,
      );
      expect(
        due,
        isEmpty,
        reason:
            'Zeitgetrieben, also genau einmal: Ein Nachholen wäre die '
            'Erinnerung an eine Abfahrt, die schon war.',
      );
      // Die Rückfahrt hat ihren eigenen Riegel und ist davon unberührt.
      expect(
        at(
          DateTime(2026, 7, 28, 16, 20),
          prefs: remindingPrefs([anna]),
          sent: sent,
        ),
        hasLength(1),
      );
    });

    test('hängt nicht am Abend-Blick', () {
      // `remindingPrefs` hat Abend-Blick UND Änderungen aus — trotzdem kommt
      // sie. Anders als die Änderungs-Meldung braucht sie keinen Abend-Push
      // in `push_log`: Sie hängt an der Uhr der Gruppe. Wer nur den Schubs
      // kurz vorher will, bekommt ihn auch allein.
      expect(
        at(DateTime(2026, 7, 28, 7, 20), prefs: remindingPrefs([anna])),
        hasLength(1),
      );
    });

    test('steht neben dem Abend-Blick, nicht statt seiner', () {
      final prefs = {
        anna: NotificationPrefs.initial(anna).copyWith(remindersEnabled: true),
      };
      // Alles an, nichts verschickt: Um 7:20 ist das Abend-Fenster noch
      // offen (bis 7:30) und das Erinnerungs-Fenster auch.
      final due = at(DateTime(2026, 7, 28, 7, 20), prefs: prefs);
      expect(
        due.map((d) => d.kind).toSet(),
        {PushKind.evening, PushKind.departureOut},
        reason:
            'Zwei Arten, zwei Fenster, ein Lauf — sie schließen einander '
            'nicht aus. In `push_due()` ist das der `union all`.',
      );
    });

    test('der Text ist der des Tages, samt Vorgaben', () {
      final due = at(
        DateTime(2026, 7, 28, 7, 20),
        prefs: remindingPrefs([bernd]),
        defaults: const GroupDefaults(
          outboundTime: DayTime(7, 30),
          meetingPoint: 'Parkplatz Rathaus',
        ),
      );
      expect(due.single.body, contains('Anna fährt'));
      expect(due.single.body, contains('Treffpunkt Parkplatz Rathaus'));
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

    // Dasselbe für den Rückfahrt-Vorlauf (#168). Er steht in einer eigenen
    // Migration, weil die Spalte später dazukam — geprüft wird trotzdem
    // gegen dieselbe Dart-Vorbelegung.
    expect(
      File(
        'supabase/migrations/20260805010000_split_reminder_lead.sql',
      ).readAsStringSync(),
      contains(
        'reminder_lead_return_minutes integer not null\n    default '
        '${initial.reminderLeadReturnMinutes}',
      ),
      reason:
          'Ein Alt-Client schreibt diese Spalte nie — dann gilt der '
          'DB-Default, und der muss das sagen, was der Screen anzeigt.',
    );

    // Dasselbe für die Erinnerung (#164) — in ihrer eigenen Migration.
    final reminders = File(
      'supabase/migrations/20260803140000_departure_reminders.sql',
    ).readAsStringSync();
    expect(
      initial.remindersEnabled,
      isFalse,
      reason: 'Opt-in: Vorgabe AUS, in Dart wie in der Datenbank.',
    );
    expect(
      reminders,
      contains('reminders_enabled boolean not null default false'),
    );
    expect(
      reminders,
      contains(
        'reminder_lead_minutes integer not null default '
        '${initial.reminderLeadMinutes}',
      ),
    );
  });
}

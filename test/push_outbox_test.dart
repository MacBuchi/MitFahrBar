/// push_outbox_test.dart – Der Ausgangskorb (#132) muss dasselbe hergeben
/// wie der bisherige Versandweg.
///
/// Das ist der eigentliche Beweis dieser Umstellung. Der Text wird künftig
/// **beim Schreiben** gerechnet statt beim Senden; wenn dabei auch nur die
/// Kopfzeile anders lautet, bekäme die Gruppe ab dem Umschalten andere
/// Nachrichten als vorher — und niemand hätte einen Anhaltspunkt, warum.
///
/// Deshalb wird hier nicht geprüft, dass „etwas herauskommt", sondern dass
/// zu **jeder** Nachricht, die [dueMessages] erzeugt, eine Korb-Zeile mit
/// demselben Digest, demselben Text und derselben Kopfzeile existiert.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/core/push_digest.dart';
import 'package:mitfahrbar/core/push_outbox.dart';
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

  PlannedDay dayWith({
    List<String> available = const [anna, bernd, clara],
    List<PlannedCar> cars = const [
      PlannedCar(driverId: anna, fullIds: [bernd, clara]),
    ],
    bool confirmed = false,
  }) => PlannedDay(
    date: tuesday,
    availableIds: available,
    oneWayIds: const {},
    suggestedDriverIds: [for (final car in cars) car.driverId],
    cars: cars,
    confirmed: confirmed,
  );

  Map<String, NotificationPrefs> prefsFor(List<String> ids) => {
    for (final id in ids) id: NotificationPrefs.initial(id),
  };

  OutboxEntry entryFor(List<OutboxEntry> box, String personId) =>
      box.firstWhere(
        (e) => e.personId == personId && e.date == tuesday,
        orElse: () => throw StateError('keine Korb-Zeile für $personId'),
      );

  /// Die Kopfzeile, die der Versender aus der Zeile wählen würde.
  String titleFor(OutboxEntry entry, PushKind kind) =>
      kind == PushKind.evening ? entry.titleEvening : entry.titleChange;

  group('Gleichstand mit dem bisherigen Versandweg', () {
    test('Abend-Blick: Digest, Text und Kopfzeile stimmen überein', () {
      final week = [dayWith()];
      final due = dueMessages(
        week: week,
        prefs: prefsFor([anna, bernd, clara]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
      );
      final box = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
      );

      expect(due, isNotEmpty, reason: 'Sonst prüft der Vergleich nichts.');
      for (final message in due) {
        final entry = entryFor(box, message.personId);
        expect(entry.digest, message.digest);
        expect(entry.body, message.body);
        expect(titleFor(entry, message.kind), message.title);
      }
    });

    test('Änderung: auch die „Ausgetragen"-Kopfzeile stimmt', () {
      // Clara ist raus — der Fall, für den es `removedDigest` gibt.
      final week = [
        dayWith(
          available: const [anna, bernd],
          cars: const [
            PlannedCar(driverId: anna, fullIds: [bernd]),
          ],
        ),
      ];
      final before = dayWith();
      final sent = [
        for (final id in [anna, bernd, clara])
          SentPush(
            personId: id,
            planDate: tuesday,
            kind: PushKind.evening,
            digest: dayDigestFor(before, id),
            sentAt: mondayEvening,
          ),
      ];
      final due = dueMessages(
        week: week,
        prefs: prefsFor([anna, bernd, clara]),
        sent: sent,
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
      );
      final box = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening.add(const Duration(hours: 1)),
      );

      expect(
        due.any((m) => m.personId == clara && m.digest == removedDigest),
        isTrue,
        reason:
            'Ohne die Austrag-Meldung prüft der Vergleich den Sonderfall '
            'nicht, um den es hier geht.',
      );
      for (final message in due) {
        final entry = entryFor(box, message.personId);
        expect(entry.digest, message.digest);
        expect(entry.body, message.body);
        expect(
          titleFor(entry, message.kind),
          message.title,
          reason:
              'Der Korb trägt beide Kopfzeilen, weil der Client nicht weiß, '
              'welche Art die Meldung wird — `push_log` sieht nur der '
              'Versender. Stimmte die falsche, bekäme die Gruppe beim '
              'Austragen „Änderung" statt „Ausgetragen".',
        );
      }
    });

    test('Anmerkungen reisen im Text mit', () {
      final week = [dayWith()];
      final notes = [
        PlanNote(
          id: 'n1',
          date: tuesday,
          personId: bernd,
          body: 'Komme erst um 9',
          createdAt: mondayEvening,
        ),
      ];
      final due = dueMessages(
        week: week,
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
        notes: notes,
      );
      final box = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
        notes: notes,
      );

      expect(due.single.body, contains('Komme erst um 9'));
      expect(entryFor(box, anna).body, due.single.body);
      expect(
        entryFor(box, anna).digest,
        due.single.digest,
        reason:
            'Die Notiz-Kennungen stecken im Digest — driftete das, meldete '
            'der Versand endlos „Änderung" ohne Änderung.',
      );
    });
  });

  group('Umfang des Korbs', () {
    test('eingetragene Tage bleiben draußen', () {
      final box = outboxEntries(
        week: [dayWith(confirmed: true)],
        persons: persons,
        now: mondayEvening,
      );
      expect(
        box,
        isEmpty,
        reason:
            'Ein eingetragener Tag ist gelaufen — dieselbe Regel wie in '
            'dueMessages. Stünde er im Korb, käme nach der Fahrt noch eine '
            'Meldung über sie.',
      );
    });

    test('auch Abwesende bekommen eine Zeile', () {
      final box = outboxEntries(
        week: [
          dayWith(
            available: const [anna, bernd],
            cars: const [
              PlannedCar(driverId: anna, fullIds: [bernd]),
            ],
          ),
        ],
        persons: persons,
        now: mondayEvening,
      );
      expect(
        entryFor(box, clara).digest,
        removedDigest,
        reason:
            'Der Client weiß nicht, wer schon einen Abend-Blick hat — das '
            'steht in `push_log`, und das darf er nicht lesen. Ohne Zeile '
            'für Abwesende erführe niemand mehr, dass er ausgetragen wurde. '
            'Der Versand schickt einem Abwesenden trotzdem keinen '
            'Abend-Blick.',
      );
    });
  });
}

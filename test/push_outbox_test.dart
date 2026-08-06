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
    test('eingetragene Tage bekommen Zeilen mit festem Digest', () {
      final box = outboxEntries(
        week: [dayWith(confirmed: true)],
        persons: persons,
        now: mondayEvening,
      );
      expect(
        entryFor(box, anna).digest,
        confirmedDigest,
        reason:
            'Bis v0.57.0 ließ der Korb eingetragene Tage aus — die alte Zeile '
            'blieb mit ihrem Plan-Hash stehen und passte zu nichts mehr. Die '
            'Abfahrts-Erinnerung (#164) braucht die Zeile gerade dann: Sie '
            'meldet sich, wenn die Fahrt feststeht. Dass daraus keine '
            'Plan-Meldung wird, regelt der feste Digest, nicht das Auslassen.',
      );
    });

    test('an einem eingetragenen Tag ist draußen, wer nicht mitfuhr', () {
      // `planWeek` vereint für einen bestätigten Tag Verfügbarkeit UND
      // Fahrt (#85) — Clara steht also weiter in availableIds, obwohl die
      // Fahrt ohne sie eingetragen wurde.
      final box = outboxEntries(
        week: [
          dayWith(
            confirmed: true,
            cars: const [
              PlannedCar(driverId: anna, fullIds: [bernd]),
            ],
          ),
        ],
        persons: persons,
        now: mondayEvening,
      );
      expect(entryFor(box, bernd).digest, confirmedDigest);
      expect(
        entryFor(box, clara).digest,
        removedDigest,
        reason:
            'Für sie ist der Tag vorbei wie für eine Ausgetragene — und der '
            'Text muss dasselbe sagen wie der Digest, sonst stünde über einer '
            'Fahrtbeschreibung die Kopfzeile „Ausgetragen".',
      );
      expect(entryFor(box, clara).body, contains('nicht mehr eingetragen'));
    });

    test('feste Vorgaben (#139) stehen im Korb wie in der Meldung', () {
      const defaults = GroupDefaults(
        outboundTime: DayTime(7, 30),
        returnTime: DayTime(16, 30),
        meetingPoint: 'Parkplatz Rathaus',
      );
      final week = [dayWith()];
      final due = dueMessages(
        week: week,
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
        defaults: defaults,
      );
      final box = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
        defaults: defaults,
      );

      expect(due.single.body, contains('Abfahrt 07:30'));
      expect(entryFor(box, anna).body, due.single.body);
      expect(
        entryFor(box, anna).digest,
        due.single.digest,
        reason:
            'Die Vorgaben stehen im TEXT, nicht im Digest. Wanderten sie '
            'hinein, löste ein Speichern im Parameter-Screen eine '
            '„Änderung"-Meldung über einen unveränderten Tag aus.',
      );
    });

    test('die Erinnerungs-Kopfzeilen tragen die Gruppenzeit (#164)', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
        defaults: const GroupDefaults(
          outboundTime: DayTime(7, 30),
          returnTime: DayTime(16, 30),
        ),
      );
      final entry = entryFor(box, anna);
      expect(entry.titleOut, 'Abfahrt 07:30 Uhr');
      expect(entry.titleReturn, 'Rückfahrt 16:30 Uhr');
      expect(
        entry.toJson()['title_out'],
        'Abfahrt 07:30 Uhr',
        reason:
            'Die Kopfzeile reist im selben Upsert mit — sonst stünde in der '
            'Datenbank NULL, und `push_due()` verlangt sie.',
      );
    });

    test('ohne Gruppenzeit bleibt die Kopfzeile leer', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
        defaults: const GroupDefaults(outboundTime: DayTime(7, 30)),
      );
      final entry = entryFor(box, anna);
      expect(entry.titleOut, isNotNull);
      expect(
        entry.titleReturn,
        isNull,
        reason:
            'Ohne Zeit keine Erinnerung, ohne Erinnerung keine Kopfzeile. '
            'Ein blankes „Rückfahrt" wäre eine Meldung, die nichts sagt.',
      );
    });

    test('nur die eigene Zeile unterdrückt die Eintrag-Meldung (#163)', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
        suppressPersonId: anna,
      );
      expect(entryFor(box, anna).suppressRoster, isTrue);
      expect(
        entryFor(box, bernd).suppressRoster,
        isFalse,
        reason:
            'Unterdrückt wird die Meldung über die eigene Änderung, nicht '
            'die der anderen — sonst hörte die Gruppe nichts mehr davon, '
            'sobald ein Gerät zugeordnet ist.',
      );
      expect(
        entryFor(box, anna).titleRoster,
        'Eingetragen · Morgen (Di, 28.07.)',
      );
    });

    test('ohne Geräte-Zuordnung wird nichts unterdrückt', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
      );
      expect(
        box.every((e) => !e.suppressRoster),
        isTrue,
        reason:
            'So schreibt der stündliche Job — er weiß nicht, wer getippt '
            'hat, und überstimmt damit im Reparaturfall. Lieber eine '
            'Meldung zu viel als eine, die niemand bekommt.',
      );
    });

    test('Plan-Zeilen tragen die Art „plan"', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
      );
      expect(box.every((e) => e.kind == 'plan'), isTrue);
      expect(entryFor(box, anna).toJson()['kind'], 'plan');
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

  group('Was der Korb behalten muss (#177)', () {
    // 2026-07-27 ist ein Montag, 2026-07-31 der Freitag, 2026-08-03 der
    // Montag danach.
    final monday = DateTime(2026, 7, 27);
    final friday = DateTime(2026, 7, 31);
    final nextMonday = DateTime(2026, 8, 3);

    test('am Freitagnachmittag bleibt dieser Freitag stehen', () {
      expect(
        outboxKeepFrom(DateTime(2026, 7, 31, 14)),
        friday,
        reason:
            'Ab Freitagmittag liefert `planningWeek` den nächsten Montag — '
            'als `keep_from` genommen löschte das die Zeilen DIESES Freitags, '
            'und die Rückfahrt-Erinnerung um 16:20 hätte nichts mehr, aus dem '
            'sie feuern könnte. Der Planer darf vorausblicken, der Korb darf '
            'den Tag nicht wegwerfen, über den er noch meldet.',
      );
      expect(
        planningWeek(DateTime(2026, 7, 31, 14)).first,
        nextMonday,
        reason:
            'Die Gegenprobe zur Regel: `planningWeek` selbst bleibt '
            'unverändert: Der Planer soll am Freitagnachmittag die kommende '
            'Woche zeigen. Geändert wird nur, was der Korb daraus macht.',
      );
    });

    test('vor Freitagmittag ist es unverändert der Wochenmontag', () {
      expect(outboxKeepFrom(DateTime(2026, 7, 31, 11, 59)), monday);
      expect(
        outboxKeepFrom(DateTime(2026, 7, 29, 14)),
        monday,
        reason:
            'Mitten in der Woche liegt der Wochenmontag vor heute — dann '
            'gewinnt er, sonst räumte jeder Schreibvorgang die Tage weg, die '
            'diese Woche schon hinter uns liegen, aber noch zur Planwoche '
            'gehören.',
      );
    });

    test('am Samstag darf der Freitag weg', () {
      expect(
        outboxKeepFrom(DateTime(2026, 8, 1, 9)),
        DateTime(2026, 8, 1),
        reason:
            'Die Regel ist „nie über heute hinaus", nicht „behalte den '
            'Freitag". Am Samstag ist seine letzte Erinnerung gefallen, die '
            'Zeile hat ihren Zweck erfüllt — bliebe sie liegen, wüchse der '
            'Korb mit jedem Tag.',
      );
    });
  });
}

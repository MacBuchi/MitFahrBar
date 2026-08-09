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

import 'dart:io';

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

  group('Abweichung eines Tages (#183)', () {
    const group = GroupDefaults(
      outboundTime: DayTime(7, 30),
      returnTime: DayTime(16, 30),
      meetingPoint: 'Parkplatz Rathaus',
    );

    test('aufgelöst wird feldweise, nicht objektweise', () {
      final merged = effectiveDefaults(
        group,
        const GroupDefaults(outboundTime: DayTime(6, 45)),
      );
      expect(merged.outboundTime, const DayTime(6, 45));
      expect(
        merged.returnTime,
        const DayTime(16, 30),
        reason:
            'Ein Tag, der nur die Hinfahrt verschiebt, behält die Rückfahrt '
            'der Gruppe. Objektweise ersetzt fiele sie auf null — und die '
            'Rückfahrt-Erinnerung entfiele stillschweigend.',
      );
      expect(merged.meetingPoint, 'Parkplatz Rathaus');
    });

    test('ohne Abweichung bleibt die Vorgabe unangetastet', () {
      expect(effectiveDefaults(group, null), group);
      expect(effectiveDefaults(group, const GroupDefaults()), group);
    });

    test('der Digest ändert sich, wenn der TAG eine andere Zeit bekommt', () {
      final week = [dayWith()];
      final plain = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
        defaults: group,
      );
      final moved = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
        defaults: group,
        dayDefaults: {
          tuesday: const GroupDefaults(outboundTime: DayTime(6, 45)),
        },
      );
      expect(
        entryFor(moved, anna).digest,
        isNot(entryFor(plain, anna).digest),
        reason:
            'Eine verschobene Abfahrt ist eine Tatsache über diesen Tag. Wer '
            'sie verschiebt, muss die Mitfahrenden wecken — sonst stünde die '
            'neue Zeit im Planer und das Handy klingelte zur alten.',
      );
    });

    test('der Digest ändert sich NICHT, wenn die GRUPPE ihre Zeit ändert', () {
      final week = [dayWith()];
      String digestWith(GroupDefaults defaults) => entryFor(
        outboxEntries(
          week: week,
          persons: persons,
          now: mondayEvening,
          defaults: defaults,
        ),
        anna,
      ).digest;

      expect(
        digestWith(group),
        digestWith(
          const GroupDefaults(
            outboundTime: DayTime(6, 45),
            returnTime: DayTime(16, 30),
            meetingPoint: 'Parkplatz Rathaus',
          ),
        ),
        reason:
            'Die andere Hälfte derselben Regel: Die Vorgabe ist ein '
            'Parameter. Stünde sie im Digest, bekäme beim Speichern im '
            'Parameter-Screen die halbe Gruppe eine „Änderung"-Meldung über '
            'einen Tag, an dem sich nichts getan hat.',
      );
    });

    test('eine leere Abweichung zählt wie gar keine', () {
      final week = [dayWith()];
      String digestWith(Map<DateTime, GroupDefaults> byDay) => entryFor(
        outboxEntries(
          week: week,
          persons: persons,
          now: mondayEvening,
          defaults: group,
          dayDefaults: byDay,
        ),
        anna,
      ).digest;

      expect(
        digestWith(const {}),
        digestWith({tuesday: const GroupDefaults()}),
        reason:
            'Sonst hinge an einer inhaltlosen Zeile eine Meldung — und ein '
            'Client, der die Abweichung noch nicht kennt, rechnete für '
            'denselben unveränderten Tag einen anderen Digest. Jeder Wechsel '
            'zwischen beiden wäre eine „Änderung" an alle Anwesenden.',
      );
    });

    test('die Zeile trägt die WIRKSAME Zeit, nicht die der Gruppe', () {
      final box = outboxEntries(
        week: [dayWith()],
        persons: persons,
        now: mondayEvening,
        defaults: group,
        dayDefaults: {
          tuesday: const GroupDefaults(outboundTime: DayTime(6, 45)),
        },
      );
      final entry = entryFor(box, anna);
      expect(
        entry.outboundTime,
        const DayTime(6, 45),
        reason:
            'Aus dieser Spalte feuert `push_due()`. Stünde dort die Vorgabe, '
            'käme die Erinnerung zur alten Zeit — und ab Stufe B kann der '
            'Versand sie gar nicht selbst ausrechnen: Sie hängt daran, in '
            'welchem Auto die Person sitzt, und das weiß nur `planWeek`.',
      );
      expect(entry.returnTime, const DayTime(16, 30));
      expect(
        entry.titleOut,
        contains('06:45'),
        reason: 'Die Kopfzeile nennt dieselbe Zeit wie die Spalte daneben.',
      );
      expect(
        entry.body,
        contains('Abfahrt 06:45'),
        reason:
            'Und der Text auch — Banner und Meldung kommen aus derselben '
            'Funktion, sie dürfen nicht auseinanderlaufen.',
      );
    });

    test('dueMessages und der Korb bleiben einig', () {
      final week = [dayWith()];
      final dayDefaults = {
        tuesday: const GroupDefaults(outboundTime: DayTime(6, 45)),
      };
      final due = dueMessages(
        week: week,
        prefs: prefsFor([anna]),
        sent: const [],
        persons: persons,
        now: mondayEvening,
        defaults: group,
        dayDefaults: dayDefaults,
      );
      final box = outboxEntries(
        week: week,
        persons: persons,
        now: mondayEvening,
        defaults: group,
        dayDefaults: dayDefaults,
      );
      expect(due.single.body, entryFor(box, anna).body);
      expect(
        due.single.digest,
        entryFor(box, anna).digest,
        reason:
            'Der Dart-Spiegel von `push_due()` muss dieselbe Rechnung machen '
            'wie der Korb; sonst prüft dieser Test einen Weg, den es in '
            'Produktion nicht gibt.',
      );
    });
  });

  group('Abweichung eines Autos (#183, Stufe B)', () {
    const group = GroupDefaults(
      outboundTime: DayTime(7, 30),
      returnTime: DayTime(16, 30),
    );
    // Zwei Autos: Anna fährt Bernd, Clara fährt allein.
    PlannedDay twoCars() => dayWith(
      cars: const [
        PlannedCar(driverId: anna, fullIds: [bernd]),
        PlannedCar(driverId: clara),
      ],
    );

    List<OutboxEntry> boxWith(Map<String, GroupDefaults> cars) => outboxEntries(
      week: [twoCars()],
      persons: persons,
      now: mondayEvening,
      defaults: group,
      carDefaults: {tuesday: cars},
    );

    test('nur das eigene Auto bekommt die abweichende Zeit', () {
      final box = boxWith({
        clara: const GroupDefaults(outboundTime: DayTime(6, 45)),
      });
      expect(
        entryFor(box, clara).outboundTime,
        const DayTime(6, 45),
        reason: 'Clara fährt ihr eigenes Auto und hat es früher gelegt.',
      );
      for (final id in [anna, bernd]) {
        expect(
          entryFor(box, id).outboundTime,
          const DayTime(7, 30),
          reason:
              'Anna und Bernd sitzen im anderen Auto und fahren unverändert. '
              'Genau dafür steht die Zeit je ZEILE im Korb: Der Versand kann '
              'sie nicht selbst ausrechnen, sie hängt an der Zuordnung aus '
              '`planWeek`.',
        );
      }
    });

    test('geweckt wird nur, wer in dem Auto sitzt', () {
      final before = outboxEntries(
        week: [twoCars()],
        persons: persons,
        now: mondayEvening,
        defaults: group,
      );
      final after = boxWith({
        clara: const GroupDefaults(outboundTime: DayTime(6, 45)),
      });
      expect(
        entryFor(after, clara).digest,
        isNot(entryFor(before, clara).digest),
      );
      for (final id in [anna, bernd]) {
        expect(
          entryFor(after, id).digest,
          entryFor(before, id).digest,
          reason:
              'Für sie hat sich nichts geändert. Eine Meldung an den ganzen '
              'Tag wäre falsch — sie fahren zur selben Zeit wie vorher.',
        );
      }
    });

    test('das Auto schlägt den Tag, der Tag die Gruppe — feldweise', () {
      final box = outboxEntries(
        week: [twoCars()],
        persons: persons,
        now: mondayEvening,
        defaults: group,
        dayDefaults: {
          tuesday: const GroupDefaults(
            outboundTime: DayTime(7, 0),
            returnTime: DayTime(17, 0),
          ),
        },
        carDefaults: {
          tuesday: {clara: const GroupDefaults(outboundTime: DayTime(6, 45))},
        },
      );
      final entry = entryFor(box, clara);
      expect(entry.outboundTime, const DayTime(6, 45), reason: 'vom Auto');
      expect(
        entry.returnTime,
        const DayTime(17, 0),
        reason:
            'Vom Tag — ihr Auto hat die Rückfahrt nicht angefasst. '
            'Objektweise ersetzt fiele sie auf die Gruppenzeit zurück oder '
            'ganz weg, und die Rückfahrt-Erinnerung käme zur falschen Zeit.',
      );
      expect(
        entryFor(box, anna).outboundTime,
        const DayTime(7, 0),
        reason: 'Annas Auto hat nichts gesetzt — für sie gilt der Tag.',
      );
    });

    test('ein Eintrag zu einem Nicht-Fahrer wirkt nicht', () {
      final box = boxWith({
        // Bernd fährt an diesem Tag nicht; seine Zeile ist übrig geblieben,
        // weil der Vorschlag inzwischen gekippt ist.
        bernd: const GroupDefaults(outboundTime: DayTime(5, 0)),
      });
      for (final id in [anna, bernd, clara]) {
        expect(
          entryFor(box, id).outboundTime,
          const DayTime(7, 30),
          reason:
              'Eine verwaiste Zeile fällt beim Auflösen heraus, statt '
              'irgendjemanden um fünf zu wecken. Aufgeräumt wird sie nie — '
              'dafür müsste jemand den Plan nachrechnen, und das ist genau '
              'die zweite Wahrheit, die der Korb vermeidet.',
        );
      }
    });

    test('dueMessages rechnet dasselbe', () {
      final week = [twoCars()];
      final cars = {
        tuesday: {clara: const GroupDefaults(outboundTime: DayTime(6, 45))},
      };
      final due = dueMessages(
        week: week,
        // Die Erinnerung ist Opt-in und ohne dieses Flag aus — sonst prüfte
        // der Test einen Zweig, den er nie erreicht.
        prefs: {
          for (final id in [anna, bernd, clara])
            id: NotificationPrefs.initial(id).copyWith(remindersEnabled: true),
        },
        sent: const [],
        persons: persons,
        // 06:35 ist Claras Vorlauf, für Anna und Bernd passiert nichts.
        now: DateTime(2026, 7, 28, 6, 35),
        defaults: group,
        carDefaults: cars,
      );
      // Nur die Erinnerungen: Der Abend-Blick liegt um diese Zeit für alle
      // im Fenster (bis zur persönlichen departure_time) und gehört nicht
      // zur Frage.
      final reminders = due.where((d) => d.kind.isDeparture);
      expect(
        reminders.map((d) => d.personId).toSet(),
        {clara},
        reason:
            'Der Dart-Spiegel muss dieselbe Rechnung machen wie `push_due()` '
            'über die Korb-Zeilen; sonst prüft die Suite einen Weg, den es '
            'in Produktion nicht gibt. Um 06:35 ist nur Claras Auto dran — '
            'die anderen fahren erst um 7:30.',
      );
      expect(reminders.single.kind, PushKind.departureOut);
    });
  });

  group('Der Gruppen-Schalter (#213)', () {
    const group = GroupDefaults(
      outboundTime: DayTime(7, 30),
      returnTime: DayTime(16, 30),
    );
    PlannedDay twoCars() => dayWith(
      cars: const [
        PlannedCar(driverId: anna, fullIds: [bernd]),
        PlannedCar(driverId: clara),
      ],
    );

    List<OutboxEntry> box({required bool on, bool withDeviation = true}) =>
        outboxEntries(
          week: [twoCars()],
          persons: persons,
          now: mondayEvening,
          defaults: group,
          dayDefaults: withDeviation
              ? {tuesday: const GroupDefaults(meetingPoint: 'Netto')}
              : const {},
          carDefaults: withDeviation
              ? {
                  tuesday: {
                    clara: const GroupDefaults(outboundTime: DayTime(6, 45)),
                  },
                }
              : const {},
          carAssignment: on,
        );

    test('aus: im Push stehen nur die Zeiten der Gruppe', () {
      final off = box(on: false);
      for (final id in [anna, bernd, clara]) {
        expect(
          entryFor(off, id).outboundTime,
          const DayTime(7, 30),
          reason:
              'Ohne Auto-Zuordnung gibt es keine Abfahrt je Auto — auch nicht '
              'für Clara, die eine abgelegt hat. Genau das verspricht der '
              'Screen.',
        );
      }
      expect(
        entryFor(box(on: true), clara).outboundTime,
        const DayTime(6, 45),
        reason:
            'Sonst misst der Test nichts: Eingeschaltet MUSS Claras Zeile die '
            'abweichende Zeit tragen.',
      );
    });

    test('aus: der Digest ist derselbe wie ganz ohne Abweichung', () {
      final off = box(on: false);
      final clean = box(on: false, withDeviation: false);
      for (final id in [anna, bernd, clara]) {
        expect(
          entryFor(off, id).digest,
          entryFor(clean, id).digest,
          reason:
              'Eine liegengebliebene Abweichung darf im ausgeschalteten '
              'Zustand nichts anhängen — sonst meldete das Feature weiter '
              '„Änderung" über eine Zeit, die niemand mehr angezeigt bekommt.',
        );
      }
      expect(
        entryFor(box(on: true), clara).digest,
        isNot(entryFor(clean, clara).digest),
        reason: 'Gegenprobe: eingeschaltet zählt sie sehr wohl.',
      );
    });

    test('beide Korb-Schreiber reichen den Schalter durch', () {
      // Am Quelltext geprüft, nicht am Verhalten — dieselbe Bauart wie
      // `test/read_retry_test.dart`. Die Vorgabe von `carAssignment` ist der
      // bisherige Zustand (an), damit ein vergessener Aufrufer nichts still
      // abschaltet; genau deshalb würde ein Vergessen sonst NICHT auffallen.
      // Beide füllen denselben Korb: Läse einer den Schalter nicht, trüge er
      // andere Zeiten ein als der andere.
      for (final path in ['lib/data/providers.dart', 'tool/notify.dart']) {
        final source = File(path).readAsStringSync();
        final call = source.substring(source.indexOf('outboxEntries('));
        expect(
          call.substring(0, call.indexOf(');')),
          contains('carAssignment:'),
          reason: '$path ruft outboxEntries ohne den Gruppen-Schalter auf.',
        );
      }
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

/// push_e2e_test.dart – Push-Registrierung gegen einen ECHTEN Stack (#101).
///
/// Alles hier Geprüfte bildet das In-Memory-Backend nur nach: die RLS auf
/// `push_devices` und `notification_prefs`, die Policy-freie `push_log` und
/// vor allem `register_push_device`. Genau diese Funktion existiert, weil ein
/// Gerät die Gruppe wechseln kann — und der Fehler dabei (Unique-Verletzung
/// auf einer Zeile, die die RLS gar nicht zeigt) ist im Fake per Konstruktion
/// unsichtbar.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e_env.dart';

void main() {
  late SupabaseClient service;

  setUpAll(() {
    if (!e2eConfigured) return;
    service = newServiceClient();
  });

  tearDownAll(() async {
    if (!e2eConfigured) return;
    await disposeClients();
  });

  /// Eine aktive Gruppe mit einer Person.
  Future<(GroupAccount, String)> groupWithPerson(String label) async {
    final group = await registerGroup(label);
    final person = await group.client
        .from('persons')
        .insert({'name': 'E2E $label'})
        .select('id')
        .single();
    return (group, person['id'] as String);
  }

  test(
    'die Registrierung ordnet das Gerät einer eigenen Person zu',
    () async {
      final (group, personId) = await groupWithPerson('pusha');
      final token = uniqueName('token');

      await group.client.rpc<void>(
        'register_push_device',
        params: {
          'device_token': token,
          'person': personId,
          'device_platform': 'android',
        },
      );

      final row = await group.client
          .from('push_devices')
          .select('person_id, group_id, platform')
          .eq('token', token)
          .single();
      expect(row['person_id'], personId);
      expect(row['group_id'], group.id);
      expect(row['platform'], 'android');
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'eine fremde Person lässt sich nicht zuordnen',
    () async {
      final (mine, _) = await groupWithPerson('pushb');
      final (_, foreignPerson) = await groupWithPerson('pushc');

      await expectLater(
        mine.client.rpc<void>(
          'register_push_device',
          params: {
            'device_token': uniqueName('token'),
            'person': foreignPerson,
            'device_platform': 'android',
          },
        ),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('unknown person'),
          ),
        ),
        reason:
            'Sonst hinge eine Zustellung an einer fremden person_id — und die '
            'Gruppe bekäme Nachrichten über jemanden, den sie nie sehen darf.',
      );
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'ein Gerät gehört immer nur einer Gruppe',
    () async {
      final (first, firstPerson) = await groupWithPerson('pushd');
      final (second, secondPerson) = await groupWithPerson('pushe');
      final token = uniqueName('token');

      await first.client.rpc<void>(
        'register_push_device',
        params: {
          'device_token': token,
          'person': firstPerson,
          'device_platform': 'android',
        },
      );
      // Dasselbe Gerät meldet sich in einer anderen Gruppe an. Ohne das
      // delete-then-insert in der Funktion liefe das hier in eine
      // Unique-Verletzung auf einer Zeile, die die RLS der zweiten Gruppe
      // nicht einmal zeigt.
      await second.client.rpc<void>(
        'register_push_device',
        params: {
          'device_token': token,
          'person': secondPerson,
          'device_platform': 'android',
        },
      );

      expect(
        await first.client
            .from('push_devices')
            .select('token')
            .eq('token', token),
        isEmpty,
        reason:
            'Die alte Zeile muss weg sein — sonst bekäme die erste Gruppe '
            'weiter Nachrichten auf ein Gerät, das ihr nicht mehr gehört.',
      );
      final row = await second.client
          .from('push_devices')
          .select('person_id')
          .eq('token', token)
          .single();
      expect(row['person_id'], secondPerson);
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'eine fremde Gruppe sieht weder Geräte noch Einstellungen',
    () async {
      final (mine, personId) = await groupWithPerson('pushf');
      final (other, _) = await groupWithPerson('pushg');
      final token = uniqueName('token');

      await mine.client.rpc<void>(
        'register_push_device',
        params: {
          'device_token': token,
          'person': personId,
          'device_platform': 'android',
        },
      );
      await mine.client.from('notification_prefs').upsert({
        'group_id': mine.id,
        'person_id': personId,
        'evening_enabled': true,
        'evening_time': '21:00',
        'departure_time': '07:30',
        'changes_enabled': true,
      }, onConflict: 'group_id,person_id');

      expect(await other.client.from('push_devices').select('token'), isEmpty);
      expect(
        await other.client.from('notification_prefs').select('person_id'),
        isEmpty,
      );
      // Und die eigene Gruppe sieht ihre Zeile sehr wohl.
      expect(
        await mine.client.from('notification_prefs').select(),
        hasLength(1),
      );
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'das Konfliktziel der Einstellungen passt zum Schlüssel',
    () async {
      final (group, personId) = await groupWithPerson('pushh');
      Future<void> save(String time) =>
          group.client.from('notification_prefs').upsert({
            'group_id': group.id,
            'person_id': personId,
            'evening_enabled': true,
            'evening_time': time,
            'departure_time': '07:30',
            'changes_enabled': true,
          }, onConflict: 'group_id,person_id');

      await save('21:00');
      // Zweites Speichern muss die Zeile ersetzen, nicht danebenlegen. Passt
      // das Konfliktziel nicht zum Primärschlüssel, meldet Postgres hier „no
      // unique or exclusion constraint matching the ON CONFLICT specification".
      await save('22:15');

      final rows = await group.client
          .from('notification_prefs')
          .select('evening_time');
      expect(rows, hasLength(1));
      expect(rows.single['evening_time'], startsWith('22:15'));
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'das Versand-Gedächtnis ist für Clients unerreichbar',
    () async {
      final (group, personId) = await groupWithPerson('pushi');
      await service.from('push_log').insert({
        'group_id': group.id,
        'person_id': personId,
        'plan_date': '2026-07-28',
        'kind': 'evening',
        'digest': 'abc',
      });

      expect(
        await group.client.from('push_log').select('digest'),
        isEmpty,
        reason:
            'push_log hat bewusst keine Policy. Könnte ein Mitglied es lesen '
            'oder schreiben, ließen sich Nachrichten unterdrücken (Zeile '
            'anlegen) oder erneut auslösen (Zeile löschen).',
      );
      await expectLater(
        group.client.from('push_log').insert({
          'group_id': group.id,
          'person_id': personId,
          'plan_date': '2026-07-29',
          'kind': 'evening',
          'digest': 'x',
        }),
        throwsA(isA<PostgrestException>()),
      );
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  test(
    'eine nicht freigegebene Gruppe registriert gar nichts',
    () async {
      // Zurück auf pending: `my_group_active()` ist dann false.
      final pending = await registerGroup('pushj');
      await makePending(newServiceClient(), pending.id);
      await expectLater(
        pending.client.rpc<void>(
          'register_push_device',
          params: {
            'device_token': uniqueName('token'),
            'person': null,
            'device_platform': 'android',
          },
        ),
        throwsA(
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            contains('not allowed'),
          ),
        ),
      );
    },
    skip: e2eConfigured ? false : e2eSkipReason,
  );

  // Der Ausgangskorb (#132). Hier hängt mehr am echten Postgres als sonst:
  // Der Weg „Tabellenrechte plus Policies" wurde ausprobiert und scheitert
  // — Postgres verlangt für `on conflict do update` das SELECT-Recht, und
  // mit Recht, aber ohne SELECT-Policy scheitert der Upsert an „new row
  // violates row-level security policy". Das kann kein Fake zeigen.
  group('Ausgangskorb', () {
    Future<Map<String, dynamic>?> row(String groupId) async => service
        .from('push_outbox')
        .select()
        .eq('group_id', groupId)
        .maybeSingle();

    Future<void> publish(
      GroupAccount group,
      String personId,
      String digest, {
      bool legs = false,
    }) => group.client.rpc<void>(
      'publish_push_outbox',
      params: {
        'entries': [
          {
            'person_id': personId,
            'plan_date': '2026-07-30',
            'digest': digest,
            'body': 'Anna fährt · dabei: Bert',
            'title_evening': 'Morgen (Do, 30.07.)',
            'title_change': 'Änderung · Morgen (Do, 30.07.)',
            if (legs) 'title_out': 'Abfahrt 07:30 Uhr',
            if (legs) 'title_return': 'Rückfahrt 16:30 Uhr',
          },
        ],
        'keep_from': '2026-07-27',
      },
    );

    test('schreiben geht, lesen nicht', () async {
      final (group, personId) = await groupWithPerson('outa');
      await publish(group, personId, 'd1');

      expect(
        (await row(group.id))?['body'],
        'Anna fährt · dabei: Bert',
        reason: 'Mit dem service_role-Key ist die Zeile da.',
      );
      await expectLater(
        group.client.from('push_outbox').select(),
        throwsA(isA<PostgrestException>()),
        reason:
            'Im Korb steht der vorgeschlagene Fahrer im Klartext. Könnte '
            'der Client ihn lesen, stünde neben fairness.dart eine zweite '
            'Wahrheit darüber, wer fährt — genau das verhindert die '
            'fehlende Policy samt zurückgenommenem Grant.',
      );
    }, skip: e2eConfigured ? false : e2eSkipReason);

    test(
      'gleicher Inhalt verschiebt die Fälligkeit nicht',
      () async {
        final (group, personId) = await groupWithPerson('outb');
        await publish(group, personId, 'd1');
        final first = (await row(group.id))?['due_at'] as String?;
        expect(first, isNotNull, reason: 'Neu angelegt heißt fällig.');

        await publish(group, personId, 'd1');
        expect(
          (await row(group.id))?['due_at'],
          first,
          reason:
              'So schreibt der stündliche Reparatur-Job: immer wieder '
              'dasselbe. Schöbe das die Fälligkeit jedes Mal nach hinten, '
              'würde NIE etwas gesendet — und im Log stünde kein Fehler.',
        );

        await publish(group, personId, 'd2');
        expect(
          DateTime.parse(
            (await row(group.id))!['due_at'] as String,
          ).isAfter(DateTime.parse(first!)),
          isTrue,
          reason:
              'Geänderter Inhalt entprellt: Wer weiterklickt, schiebt die '
              'Meldung weiter — fünf Taps ergeben eine Nachricht, nicht fünf.',
        );
      },
      skip: e2eConfigured ? false : e2eSkipReason,
    );

    // Die Auswahl beim Versand (#132, Teil 2). Sie bildet `dueMessages` in
    // SQL nach — Zeitfenster, Digest-Vergleich, Entprell-Riegel. Genau die
    // Zeitrechnung kann kein Fake zeigen: Das Fenster geht über zwei
    // Kalendertage, in Europe/Berlin, während Postgres in UTC läuft.
    group('was fällig ist', () {
      Future<List<String>> kindsAt(String groupId, String at) async {
        final rows = await service.rpc<List<dynamic>>(
          'push_due',
          params: {'at': at},
        );
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            if (row['group_id'] == groupId) row['kind'] as String,
        ];
      }

      /// Gruppe mit Person, Einstellungen (21:00 / 07:30), Gerät und einer
      /// Korb-Zeile für Donnerstag, den 30.07.2026.
      Future<(GroupAccount, String)> ready(String label) async {
        final (group, personId) = await groupWithPerson(label);
        await group.client.from('notification_prefs').upsert({
          'group_id': group.id,
          'person_id': personId,
          'evening_enabled': true,
          'evening_time': '21:00',
          'departure_time': '07:30',
          'changes_enabled': true,
        }, onConflict: 'group_id,person_id');
        await group.client.rpc<void>(
          'register_push_device',
          params: {
            'device_token': uniqueName('token'),
            'person': personId,
            'device_platform': 'android',
          },
        );
        await publish(group, personId, 'd1');
        return (group, personId);
      }

      test(
        'das Fenster geht vom Abend davor bis zur Abfahrt',
        () async {
          final (group, _) = await ready('oute');
          expect(
            await kindsAt(group.id, '2026-07-29 20:00+02'),
            isEmpty,
            reason: 'Vor der eingestellten Abendzeit kommt nichts.',
          );
          expect(
            await kindsAt(group.id, '2026-07-29 21:30+02'),
            ['evening'],
            reason: 'Ab 21:00 am Vortag ist der Abend-Blick fällig.',
          );
          expect(
            await kindsAt(group.id, '2026-07-30 08:00+02'),
            isEmpty,
            reason:
                'Nach der Abfahrt nützt keine Meldung mehr — und ein '
                'nachgeholter Lauf darf niemanden nachts wecken.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'nach dem Abend-Blick zählt nur noch die Änderung',
        () async {
          final (group, personId) = await ready('outf');
          await service.from('push_log').insert({
            'group_id': group.id,
            'person_id': personId,
            'plan_date': '2026-07-30',
            'kind': 'evening',
            'digest': 'd1',
          });

          expect(
            await kindsAt(group.id, '2026-07-29 22:00+02'),
            isEmpty,
            reason: 'Unveränderter Digest heißt: nichts zu melden.',
          );

          await publish(group, personId, 'd2');
          // Die Fälligkeit setzt der Trigger auf „jetzt + 60 s" — und `jetzt`
          // ist die echte Uhr, nicht die des Tests. Für den Riegel wird sie
          // deshalb ausdrücklich gesetzt: einmal hinter, einmal vor dem
          // Zeitpunkt der Abfrage. Dass der Trigger überhaupt schiebt, prüft
          // „gleicher Inhalt verschiebt die Fälligkeit nicht" weiter oben.
          await service
              .from('push_outbox')
              .update({'due_at': '2026-07-29 22:00:30+02'})
              .eq('group_id', group.id);
          expect(
            await kindsAt(group.id, '2026-07-29 22:00+02'),
            isEmpty,
            reason:
                'Das Entprellen aus Teil 1 greift auch hier: Wer im Planer '
                'weiterklickt, schiebt die Meldung vor sich her. Ohne diesen '
                'Riegel ginge die erste Zwischenversion raus und der '
                'Endzustand wäre danach 30 Minuten gesperrt.',
          );
          await service
              .from('push_outbox')
              .update({'due_at': '2026-07-29 21:59+02'})
              .eq('group_id', group.id);
          expect(
            await kindsAt(group.id, '2026-07-29 22:00+02'),
            ['change'],
            reason: 'Ist die Frist um, geht die Änderung raus.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      // Die Abfahrts-Erinnerung (#164). Sie ist der eigentliche Grund, warum
      // `push_due()` seit v0.58.0 zwei Fenster hat — die Rückfahrt liegt per
      // Konstruktion AUSSERHALB des Plan-Fensters (das endet um 07:30). In
      // einem gemeinsamen Fenster wäre sie nie fällig geworden, und das sieht
      // man nur an einer echten Uhr in Europe/Berlin.
      group('Abfahrts-Erinnerung', () {
        /// Wie [ready], zusätzlich mit Gruppenzeiten, Kopfzeilen und Opt-in.
        Future<(GroupAccount, String)> reminding(
          String label, {
          int lead = 15,
        }) async {
          final (group, personId) = await ready(label);
          await publish(group, personId, 'd1', legs: true);
          await group.client.from('group_defaults').upsert({
            'group_id': group.id,
            'outbound_time': '07:30',
            'return_time': '16:30',
          }, onConflict: 'group_id');
          await group.client
              .from('notification_prefs')
              .update({
                'reminders_enabled': true,
                'reminder_lead_minutes': lead,
              })
              .eq('person_id', personId);
          return (group, personId);
        }

        test(
          'die Hinfahrt weckt im Vorlauf, die Rückfahrt nach dem Plan-Fenster',
          () async {
            final (group, _) = await reminding('outg');

            expect(
              (await kindsAt(group.id, '2026-07-30 07:10+02')).toSet(),
              isNot(contains('departure_out')),
              reason: '20 Minuten vorher ist der Vorlauf noch nicht erreicht.',
            );
            expect(
              // Als Menge geprüft: Der Abend-Blick ist um 07:20 parallel
              // offen (Fenster bis 07:30) und gehört nicht zur Frage.
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              contains('departure_out'),
            );
            expect(
              await kindsAt(group.id, '2026-07-30 16:20+02'),
              ['departure_return'],
              reason:
                  'Halb fünf liegt weit hinter der persönlichen '
                  'departure_time (07:30). Läge die Erinnerung im '
                  'Plan-Fenster, käme hier nichts — und niemand sähe warum.',
            );
            expect(
              await kindsAt(group.id, '2026-07-30 16:30+02'),
              isEmpty,
              reason: 'Um 16:30 fährt das Auto.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );

        // #183. Im Fake und im Dart-Spiegel ist das nicht zu beweisen: Ob die
        // Zeile die Gruppenzeit schlägt, entscheidet das `coalesce` im
        // `values`-Paar von `push_due()` — SQL, das nur echtes Postgres
        // ausführt.
        test(
          'die Zeit der Zeile schlägt die Vorgabe der Gruppe',
          () async {
            final (group, personId) = await reminding('outk');
            // Derselbe Tag, aber eine Dreiviertelstunde früher los. Der
            // Client rechnet die wirksame Zeit und legt sie mit ab; die
            // Gruppenzeit (07:30) bleibt unverändert daneben stehen.
            await group.client.rpc<void>(
              'publish_push_outbox',
              params: {
                'entries': [
                  {
                    'person_id': personId,
                    'plan_date': '2026-07-30',
                    'digest': 'd2',
                    'body': 'Anna fährt · dabei: Bert',
                    'title_evening': 'Morgen (Do, 30.07.)',
                    'title_change': 'Änderung · Morgen (Do, 30.07.)',
                    'title_out': 'Abfahrt 06:45 Uhr',
                    'title_return': 'Rückfahrt 16:30 Uhr',
                    'outbound_time': '06:45',
                  },
                ],
                'keep_from': '2026-07-27',
              },
            );

            expect(
              (await kindsAt(group.id, '2026-07-30 06:35+02')).toSet(),
              contains('departure_out'),
              reason:
                  'Fünfzehn Minuten vor der Zeit des TAGES. Zöge push_due() '
                  'die Gruppenzeit, käme hier nichts — und die Erinnerung '
                  'erst, wenn das Auto längst weg ist.',
            );
            expect(
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              isNot(contains('departure_out')),
              reason:
                  'Und zur alten Zeit gar nicht mehr: Sie gilt an diesem Tag '
                  'nicht. Ohne diese Hälfte wäre die Prüfung oben auch mit '
                  'zwei Erinnerungen zufrieden.',
            );
            expect(
              await kindsAt(group.id, '2026-07-30 16:20+02'),
              ['departure_return'],
              reason:
                  'Die Rückfahrt hat der Tag nicht angefasst — sie bleibt bei '
                  'der Vorgabe der Gruppe. Feldweise aufgelöst, nicht '
                  'objektweise: Sonst nähme eine verschobene Hinfahrt der '
                  'Rückfahrt ihre Zeit.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );

        test(
          'sie kommt genau einmal je Richtung',
          () async {
            final (group, personId) = await reminding('outh');
            await service.from('push_log').insert({
              'group_id': group.id,
              'person_id': personId,
              'plan_date': '2026-07-30',
              'kind': 'departure_out',
              'digest': 'd1',
            });

            expect(
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              isNot(contains('departure_out')),
              reason:
                  'Zeitgetrieben heißt: einmal. Ohne den Riegel feuerte sie '
                  'in jedem Minutentakt des Fensters neu — bei 15 Minuten '
                  'Vorlauf fünfzehnmal. Und der CHECK auf push_log.kind muss '
                  'die Art kennen: Täte er es nicht, schlüge schon dieses '
                  'insert fehl, und im Betrieb sähe es aus wie „nie gesendet".',
            );
            expect(
              await kindsAt(group.id, '2026-07-30 16:20+02'),
              ['departure_return'],
              reason: 'Die andere Richtung hat ihren eigenen Riegel.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );

        test(
          'ohne Opt-in und ohne Gruppenzeit kommt nichts',
          () async {
            final (group, personId) = await reminding('outi');
            await group.client
                .from('notification_prefs')
                .update({'reminders_enabled': false})
                .eq('person_id', personId);
            expect(
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              isNot(contains('departure_out')),
            );

            await group.client
                .from('notification_prefs')
                .update({'reminders_enabled': true})
                .eq('person_id', personId);
            await group.client
                .from('group_defaults')
                .update({'outbound_time': null})
                .eq('group_id', group.id);
            expect(
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              isNot(contains('departure_out')),
              reason: 'Ohne Gruppenzeit gibt es kein Fenster.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );

        test(
          'am eingetragenen Tag kommt sie, der Abend-Blick nicht',
          () async {
            final (group, personId) = await reminding('outj');
            // `fix` = confirmedDigest: Die Fahrt ist eingetragen.
            await publish(group, personId, 'fix', legs: true);

            final kinds = (await kindsAt(
              group.id,
              '2026-07-30 07:20+02',
            )).toSet();
            expect(
              kinds,
              contains('departure_out'),
              reason:
                  'An einem eingetragenen Tag fährt die Gruppe gerade — das '
                  'ist der Moment, für den die Erinnerung gebaut wurde.',
            );
            expect(
              kinds,
              isNot(contains('evening')),
              reason:
                  'Ein eingetragener Tag ist geplant fertig. Ohne den '
                  'fix-Riegel käme noch ein Abend-Blick auf einen Tag, der '
                  'schon läuft.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );

        test(
          'ein Alt-Client leert die Kopfzeile nicht aus',
          () async {
            final (group, personId) = await reminding('outk');
            // Genau der Aufruf eines Clients von vor v0.58.0: ohne die neuen
            // Felder, mit geändertem Inhalt.
            await publish(group, personId, 'd2');

            expect(
              (await kindsAt(group.id, '2026-07-30 07:20+02')).toSet(),
              contains('departure_out'),
              reason:
                  'Ohne coalesce im Upsert setzte jeder Schreibvorgang eines '
                  'Alt-Clients die Kopfzeile auf NULL — und ohne Kopfzeile '
                  'fällt die Erinnerung aus, bis der stündliche Job sie '
                  'wiederherstellt.',
            );
          },
          skip: e2eConfigured ? false : e2eSkipReason,
        );
      });
    });

    // Sofort-Meldungen (#163). Drei Dinge sind hier und NUR hier zu sehen:
    // dass der Trigger beim ersten Füllen schweigt, dass Plan- und
    // Fahrt-Zeile zum selben Tag nebeneinander bestehen (der vierspaltige
    // Schlüssel), und dass der Wochen-Purge die Fahrt-Meldung stehen lässt.
    group('Sofort-Meldungen', () {
      Future<List<String>> kindsAt(String groupId, String at) async {
        final rows = await service.rpc<List<dynamic>>(
          'push_due',
          params: {'at': at},
        );
        return [
          for (final row in rows.cast<Map<String, dynamic>>())
            if (row['group_id'] == groupId) row['kind'] as String,
        ];
      }

      /// Gruppe mit Person, Einstellungen, Gerät — aber noch OHNE Korb.
      Future<(GroupAccount, String)> ready(String label) async {
        final (group, personId) = await groupWithPerson(label);
        await group.client.from('notification_prefs').upsert({
          'group_id': group.id,
          'person_id': personId,
          'evening_time': '21:00',
          'departure_time': '07:30',
        }, onConflict: 'group_id,person_id');
        await group.client.rpc<void>(
          'register_push_device',
          params: {
            'device_token': uniqueName('token'),
            'person': personId,
            'device_platform': 'android',
          },
        );
        return (group, personId);
      }

      Future<void> publishPlan(
        GroupAccount group,
        String personId,
        String digest, {
        bool suppress = false,
      }) => group.client.rpc<void>(
        'publish_push_outbox',
        params: {
          'entries': [
            {
              'person_id': personId,
              'plan_date': '2026-07-30',
              'kind': 'plan',
              'digest': digest,
              'body': 'Anna fährt · dabei: Bert',
              'title_evening': 'Morgen (Do, 30.07.)',
              'title_change': 'Ausgetragen · Morgen (Do, 30.07.)',
              'title_roster': 'Eingetragen · Morgen (Do, 30.07.)',
              'suppress_roster': suppress,
            },
          ],
          'keep_from': '2026-07-27',
        },
      );

      test(
        'die erste Korb-Füllung weckt niemanden',
        () async {
          final (group, personId) = await ready('insta');
          await publishPlan(group, personId, 'd1');

          final row = await service
              .from('push_outbox')
              .select('roster_due_at')
              .eq('group_id', group.id)
              .single();
          expect(
            row['roster_due_at'],
            isNull,
            reason:
                'Beim ersten Füllen entstehen Zeilen für JEDE Person — eine '
                'neue Gruppe, ein Wochenwechsel, ein Gerät, das den Korb '
                'erstmals schreibt. Ohne den tg_op-Riegel weckte das die '
                'halbe Gruppe mit „Eingetragen" für Tage, an denen sich '
                'nichts geändert hat.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'ein Eintrag durch andere meldet sich sofort, auch mittags',
        () async {
          final (group, personId) = await ready('instb');
          // Erst raus, dann rein: Das ist der Zustandswechsel, um den es geht.
          await publishPlan(group, personId, 'raus');
          await publishPlan(group, personId, 'd1');

          await service
              .from('push_outbox')
              .update({'roster_due_at': '2026-07-29 12:00+02'})
              .eq('group_id', group.id);
          expect(
            await kindsAt(group.id, '2026-07-29 12:01+02'),
            ['roster'],
            reason:
                'Mittags ist kein Abend-Fenster offen — genau deshalb hat '
                'die Meldung ihre eigene Fälligkeit. Hinge sie am '
                'Abend-Blick, käme sie erst um 21 Uhr.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'die eigene Schreibung bleibt still',
        () async {
          final (group, personId) = await ready('instc');
          await publishPlan(group, personId, 'raus');
          await publishPlan(group, personId, 'd1', suppress: true);

          final row = await service
              .from('push_outbox')
              .select('roster_due_at')
              .eq('group_id', group.id)
              .single();
          expect(
            row['roster_due_at'],
            isNull,
            reason:
                'Wer selbst tippt, braucht keine Meldung darüber. Best '
                'effort: Der stündliche Job schreibt `false` und hebt es '
                'wieder auf.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'hin und her ergibt eine Meldung je Zustand',
        () async {
          final (group, personId) = await ready('instd');
          await publishPlan(group, personId, 'raus');
          await publishPlan(group, personId, 'd1');
          await service
              .from('push_outbox')
              .update({'roster_due_at': '2026-07-29 12:00+02'})
              .eq('group_id', group.id);
          expect(await kindsAt(group.id, '2026-07-29 12:01+02'), ['roster']);

          // Verschickt: Protokoll steht, Fälligkeit quittiert.
          await service.from('push_log').insert({
            'group_id': group.id,
            'person_id': personId,
            'plan_date': '2026-07-30',
            'kind': 'roster',
            'digest': 'd1',
          });
          await service
              .from('push_outbox')
              .update({'roster_due_at': null})
              .eq('group_id', group.id);
          expect(await kindsAt(group.id, '2026-07-29 12:02+02'), isEmpty);

          // Wieder ausgetragen — ein neuer Zustand, also eine neue Meldung.
          await publishPlan(group, personId, 'raus');
          await service
              .from('push_outbox')
              .update({'roster_due_at': '2026-07-29 12:03+02'})
              .eq('group_id', group.id);
          expect(
            await kindsAt(group.id, '2026-07-29 12:04+02'),
            ['roster'],
            reason:
                'Jede Wendung einmal — aber nicht jede Schreibrunde. Der '
                'Vergleich mit dem letzten Protokolleintrag macht den '
                'Unterschied.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'Plan- und Fahrt-Zeile stehen nebeneinander (Schlüssel-Beweis)',
        () async {
          final (group, personId) = await ready('inste');
          await publishPlan(group, personId, 'd1');
          await group.client.rpc<void>(
            'publish_push_outbox',
            params: {
              'entries': [
                {
                  'person_id': personId,
                  'plan_date': '2026-07-30',
                  'kind': 'trip',
                  'digest': 'tripdigest',
                  'body': 'Die Fahrt an diesem Tag wurde gelöscht.',
                  'title_evening': 'Fahrt entfernt · Do, 30.07.',
                  'title_change': 'Fahrt entfernt · Do, 30.07.',
                },
              ],
              'keep_from': '2026-07-27',
            },
          );

          final rows = await service
              .from('push_outbox')
              .select('kind, body')
              .eq('group_id', group.id);
          expect(
            rows.map((r) => r['kind']).toSet(),
            {'plan', 'trip'},
            reason:
                'Ohne `kind` im Primärschlüssel überschriebe die eine Zeile '
                'die andere — je nach Reihenfolge verschwände mal die '
                'Planung, mal die Fahrtänderung.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'eine Fahrt-Meldung feuert ohne Fenster, auch für alte Tage',
        () async {
          final (group, personId) = await ready('instf');
          await group.client.rpc<void>(
            'publish_push_outbox',
            params: {
              'entries': [
                {
                  'person_id': personId,
                  // Zwei Wochen alt: außerhalb jedes Plan-Fensters.
                  'plan_date': '2026-07-15',
                  'kind': 'trip',
                  'digest': 'tripdigest',
                  'body': 'Die Fahrt an diesem Tag wurde gelöscht.',
                  'title_evening': 'Fahrt entfernt · Mi, 15.07.',
                  'title_change': 'Fahrt entfernt · Mi, 15.07.',
                },
              ],
              'keep_from': '2026-07-27',
            },
          );

          // **Der eigentliche Beweis:** Ein ZWEITER Schreibvorgang. Der
          // Purge läuft am Anfang der Funktion, im selben Aufruf sieht er
          // die Zeile also gar nicht — gefährlich wird erst der nächste
          // Plan-Schreib, und den macht der Client bei jeder Planänderung.
          await publishPlan(group, personId, 'd1');
          expect(
            await service
                .from('push_outbox')
                .select('kind')
                .eq('group_id', group.id)
                .eq('kind', 'trip'),
            hasLength(1),
            reason:
                'Die Fahrt liegt zwei Wochen zurück, `plan_date` also vor '
                '`keep_from`. Ohne den kind-Filter nähme der nächste '
                'Plan-Schreib sie mit — die Meldung stürbe, bevor sie eine '
                'Minute später verschickt würde, und im Log stünde nichts.',
          );

          await service
              .from('push_outbox')
              .update({'due_at': '2026-07-29 12:00+02'})
              .eq('group_id', group.id)
              .eq('kind', 'trip');
          expect(
            await kindsAt(group.id, '2026-07-29 12:01+02'),
            ['trip'],
            reason:
                'Kein Fenster, kein Digest-Vergleich: Die Zeile entsteht '
                'nur, wenn wirklich jemand eine Fahrt geändert hat.',
          );
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );

      test(
        'ohne Sofort-Meldungen kommt weder Roster noch Trip',
        () async {
          final (group, personId) = await ready('instg');
          await group.client
              .from('notification_prefs')
              .update({'instant_enabled': false})
              .eq('person_id', personId);
          await publishPlan(group, personId, 'raus');
          await publishPlan(group, personId, 'd1');
          await service
              .from('push_outbox')
              .update({'roster_due_at': '2026-07-29 12:00+02'})
              .eq('group_id', group.id);

          expect(await kindsAt(group.id, '2026-07-29 12:01+02'), isEmpty);
        },
        skip: e2eConfigured ? false : e2eSkipReason,
      );
    });

    test(
      'eine fremde Person landet nicht im eigenen Korb',
      () async {
        final (mine, _) = await groupWithPerson('outc');
        final (_, foreignPerson) = await groupWithPerson('outd');
        await publish(mine, foreignPerson, 'd1');
        expect(
          await row(mine.id),
          isNull,
          reason:
              'Der Fremdschlüssel auf persons prüft nur, dass es die Person '
              'GIBT, nicht wem sie gehört. Ohne den Join auf group_id hinge '
              'eine Zeile an einer gruppenfremden person_id.',
        );
      },
      skip: e2eConfigured ? false : e2eSkipReason,
    );
  });
}

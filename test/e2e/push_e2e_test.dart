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

    Future<void> publish(GroupAccount group, String personId, String digest) =>
        group.client.rpc<void>(
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

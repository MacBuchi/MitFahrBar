/// E2E: Mandantentrennung gegen ECHTES Postgres mit echter RLS.
///
/// test/fakes/ bildet die Trennung nur nach — hier wird sie bewiesen:
/// Signup-Trigger, pending-Sperre, Gruppen-Isolation, Nur-Lese-app_config
/// und die group_id-Schlüssel des Wochenplaners (v0.15.0-Fix).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e_env.dart';

void main() {
  if (!e2eConfigured) {
    test('RLS-E2E', () {}, skip: e2eSkipReason);
    return;
  }

  late SupabaseClient service;
  late GroupAccount a;
  late GroupAccount b;
  late Map<String, dynamic> personA;

  setUpAll(() async {
    service = newServiceClient();
    a = await registerGroup('rlsa');
    b = await registerGroup('rlsb');
    personA = await a.client
        .from('persons')
        .insert({'name': 'Anna E2E'})
        .select()
        .single();
    await b.client.from('persons').insert({'name': 'Ben E2E'});
  });

  tearDownAll(disposeClients);

  test('Signup-Trigger: Gruppe mit Default-Settings', () async {
    final c = await registerGroup('rlsc');

    final group = await c.client.from('groups').select().single();
    expect(group['handle'], c.handle);
    expect(
      group['status'],
      'active',
      reason:
          'Der Trigger legt sie als pending an, die Function schaltet sie im '
          'selben Zug frei — beides gehört zur Anlage.',
    );

    // Settings entstehen im Trigger — inklusive points_weight = 1.0
    // (Punkte-only-Ranking, Issue #38).
    final settings = await service
        .from('settings')
        .select()
        .eq('group_id', c.id);
    expect(settings, hasLength(6));
    final weight = settings.singleWhere(
      (s) => s['key'] == 'points_weight',
    )['value'];
    expect(weight, 1.0);
  });

  test('pending-Gruppe darf nichts lesen und nichts schreiben', () async {
    // Der Zustand entsteht nicht mehr über die App, sondern nur noch durch
    // einen Fremd-Signup gegen die Gruppen-Domain — der ist client-seitig
    // nicht abstellbar, solange die Verwalter-Registrierung offen ist. Genau
    // deshalb bleibt `status` der Riegel: Eine solche Zeile ist inert.
    final c = await registerGroup('rlsp');
    await makePending(service, c.id);
    // Eigene Settings existieren (Trigger), sind aber unsichtbar,
    // solange die Gruppe nicht aktiv ist.
    final settings = await c.client.from('settings').select();
    expect(settings, isEmpty);
    await expectLater(
      c.client.from('persons').insert({'name': 'Zu früh'}),
      throwsA(isA<PostgrestException>()),
    );
  });

  // Issue #108: `groups` hat keine Update-Policy mehr. Das ist der Grund,
  // warum die Sonderrolle einer Admin-Gruppe wegfallen KONNTE — vorher
  // brauchte die Freigabe eine Policy, die fremde Zeilen schreiben darf.
  test('eine pending-Gruppe kann sich nicht selbst freischalten', () async {
    final c = await registerGroup('rlsu');
    await makePending(service, c.id);

    // Ihre eigene Zeile darf sie sehen (das Gate im Client liest den Status),
    // aber nicht anfassen.
    final own = await c.client.from('groups').select().eq('id', c.id);
    expect(own, hasLength(1));

    final updated = await c.client
        .from('groups')
        .update({'status': 'active'})
        .eq('id', c.id)
        .select();
    expect(
      updated,
      isEmpty,
      reason:
          'Ohne Update-Policy trifft das Update keine Zeile. Griffe es, wäre '
          'jeder Fremd-Signup gegen die Gruppen-Domain eine Gruppe, die sich '
          'selbst freischaltet — und die Statuswerte wären als Riegel wertlos, '
          'auch der künftige "archived".',
    );

    final after = await service
        .from('groups')
        .select('status')
        .eq('id', c.id)
        .single();
    expect(after['status'], 'pending');
  });

  test('aktive Gruppe sieht ausschließlich die eigenen Zeilen', () async {
    final personsA = await a.client.from('persons').select();
    expect(personsA, hasLength(1));
    expect(personsA.single['name'], 'Anna E2E');

    final personsB = await b.client.from('persons').select();
    expect(personsB, hasLength(1));
    expect(personsB.single['name'], 'Ben E2E');
  });

  test('fremde Zeilen: unsichtbar, unveränderbar, unlöschbar', () async {
    final updated = await b.client
        .from('persons')
        .update({'name': 'Gekapert'})
        .eq('id', personA['id'] as String)
        .select();
    expect(updated, isEmpty);

    final deleted = await b.client
        .from('persons')
        .delete()
        .eq('id', personA['id'] as String)
        .select();
    expect(deleted, isEmpty);

    final still = await a.client.from('persons').select().single();
    expect(still['name'], 'Anna E2E');
  });

  test('Insert mit fremder group_id scheitert an WITH CHECK', () async {
    await expectLater(
      b.client.from('persons').insert({'name': 'Kuckuck', 'group_id': a.id}),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('anon: keine Gruppendaten, aber app_config lesbar', () async {
    final anon = newAnonClient();
    final persons = await anon.from('persons').select();
    expect(persons, isEmpty);

    // Der Sperr-Schirm braucht die Mindestversion VOR dem Login.
    final config = await anon
        .from('app_config')
        .select()
        .eq('key', 'min_supported_version');
    expect(config, hasLength(1));
  });

  test('app_config ist auch für angemeldete Gruppen nur lesbar', () async {
    await expectLater(
      a.client.from('app_config').insert({'key': 'e2e', 'value': 'x'}),
      throwsA(isA<PostgrestException>()),
    );

    final updated = await a.client
        .from('app_config')
        .update({'value': '99.0.0'})
        .eq('key', 'min_supported_version')
        .select();
    expect(
      updated,
      isEmpty,
      reason:
          'Update darf keine Zeile treffen — '
          'sonst könnte ein Client alle aussperren (Issue #19)',
    );
  });

  test(
    'Planer-Schlüssel tragen group_id: gleicher Tag, zwei Gruppen',
    () async {
      final personB = await b.client.from('persons').select().single();
      const day = '2026-07-27';

      await a.client.from('plan_availability').insert({
        'plan_date': day,
        'person_id': personA['id'],
      });
      await b.client.from('plan_availability').insert({
        'plan_date': day,
        'person_id': personB['id'],
      });

      await a.client.from('plan_overrides').insert({
        'plan_date': day,
        'driver_id': personA['id'],
      });
      // Vor dem v0.15.0-Fix lief genau dieser zweite Insert in eine
      // Unique-Verletzung auf einer Zeile, die RLS gar nicht zeigt.
      await b.client.from('plan_overrides').insert({
        'plan_date': day,
        'driver_id': personB['id'],
      });

      final overridesA = await a.client.from('plan_overrides').select();
      expect(overridesA, hasLength(1));
    },
  );

  // Issue #62: Seit dem Schlüssel (group_id, plan_date, driver_id) darf
  // ein Tag mehrere Fahrer-Zeilen tragen — vorher wäre dieser zweite
  // Insert an derselben Unique-Verletzung gescheitert wie einst die
  // zweite Gruppe.
  test('ein Tag trägt mehrere Fahrer-Zeilen derselben Gruppe', () async {
    final second = await a.client
        .from('persons')
        .insert({'name': 'Arno E2E'})
        .select()
        .single();
    await a.client.from('plan_overrides').insert({
      'plan_date': '2026-07-27',
      'driver_id': second['id'],
    });

    final rows = await a.client
        .from('plan_overrides')
        .select()
        .eq('plan_date', '2026-07-27');
    expect(rows, hasLength(2));
  });

  // Issue #109: `persons.name` trug bis v0.41.0 einen GLOBALEN `unique
  // (name)` aus der Zeit vor der Mandantentrennung. Die zweite Gruppe konnte
  // damit keine „Anna" anlegen — und erfuhr an der Fehlermeldung, dass der
  // Name woanders existiert. Genau das prüfen die nächsten drei Tests; im
  // Fake-Backend wäre das nur nachgebaut.
  group('persons.name ist je Gruppe eindeutig (#109)', () {
    test('zwei Gruppen dürfen denselben Namen tragen', () async {
      // Gruppe A hat „Anna E2E" schon aus dem setUpAll.
      final mine = await b.client
          .from('persons')
          .insert({'name': 'Anna E2E'})
          .select()
          .single();
      expect(
        mine['name'],
        'Anna E2E',
        reason:
            'Ein gemeinsamer Vorname ist bei zwei realen Fahrgemeinschaften '
            'der Normalfall. Vorher scheiterte das hier mit 23505.',
      );
    });

    test('eine Gruppe nicht zweimal — auch nicht anders geschrieben', () async {
      // Kleingeschrieben und mit Rand-Leerzeichen: Der Index normalisiert
      // über `lower(btrim(name))`, genauso wie core/csv_import.dart Namen
      // Personen zuordnet. Liefen beide auseinander, fände der Import zwei
      // Zeilen und nähme willkürlich die erste.
      await expectLater(
        a.client.from('persons').insert({'name': '  anna e2e '}),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '23505'),
        ),
      );
    });

    test('ein inaktiver Name bleibt belegt', () async {
      await a.client
          .from('persons')
          .update({'active': false})
          .eq('id', personA['id'] as String);
      addTearDown(
        () => a.client
            .from('persons')
            .update({'active': true})
            .eq('id', personA['id'] as String),
      );

      await expectLater(
        a.client.from('persons').insert({'name': 'Anna E2E'}),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '23505'),
        ),
        reason:
            'Kein `where active` im Index, und das ist Absicht: Wer '
            'zurückkommt, wird reaktiviert. Eine zweite Zeile spaltete seine '
            'Punkte-Historie und verschöbe rückwirkend die Quote aller '
            'anderen — dieselbe Begründung, aus der es kein deletePerson gibt.',
      );
    });
  });
}

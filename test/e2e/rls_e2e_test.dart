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
    await activateGroup(service, a.id);
    await activateGroup(service, b.id);
    personA = await a.client
        .from('persons')
        .insert({'name': 'Anna E2E'})
        .select()
        .single();
    await b.client.from('persons').insert({'name': 'Ben E2E'});
  });

  tearDownAll(disposeClients);

  test('Signup-Trigger: pending-Gruppe mit Default-Settings', () async {
    final c = await registerGroup('rlsc');

    final group = await c.client.from('groups').select().single();
    expect(group['handle'], c.handle);
    expect(group['status'], 'pending');

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
    final c = await registerGroup('rlsp');
    // Eigene Settings existieren (Trigger), sind aber unsichtbar,
    // solange die Gruppe nicht freigegeben ist.
    final settings = await c.client.from('settings').select();
    expect(settings, isEmpty);
    await expectLater(
      c.client.from('persons').insert({'name': 'Zu früh'}),
      throwsA(isA<PostgrestException>()),
    );
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
}

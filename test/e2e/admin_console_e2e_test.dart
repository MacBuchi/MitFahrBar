/// E2E: Verwalter-Konsole (Issue #55, #106) gegen den echten Stack.
///
/// Beweist die Annahmen, die test/schema_test.dart nur statisch prüft: kein
/// Geister-Pending beim Admin-Signup, Anlegen nur als bestätigtes
/// Verwalter-Konto (und dann aktiv UND verknüpft), Übernehmen nur mit
/// Gruppen-Login und Einrasten, der Deckel von fünf Gruppen, jede Aktion
/// trifft nur die eigene Gruppe, Löschen reißt die Gruppe über die
/// Auth-Kaskade mit — aber nie das Verwalter-Konto.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e_env.dart';

Future<void> expectRpcError(Future<dynamic> call, String messagePart) async {
  try {
    await call;
    fail('RPC hätte scheitern müssen ("$messagePart")');
  } on PostgrestException catch (e) {
    expect(e.message, contains(messagePart));
  }
}

/// Erwartet einen HTTP-Status von der Edge Function.
Future<void> expectFunctionStatus(
  SupabaseClient client,
  Map<String, dynamic> body,
  int status,
) async {
  try {
    await client.functions.invoke('request-group', body: body);
    fail('Aufruf hätte mit $status scheitern müssen');
  } on FunctionException catch (e) {
    expect(e.status, status);
  }
}

void main() {
  if (!e2eConfigured) {
    test('Konsolen-E2E', () {}, skip: e2eSkipReason);
    return;
  }

  late SupabaseClient service;
  late GroupAccount g;
  late AdminAccount admin;

  setUpAll(() async {
    service = newServiceClient();
    g = await registerGroup('adm');
    // Die Gruppe entsteht verknüpft; für die Übernahme-Tests wird sie zur
    // freien Gruppe gemacht — genau der Zustand nach `admin_release_group`.
    await unlinkGroup(service, g.id);
    // Daten, an denen später die Lösch-Kaskade bewiesen wird.
    final person = await g.client
        .from('persons')
        .insert({'name': 'Kaskaden-Probe'})
        .select()
        .single();
    final trip = await g.client
        .from('trips')
        .insert({'trip_date': '2026-07-01'})
        .select()
        .single();
    await g.client.from('trip_participations').insert({
      'trip_id': trip['id'],
      'person_id': person['id'],
      'status': 'driver',
    });
    admin = await registerAdmin();
  });

  tearDownAll(disposeClients);

  test('Admin-Signup erzeugt keine Geister-pending-Gruppe', () async {
    final ghost = await service.from('groups').select().eq('id', admin.id);
    expect(
      ghost,
      isEmpty,
      reason: 'Der Signup-Trigger muss account_type=admin überspringen',
    );
  });

  test('Anlegen: die Gruppe ist sofort aktiv UND verknüpft', () async {
    final creator = await registerAdmin();
    final handle = uniqueName('neu');
    await creator.client.functions.invoke(
      'request-group',
      body: {
        'handle': handle,
        'password': 'gruppen-passwort-1',
        'groupName': 'E2E Anlage',
      },
    );

    final row = await service
        .from('groups')
        .select()
        .eq('handle', handle)
        .single();
    expect(
      row['status'],
      'active',
      reason: 'Es gibt keine Freigabe mehr — angelegt heißt nutzbar.',
    );
    expect(
      await service
          .from('group_admins')
          .select()
          .eq('group_id', row['id'] as String),
      hasLength(1),
      reason:
          'Aktiv und verknüpft entstehen in einem Zug. Fehlte der zweite '
          'Schritt, gehörte die Gruppe niemandem und niemand könnte sie mehr '
          'erreichen.',
    );
    // Und der Login funktioniert mit dem getippten Passwort.
    final probe = newAnonClient();
    final session = await probe.auth.signInWithPassword(
      email: '$handle@$e2eGroupDomain',
      password: 'gruppen-passwort-1',
    );
    expect(session.user, isNotNull);
  });

  test('Anlegen: anonym und als Gruppe abgewiesen', () async {
    final body = {
      'handle': uniqueName('darfnicht'),
      'password': 'gruppen-passwort-1',
      'groupName': 'E2E Verboten',
    };
    // Der anon-Key IST ein gültiges JWT — `verify_jwt` allein schützt hier
    // nichts. Ohne die getUser-Prüfung in der Function wäre der Endpunkt
    // eine offene Gruppenfabrik.
    await expectFunctionStatus(newAnonClient(), body, 401);
    // Ein Gruppen-Login ist angemeldet, aber kein Verwalter-Konto.
    await expectFunctionStatus(g.client, body, 403);
    expect(
      await service
          .from('groups')
          .select()
          .eq('handle', body['handle'] as String),
      isEmpty,
      reason: 'Kein abgewiesener Aufruf darf eine Zeile hinterlassen.',
    );
  });

  test('claim: falsches Gruppenpasswort prallt ab', () async {
    await expectRpcError(
      admin.client.rpc(
        'claim_admin_group',
        params: {'claim_handle': g.handle, 'group_password': 'voellig-falsch'},
      ),
      'wrong group credentials',
    );
  });

  test('claim: Gruppen-Konto ist kein Admin-Konto', () async {
    await expectRpcError(
      g.client.rpc(
        'claim_admin_group',
        params: {'claim_handle': g.handle, 'group_password': g.password},
      ),
      'not an admin account',
    );
  });

  test('claim verknüpft und my_admin_groups zeigt es', () async {
    await admin.client.rpc(
      'claim_admin_group',
      params: {'claim_handle': g.handle, 'group_password': g.password},
    );
    final linked = await admin.client.rpc<List<dynamic>>('my_admin_groups');
    expect(linked, hasLength(1));
    final row = linked.single as Map<String, dynamic>;
    expect(row['handle'], g.handle);
    expect(
      row['group_id'],
      g.id,
      reason: 'Die Konsole braucht die id, um Aktionen zuzuordnen.',
    );
    expect(
      (await service
          .from('groups')
          .select()
          .eq('id', g.id)
          .single())['released_at'],
      isNull,
      reason: 'Wer eine Gruppe übernimmt, löscht die Waisen-Markierung.',
    );
  });

  test('die Verknüpfung rastet ein: zweites Postfach prallt ab', () async {
    final second = await registerAdmin();
    await expectRpcError(
      second.client.rpc(
        'claim_admin_group',
        params: {'claim_handle': g.handle, 'group_password': g.password},
      ),
      'group already claimed',
    );
  });

  test('Admin sieht keinerlei Gruppendaten (anderer uid, RLS)', () async {
    expect(await admin.client.from('persons').select(), isEmpty);
    expect(await admin.client.from('trips').select(), isEmpty);
    expect(await admin.client.from('groups').select(), isEmpty);
    // Auch die Verknüpfungstabelle selbst hat bewusst null Policies.
    expect(await admin.client.from('group_admins').select(), isEmpty);
  });

  test('fünf Gruppen gehen, die sechste prallt am Deckel ab', () async {
    final creator = await registerAdmin();
    for (var i = 0; i < 5; i++) {
      await creator.client.functions.invoke(
        'request-group',
        body: {
          'handle': uniqueName('deckel$i'),
          'password': 'gruppen-passwort-1',
          'groupName': 'E2E Deckel $i',
        },
      );
    }
    expect(
      await service.from('group_admins').select().eq('user_id', creator.id),
      hasLength(5),
    );

    final sixth = uniqueName('deckelsechs');
    await expectFunctionStatus(creator.client, {
      'handle': sixth,
      'password': 'gruppen-passwort-1',
      'groupName': 'E2E Deckel 6',
    }, 429);
    expect(
      await service.from('groups').select().eq('handle', sixth),
      isEmpty,
      reason:
          'Der abgewiesene Versuch darf keinen Handle blockieren — sonst '
          'wäre der Name für immer verbrannt.',
    );
  });

  test('eine fremde Gruppe lässt sich nicht anfassen', () async {
    final other = await registerGroup('fremd');
    await expectRpcError(
      admin.client.rpc(
        'admin_reset_group_password',
        params: {'target_group': other.id, 'new_password': 'lang-genug-123'},
      ),
      'not linked',
    );
    await expectRpcError(
      admin.client.rpc(
        'admin_delete_group',
        params: {
          'target_group': other.id,
          'admin_password': admin.password,
          'handle_confirmation': other.handle,
        },
      ),
      'not linked',
    );
    expect(
      await service.from('groups').select().eq('id', other.id),
      hasLength(1),
      reason: 'Die fremde Gruppe steht unberührt da.',
    );
  });

  test('Übergabe: lösen mit Sudo, dann rastet das nächste Konto ein', () async {
    final g2 = await registerGroup('uebergabe');
    await unlinkGroup(service, g2.id);
    final first = await registerAdmin();
    await first.client.rpc<void>(
      'claim_admin_group',
      params: {'claim_handle': g2.handle, 'group_password': g2.password},
    );

    await expectRpcError(
      first.client.rpc<void>(
        'admin_release_group',
        params: {'target_group': g2.id, 'admin_password': 'voellig-falsch'},
      ),
      'wrong admin password',
    );

    await first.client.rpc<void>(
      'admin_release_group',
      params: {'target_group': g2.id, 'admin_password': first.password},
    );
    expect(
      await service.from('group_admins').select().eq('group_id', g2.id),
      isEmpty,
      reason: 'Nur die Verknüpfungszeile fällt — Gruppe und Konto bleiben.',
    );
    expect(
      (await service
          .from('groups')
          .select()
          .eq('id', g2.id)
          .single())['released_at'],
      isNotNull,
      reason:
          'Eine aktive Gruppe ohne Verwalter ist markiert — sonst wäre eine '
          'laufende Übergabe von einer echten Waise nicht zu unterscheiden.',
    );

    final successor = await registerAdmin();
    await successor.client.rpc<void>(
      'claim_admin_group',
      params: {'claim_handle': g2.handle, 'group_password': g2.password},
    );
    final linked = await successor.client.rpc<List<dynamic>>('my_admin_groups');
    expect(
      (linked.single as Map<String, dynamic>)['handle'],
      g2.handle,
      reason: 'Die Nachfolgerin rastet über den normalen claim-Weg ein.',
    );

    await expectRpcError(
      first.client.rpc<void>(
        'claim_admin_group',
        params: {'claim_handle': g2.handle, 'group_password': g2.password},
      ),
      'group already claimed',
    );
  });

  test('eine pending-Gruppe lässt sich nicht verknüpfen', () async {
    // Seit #106 entsteht keine pending-Gruppe mehr über die App — den Zustand
    // gibt es nur noch für Fremd-Signups gegen die Gruppen-Domain. Genau die
    // dürfen nicht übernehmbar sein.
    final pending = await registerGroup('pend');
    await unlinkGroup(service, pending.id);
    await makePending(service, pending.id);
    final fresh = await registerAdmin();
    await expectRpcError(
      fresh.client.rpc(
        'claim_admin_group',
        params: {
          'claim_handle': pending.handle,
          'group_password': pending.password,
        },
      ),
      'wrong group credentials',
    );
  });

  test('Gruppenpasswort-Reset: zu kurz prallt ab, sonst wirkt er', () async {
    await expectRpcError(
      admin.client.rpc(
        'admin_reset_group_password',
        params: {'target_group': g.id, 'new_password': 'kurz'},
      ),
      'password too short',
    );

    const newPassword = 'frisches-gruppen-pw-9';
    await admin.client.rpc(
      'admin_reset_group_password',
      params: {'target_group': g.id, 'new_password': newPassword},
    );

    final probe = newAnonClient();
    await expectLater(
      probe.auth.signInWithPassword(email: g.email, password: g.password),
      throwsA(isA<AuthException>()),
      reason: 'altes Gruppenpasswort darf nicht mehr gelten',
    );
    final session = await probe.auth.signInWithPassword(
      email: g.email,
      password: newPassword,
    );
    expect(session.user, isNotNull);
  });

  test('Löschen verlangt Admin-Passwort UND getippten Handle', () async {
    await expectRpcError(
      admin.client.rpc(
        'admin_delete_group',
        params: {
          'target_group': g.id,
          'admin_password': 'falsches-admin-pw',
          'handle_confirmation': g.handle,
        },
      ),
      'wrong admin password',
    );
    await expectRpcError(
      admin.client.rpc(
        'admin_delete_group',
        params: {
          'target_group': g.id,
          'admin_password': admin.password,
          'handle_confirmation': 'andere-gruppe',
        },
      ),
      'handle mismatch',
    );
  });

  test('Löschen reißt Gruppe und Daten mit — nicht das Konto', () async {
    // Eine zweite Gruppe am selben Konto: Sie beweist, dass das Löschen ein
    // chirurgischer Schnitt ist und nicht das halbe Konto mitnimmt.
    final keep = await registerGroup('bleibt');
    await unlinkGroup(service, keep.id);
    await admin.client.rpc<void>(
      'claim_admin_group',
      params: {'claim_handle': keep.handle, 'group_password': keep.password},
    );

    await admin.client.rpc(
      'admin_delete_group',
      params: {
        'target_group': g.id,
        'admin_password': admin.password,
        'handle_confirmation': g.handle,
      },
    );

    expect(await service.from('groups').select().eq('id', g.id), isEmpty);
    expect(
      await service.from('persons').select().eq('group_id', g.id),
      isEmpty,
    );
    expect(await service.from('trips').select().eq('group_id', g.id), isEmpty);

    final probe = newAnonClient();
    await expectLater(
      probe.auth.signInWithPassword(
        email: g.email,
        password: 'frisches-gruppen-pw-9',
      ),
      throwsA(isA<AuthException>()),
      reason: 'Gruppen-Auth-User muss weg sein',
    );

    // Und das Konto lebt weiter, mit seiner anderen Gruppe.
    final session = await probe.auth.signInWithPassword(
      email: admin.email,
      password: admin.password,
    );
    expect(
      session.user,
      isNotNull,
      reason:
          'Bei bis zu fünf Gruppen wäre ein Selbst-Löschen Datenverlust an '
          'den übrigen — und es verschärfte die Sackgasse, wenn Postfach und '
          'Passwort verloren gehen.',
    );
    final rest = await service
        .from('group_admins')
        .select()
        .eq('user_id', admin.id);
    expect(
      rest.map((row) => row['group_id']),
      [keep.id],
      reason: 'Genau die gelöschte Verknüpfung ist weg, die andere bleibt.',
    );
  });
}

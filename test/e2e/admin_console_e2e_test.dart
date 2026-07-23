/// E2E: Verwalter-Konsole (Issue #55) gegen den echten Stack.
///
/// Beweist die vier Annahmen, die test/schema_test.dart nur statisch prüft:
/// kein Geister-Pending beim Admin-Signup, Erst-Verknüpfung nur mit
/// Gruppen-Login und Einrasten, Passwort-Reset wirkt aufs Gruppen-Konto,
/// Löschen reißt über die Auth-Kaskade alles mit.
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
    await activateGroup(service, g.id);
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

  test(
    'claim mit Gruppen-Login verknüpft und my_admin_group zeigt es',
    () async {
      await admin.client.rpc(
        'claim_admin_group',
        params: {'claim_handle': g.handle, 'group_password': g.password},
      );
      final linked = await admin.client.rpc('my_admin_group');
      expect(linked, hasLength(1));
      expect((linked.single as Map<String, dynamic>)['handle'], g.handle);
    },
  );

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

  test('derselbe Admin kann keine zweite Gruppe verknüpfen', () async {
    // Die 1:1-Zusage gilt in beide Richtungen: nicht nur ein Konto je
    // Gruppe, auch eine Gruppe je Konto (user_id ist Primärschlüssel).
    final second = await registerGroup('zweitgruppe');
    await activateGroup(service, second.id);
    await expectRpcError(
      admin.client.rpc(
        'claim_admin_group',
        params: {
          'claim_handle': second.handle,
          'group_password': second.password,
        },
      ),
      'admin already linked',
    );
  });

  test('eine pending-Gruppe lässt sich nicht verknüpfen', () async {
    // Erst die Freigabe macht die Gruppe verknüpfbar — vorher lehnt der
    // Server ab, selbst mit korrektem Gruppen-Login.
    final pending = await registerGroup('pend');
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
        params: {'new_password': 'kurz'},
      ),
      'password too short',
    );

    const newPassword = 'frisches-gruppen-pw-9';
    await admin.client.rpc(
      'admin_reset_group_password',
      params: {'new_password': newPassword},
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
          'admin_password': admin.password,
          'handle_confirmation': 'andere-gruppe',
        },
      ),
      'handle mismatch',
    );
  });

  test(
    'Löschen reißt Gruppe, Daten und Admin-Konto in einem Schlag mit',
    () async {
      await admin.client.rpc(
        'admin_delete_group',
        params: {
          'admin_password': admin.password,
          'handle_confirmation': g.handle,
        },
      );

      expect(await service.from('groups').select().eq('id', g.id), isEmpty);
      expect(
        await service.from('persons').select().eq('group_id', g.id),
        isEmpty,
      );
      expect(
        await service.from('trips').select().eq('group_id', g.id),
        isEmpty,
      );
      expect(
        await service.from('group_admins').select().eq('user_id', admin.id),
        isEmpty,
      );

      final probe = newAnonClient();
      await expectLater(
        probe.auth.signInWithPassword(
          email: g.email,
          password: 'frisches-gruppen-pw-9',
        ),
        throwsA(isA<AuthException>()),
        reason: 'Gruppen-Auth-User muss weg sein',
      );
      await expectLater(
        probe.auth.signInWithPassword(
          email: admin.email,
          password: admin.password,
        ),
        throwsA(isA<AuthException>()),
        reason: 'Admin-Konto muss sich selbst mitgelöscht haben',
      );
    },
  );
}

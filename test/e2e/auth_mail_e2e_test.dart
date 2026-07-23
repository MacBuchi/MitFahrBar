/// E2E: Auth-Workflows mit echten Mails (Mailpit) und Bestätigungspflicht.
///
/// Der Stack läuft wie Production mit `enable_confirmations = true`
/// (config.toml): Verwalter-Konten müssen den Link aus der
/// Registrierungs-Mail einlösen, Gruppen-Konten entstehen deshalb NUR über
/// die Edge Function `request-group` — serverseitig bestätigt, ohne dass je
/// eine Mail an die unzustellbare Fake-Adresse geht. Genau dieser Vertrag
/// ist hier festgenagelt; ein Rückbau auf Client-Signup für Gruppen oder
/// auf Autoconfirm fällt sofort auf. Was hier NICHT geprüft wird, ist die
/// Brevo-Zustellung in Production (reine Dashboard-Konfiguration).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2e_env.dart';

void main() {
  if (!e2eConfigured) {
    test('Mail-E2E', () {}, skip: e2eSkipReason);
    return;
  }

  tearDownAll(disposeClients);

  test(
    'Gruppen-Anlage: keine Mail, sofort anmeldbar, Gruppe pending',
    () async {
      final service = newServiceClient();
      final g = await registerGroup('fn');

      // registerGroup hat sich bereits angemeldet — das beweist: Das Konto
      // ist ohne jeden Mail-Klick nutzbar (email_confirm der Admin-API).
      expect(
        await noMailFor(g.email),
        isTrue,
        reason:
            'An die Fake-Adresse darf nie eine Mail gehen — in Production '
            'wäre das ein Bounce bei Brevo.',
      );

      final rows = await service.from('groups').select().eq('id', g.id);
      expect(
        rows.single['status'],
        'pending',
        reason: 'Der Signup-Trigger greift auch beim Admin-API-Weg.',
      );
      expect(rows.single['name'], 'E2E fn');
    },
  );

  test('doppelter Handle prallt an der Function mit 409 ab', () async {
    final g = await registerGroup('dup');
    final probe = newAnonClient();
    await expectLater(
      probe.functions.invoke(
        'request-group',
        body: {
          'handle': g.handle,
          'password': 'irgendwas-langes-1',
          'groupName': 'Doppelt',
        },
      ),
      throwsA(isA<FunctionException>().having((e) => e.status, 'status', 409)),
    );
  });

  test('die Function weist zu kurze Passwörter ab', () async {
    final probe = newAnonClient();
    await expectLater(
      probe.functions.invoke(
        'request-group',
        body: {
          'handle': uniqueName('kurz'),
          'password': 'kurz',
          'groupName': 'Zu kurz',
        },
      ),
      throwsA(isA<FunctionException>().having((e) => e.status, 'status', 400)),
    );
  });

  test('Admin-Signup verlangt die Bestätigung wirklich', () async {
    final email = '${uniqueName('confirm')}@e2e-postfach.test';
    const password = 'admin-passwort-1';
    final client = newAnonClient();
    await client.auth.signUp(
      email: email,
      password: password,
      data: {'account_type': 'admin'},
    );

    await expectLater(
      client.auth.signInWithPassword(email: email, password: password),
      throwsA(isA<AuthException>()),
      reason: 'Vor dem Bestätigungs-Link bleibt das Konto gesperrt.',
    );

    await openAuthLink(firstLink(await waitForMail(email, subject: 'Confirm')));
    final session = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    expect(session.user, isNotNull, reason: 'Nach dem Link klappt der Login.');
  });

  test(
    'Passwort vergessen: Recovery-Mail kommt an und trägt den Link',
    () async {
      final admin = await registerAdmin();
      await admin.client.auth.resetPasswordForEmail(admin.email);

      final body = await waitForMail(admin.email, subject: 'Reset');
      final link = firstLink(body);
      expect(link, contains('/auth/v1/verify'));
      expect(link, contains('type=recovery'));
    },
  );

  test('der Recovery-Link ist gültig (Redirect ohne Fehler)', () async {
    final admin = await registerAdmin();
    await admin.client.auth.resetPasswordForEmail(admin.email);
    final link = firstLink(await waitForMail(admin.email, subject: 'Reset'));
    // openAuthLink wirft, wenn GoTrue den Token nicht einlöst oder die
    // Weiterleitung einen Fehler trägt.
    await openAuthLink(link);
  });
}

/// E2E: Auth-Workflows mit echten Mails (Mailpit) und Bestätigungspflicht.
///
/// Der Stack läuft wie Production mit `enable_confirmations = true` und mit
/// denselben Mail-Vorlagen (config.toml → supabase/templates/): Verwalter-
/// Konten müssen den **Code** aus der Registrierungs-Mail eingeben,
/// Gruppen-Konten entstehen deshalb NUR über die Edge Function
/// `request-group` — serverseitig bestätigt, ohne dass je eine Mail an die
/// unzustellbare Fake-Adresse geht. Genau dieser Vertrag ist hier
/// festgenagelt; ein Rückbau auf Client-Signup für Gruppen oder auf
/// Autoconfirm fällt sofort auf.
///
/// Seit Issue #102 hängt hier auch der Passwort-Reset dran: Code statt Link,
/// weil der Link an das anfordernde Gerät gebunden wäre. Der Rundlauf unten
/// beweist gegen echtes GoTrue, dass `verifyOTP` + `updateUser` durchgehen —
/// die Fakes können das nicht.
///
/// Was hier NICHT geprüft wird, ist die Brevo-Zustellung in Production und
/// die dortigen Vorlagen (reine Dashboard-Konfiguration; dafür wacht
/// tool/config_drift.sh).
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
      reason: 'Vor der Bestätigung bleibt das Konto gesperrt.',
    );

    // firstCode wirft, wenn die Vorlage einen Link statt des Codes führt.
    await client.auth.verifyOTP(
      email: email,
      token: firstCode(await waitForMail(email, subject: 'Adresse')),
      type: OtpType.signup,
    );
    final session = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    expect(session.user, isNotNull, reason: 'Nach dem Code klappt der Login.');
  });

  test(
    'E-Mail-Wechsel verlangt beide Bestätigungen, dann gilt die neue',
    () async {
      final admin = await registerAdmin();
      final newEmail = '${uniqueName('wechsel')}@e2e-postfach.test';
      await admin.client.auth.updateUser(UserAttributes(email: newEmail));

      // Secure email change: je ein Link an die alte UND die neue Adresse —
      // beide mit dem Betreff „Confirm your new email address" (der
      // unterscheidet sie von der Signup-Mail „Confirm your email address").
      await openAuthLink(
        firstLink(await waitForMail(admin.email, subject: 'new email')),
      );
      await openAuthLink(
        firstLink(await waitForMail(newEmail, subject: 'new email')),
      );

      final probe = newAnonClient();
      await expectLater(
        probe.auth.signInWithPassword(
          email: admin.email,
          password: admin.password,
        ),
        throwsA(isA<AuthException>()),
        reason: 'Die alte Adresse gilt nach dem Wechsel nicht mehr.',
      );
      final session = await probe.auth.signInWithPassword(
        email: newEmail,
        password: admin.password,
      );
      expect(session.user!.email, newEmail);
    },
  );

  test(
    'Passwort vergessen: Recovery-Mail trägt einen Code und keinen Link',
    () async {
      final admin = await registerAdmin();
      await admin.client.auth.resetPasswordForEmail(admin.email);

      final body = await waitForMail(admin.email, subject: 'Code zum');
      expect(
        body,
        isNot(contains('auth/v1/verify')),
        reason:
            'Ein Link in der Reset-Mail hielte den gerätegebundenen '
            '(kaputten) Weg offen — siehe Issue #102.',
      );
      // Wirft, wenn die Vorlage kein {{ .Token }} zeigt.
      expect(firstCode(body), matches(RegExp(r'^\d{6}$')));
    },
  );

  test(
    'Passwort vergessen: der Code setzt wirklich ein neues Passwort',
    () async {
      final admin = await registerAdmin();
      const newPassword = 'admin-passwort-neu-2';
      await admin.client.auth.resetPasswordForEmail(admin.email);
      final code = firstCode(
        await waitForMail(admin.email, subject: 'Code zum'),
      );

      // Der Ablauf aus AuthRepository.resetAdminPasswordWithCode gegen echtes
      // GoTrue. Dass updateUser direkt nach verifyOTP durchgeht, kann kein
      // Fake beweisen — es hängt an der Server-Konfiguration.
      final probe = newAnonClient();
      await probe.auth.verifyOTP(
        email: admin.email,
        token: code,
        type: OtpType.recovery,
      );
      await probe.auth.updateUser(UserAttributes(password: newPassword));
      await probe.auth.signOut();

      final check = newAnonClient();
      await expectLater(
        check.auth.signInWithPassword(
          email: admin.email,
          password: admin.password,
        ),
        throwsA(isA<AuthException>()),
        reason: 'Das alte Passwort gilt nach dem Zurücksetzen nicht mehr.',
      );
      final session = await check.auth.signInWithPassword(
        email: admin.email,
        password: newPassword,
      );
      expect(session.user!.email, admin.email);
    },
  );

  test('Passwort vergessen: ein falscher Code wird abgewiesen', () async {
    final admin = await registerAdmin();
    await admin.client.auth.resetPasswordForEmail(admin.email);
    await waitForMail(admin.email, subject: 'Code zum');

    // Nagelt die Fehlerzuordnung in SupabaseAuthRepository fest: Genau dieser
    // Code wird zur InvalidCodeException und damit zu „falsch oder
    // abgelaufen" im Konsolen-Login.
    final probe = newAnonClient();
    await expectLater(
      probe.auth.verifyOTP(
        email: admin.email,
        token: '000000',
        type: OtpType.recovery,
      ),
      throwsA(
        isA<AuthException>().having(
          (e) => e.code == 'otp_expired' || e.statusCode == '403',
          'als ungültiger Code erkennbar',
          isTrue,
        ),
      ),
    );
  });
}

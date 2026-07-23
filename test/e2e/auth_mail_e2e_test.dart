/// E2E: Passwort-Workflows mit echten Auth-Mails (Mailpit).
///
/// Der lokale Stack fängt jede Mail ab, die GoTrue verschickt — damit ist
/// der komplette Weg „App-Aufruf → GoTrue → SMTP → Postfach → Link"
/// automatisiert prüfbar, ganz ohne Brevo. Was hier NICHT geprüft wird,
/// ist die Brevo-Zustellung in Production (reine Dashboard-Konfiguration).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  if (!e2eConfigured) {
    test('Mail-E2E', () {}, skip: e2eSkipReason);
    return;
  }

  tearDownAll(disposeClients);

  test(
    'Passwort vergessen: Recovery-Mail kommt an und trägt den Link',
    () async {
      final admin = await registerAdmin();
      await admin.client.auth.resetPasswordForEmail(admin.email);

      final body = await waitForMail(admin.email);
      final link = firstLink(body);
      expect(link, contains('/auth/v1/verify'));
      expect(link, contains('type=recovery'));
    },
  );

  test('der Recovery-Link ist gültig (Redirect ohne Fehler)', () async {
    final admin = await registerAdmin();
    await admin.client.auth.resetPasswordForEmail(admin.email);
    final link = rebaseAuthLink(firstLink(await waitForMail(admin.email)));

    final http = HttpClient();
    try {
      final request = await http.getUrl(Uri.parse(link));
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final location = response.headers.value('location') ?? '';
      expect(
        response.statusCode,
        inInclusiveRange(300, 399),
        reason: 'GoTrue muss den Token einlösen und weiterleiten',
      );
      expect(
        location,
        isNot(contains('error')),
        reason: 'Weiterleitung darf keinen Auth-Fehler tragen: $location',
      );
    } finally {
      http.close(force: true);
    }
  });

  test('Gruppen-Signup verschickt KEINE Mail (Autoconfirm)', () async {
    // Gruppen-Logins sind Fake-Adressen (handle@grp.fahrgemeinschaft.app),
    // die nie eine Mail bestätigen könnten. Deshalb läuft Auth mit
    // Autoconfirm — dieselbe Einstellung, mit der Production heute läuft.
    // Kehrseite (bewusst festgenagelt): Auch ein Admin-Signup löst dann
    // keine Bestätigungsmail aus. Wer Bestätigungen einschaltet, muss
    // zuerst klären, wie Gruppen-Signups dann noch funktionieren.
    final g = await registerGroup('mail');
    expect(await noMailFor(g.email), isTrue);
  });
}

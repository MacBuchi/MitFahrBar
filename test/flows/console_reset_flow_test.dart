/// console_reset_flow_test.dart – „Passwort vergessen" für das
/// Verwalter-Konto, vom Anfordern des Codes bis zum neuen Passwort. Komplette
/// App gegen das In-Memory-Backend (siehe test/fakes/).
///
/// Der Reset läuft absichtlich über den Zahlencode aus der Mail und nicht
/// über deren Link (Issue #102): Der Link ist an das Gerät gebunden, das ihn
/// angefordert hat (PKCE-Verifier im lokalen Speicher), und stirbt daher,
/// wenn die Mail woanders geöffnet wird — der Normalfall, wenn man in der
/// App anfordert und im Handy-Browser liest. Begründung an
/// `AuthRepository.sendAdminPasswordResetCode`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/log.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _adminEmail = 'verwalter@example.org';
const _adminPassword = 'konsole-geheim-9';
const _newPassword = 'reset-neu-gesetzt';

FakeBackend _backend() {
  final backend = FakeBackend();
  backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  backend.adminAccounts[_adminEmail] = FakeAdminAccount(
    password: _adminPassword,
  );
  return backend;
}

/// Erst ins Bild holen, dann tippen: Der Code-Modus zeigt vier Felder und
/// einen Hinweis, damit rutscht der Knopf im kleinen Test-Viewport unter den
/// sichtbaren Rand — ein Tap daneben warnt nur, statt zu scheitern, und der
/// Test liefe stumm ins Leere.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Bringt den Konsolen-Login in den Code-Modus: E-Mail eintragen, Code
/// anfordern. Die Vorbedingung der meisten Tests hier.
Future<void> _requestCode(WidgetTester tester, String email) async {
  await _tap(tester, find.text('Verwalter-Konsole'));
  await _tap(tester, find.text('Passwort vergessen?'));
  await tester.enterText(find.widgetWithText(TextField, 'E-Mail'), email);
  await _tap(tester, find.widgetWithText(FilledButton, 'Code anfordern'));
}

Future<void> _enterReset(
  WidgetTester tester, {
  required String code,
  required String password,
  String? repeat,
}) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Code aus der Mail'),
    code,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Neues Passwort'),
    password,
  );
  await tester.enterText(
    find.widgetWithText(TextField, 'Neues Passwort wiederholen'),
    repeat ?? password,
  );
  await _tap(
    tester,
    find.widgetWithText(FilledButton, 'Neues Passwort speichern'),
  );
}

void main() {
  testWidgets('Passwort vergessen fragt nur die E-Mail ab', (tester) async {
    await pumpApp(tester, _backend(), splash: false);
    await _tap(tester, find.text('Verwalter-Konsole'));
    await _tap(tester, find.text('Passwort vergessen?'));

    expect(
      find.byType(TextField),
      findsOneWidget,
      reason:
          'Im Reset-Modus gibt es kein Passwortfeld — nur die E-Mail. Sonst '
          'tippt man dort das vergessene Passwort ein.',
    );
    expect(find.widgetWithText(FilledButton, 'Code anfordern'), findsOneWidget);
  });

  testWidgets('unbekannte Adresse verrät nicht, dass es kein Konto gibt', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _requestCode(tester, 'gibtesnicht@example.org');

    expect(
      find.textContaining('Wenn es zu gibtesnicht@example.org ein Konto gibt'),
      findsOneWidget,
      reason:
          'Erfolg und Fehlschlag melden dasselbe — sonst wird die Antwort '
          'zum Konto-Orakel.',
    );
    expect(
      backend.passwordResets,
      ['gibtesnicht@example.org'],
      reason: 'Angefordert wird trotzdem, wie bei Supabase.',
    );
    expect(
      find.widgetWithText(TextField, 'Code aus der Mail'),
      findsOneWidget,
      reason: 'Auch der Weg dahin darf die beiden Fälle nicht trennen.',
    );
  });

  testWidgets('falscher Code lässt niemanden in die Konsole', (tester) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _requestCode(tester, _adminEmail);

    await _enterReset(tester, code: '000000', password: _newPassword);

    expect(find.textContaining('falsch oder abgelaufen'), findsOneWidget);
    expect(
      find.text('Verwalter-Konsole'),
      findsWidgets,
      reason: 'Wir bleiben auf dem Login — die Konsole bleibt zu.',
    );
    expect(
      find.widgetWithText(FilledButton, 'Neues Passwort speichern'),
      findsOneWidget,
      reason: 'Der Code-Modus steht noch, ein zweiter Versuch ist möglich.',
    );
    expect(
      backend.adminAccounts[_adminEmail]!.password,
      _adminPassword,
      reason: 'Das Passwort bleibt unverändert.',
    );
  });

  testWidgets('zwei verschiedene Passwörter werden abgefangen', (tester) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _requestCode(tester, _adminEmail);

    await _enterReset(
      tester,
      code: FakeBackend.resetCode,
      password: _newPassword,
      repeat: 'etwas-anderes-9',
    );

    expect(find.textContaining('stimmen nicht überein'), findsOneWidget);
    expect(
      backend.currentEmail,
      isNull,
      reason: 'Der Code wurde gar nicht erst eingelöst.',
    );
    expect(backend.adminAccounts[_adminEmail]!.password, _adminPassword);
  });

  testWidgets('zu kurzes Passwort wird abgefangen', (tester) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _requestCode(tester, _adminEmail);

    await _enterReset(tester, code: FakeBackend.resetCode, password: 'kurz');

    expect(find.textContaining('mindestens 8 Zeichen'), findsOneWidget);
    expect(backend.currentEmail, isNull);
    expect(backend.adminAccounts[_adminEmail]!.password, _adminPassword);
  });

  testWidgets('richtiger Code setzt das Passwort und führt in die Konsole', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);
    await pumpApp(tester, backend, splash: false);
    await _requestCode(tester, _adminEmail);

    await _enterReset(
      tester,
      code: FakeBackend.resetCode,
      password: _newPassword,
    );

    expect(
      find.text('Verknüpfung lösen …'),
      findsOneWidget,
      reason:
          'Nach dem Ändern öffnet erst das Ereignis aus updateUser die '
          'Konsole — hier sichtbar an der Übergabe-Karte.',
    );
    // Der Effekt, nicht nur der Aufruf: das Passwort ist wirklich neu.
    expect(backend.adminAccounts[_adminEmail]!.password, _newPassword);
    expect(
      logRing.lines.join('\n'),
      isNot(contains(_newPassword)),
      reason: 'Ein Passwort darf nie im Protokoll landen.',
    );
  });

  testWidgets('eine Recovery-Sitzung allein öffnet die Konsole nicht', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _tap(tester, find.text('Verwalter-Konsole'));

    // Genau der Zustand direkt nach dem Einlösen des Codes: gültige Sitzung,
    // aber das neue Passwort ist noch nicht gesetzt. Reagierte der Router
    // darauf, risse der Redirect (Admin-Sitzung → /console) den Login mitten
    // im Zurücksetzen weg — und bei einem Fehlschlag säße jemand angemeldet
    // in der Konsole, ohne sein Passwort zu kennen. Ohne den Filter in
    // lib/core/router.dart wird dieser Test rot.
    backend.beginRecovery(_adminEmail);
    await tester.pumpAndSettle();

    expect(find.text('Verknüpfung lösen …'), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Anmelden'),
      findsOneWidget,
      reason: 'Erst das geänderte Passwort darf hereinlassen.',
    );
  });

  testWidgets('Zurück zur Anmeldung stellt das Passwortfeld wieder her', (
    tester,
  ) async {
    await pumpApp(tester, _backend(), splash: false);
    await _requestCode(tester, _adminEmail);

    await _tap(tester, find.text('Zurück zur Anmeldung'));

    expect(
      find.byType(TextField),
      findsNWidgets(2),
      reason: 'Zurück im Anmelden-Modus sind E-Mail und Passwort wieder da.',
    );
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
    expect(find.text('Passwort vergessen?'), findsOneWidget);
  });

  testWidgets('Registrieren bestätigt die Adresse mit dem Code', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _tap(tester, find.text('Verwalter-Konsole'));
    await _tap(tester, find.text('Registrieren'));

    await tester.enterText(
      find.widgetWithText(TextField, 'E-Mail'),
      'neu@example.org',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passwort'),
      'ganz-geheim-12',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Passwort wiederholen'),
      'ganz-geheim-12',
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Registrieren'));

    expect(
      backend.adminAccounts['neu@example.org']!.confirmed,
      isFalse,
      reason: 'Registrieren allein bestätigt die Adresse nicht.',
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Code aus der Mail'),
      FakeBackend.confirmCode,
    );
    await _tap(tester, find.widgetWithText(FilledButton, 'Adresse bestätigen'));

    expect(backend.adminAccounts['neu@example.org']!.confirmed, isTrue);
    expect(
      find.text('Gruppe verknüpfen'),
      findsOneWidget,
      reason:
          'verifyOTP liefert die Sitzung gleich mit — der Router führt in '
          'die Konsole, ohne zweite Anmeldung.',
    );
  });
}

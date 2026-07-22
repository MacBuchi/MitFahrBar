/// console_flow_test.dart – Die Verwalter-Konsole über die echte App.
///
/// Geprüft werden die Zusagen, an denen Sicherheit hängt: Verknüpfen nur
/// mit Gruppen-Nachweis und nur einmal je Gruppe; die Rettungsleine
/// (Gruppenpasswort neu) wirkt wirklich; Löschen nur mit Sudo-Bestätigung
/// und dann restlos. Und: Kein Passwort landet je in `logRing`.
library;

import 'package:fahrgemeinschaft/core/log.dart';
import 'package:fahrgemeinschaft/features/console/console_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

const _adminEmail = 'verwalter@example.org';
const _adminPassword = 'konsole-geheim-9';

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

/// Erst ins Bild holen, dann tippen: Die Konsolen-Formulare ragen im
/// kleinen Test-Viewport unter den sichtbaren Bereich — ein Tap daneben
/// warnt nur, statt zu scheitern, und der Test liefe ins Leere.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Vom Gruppen-Login über den dezenten Link in die Konsole und anmelden.
Future<void> _openConsoleLogin(WidgetTester tester) async {
  await _tap(tester, find.text('Verwalter-Konsole'));
}

Future<void> _signInToConsole(WidgetTester tester) async {
  await _openConsoleLogin(tester);
  await tester.enterText(find.byType(TextField).first, _adminEmail);
  await tester.enterText(find.byType(TextField).last, _adminPassword);
  await _tap(tester, find.widgetWithText(FilledButton, 'Anmelden'));
}

Future<void> _claim(WidgetTester tester, String password) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, password);
  await _tap(tester, find.widgetWithText(FilledButton, 'Verknüpfen'));
}

void main() {
  testWidgets('Verknüpfen braucht das echte Gruppen-Login', (tester) async {
    await pumpApp(tester, _backend(), splash: false);
    await _signInToConsole(tester);

    expect(find.byType(ConsoleScreen), findsOneWidget);

    await _claim(tester, 'falsches-passwort');
    expect(
      find.text('Gruppenname oder Gruppenpasswort falsch.'),
      findsOneWidget,
    );

    await _claim(tester, 'geheim123');
    expect(
      find.textContaining('Verwaltet: daciaracing'),
      findsOneWidget,
      reason: 'Mit korrektem Nachweis ist die Gruppe verknüpft.',
    );
  });

  testWidgets('je Gruppe gibt es genau ein Verwalter-Konto', (tester) async {
    final backend = _backend();
    // Ein zweites Admin-Konto und eine bereits eingerastete Verknüpfung.
    backend.adminAccounts[_adminEmail]!.groupId = backend.groups.keys.first;
    backend.adminAccounts['zweiter@example.org'] = FakeAdminAccount(
      password: 'auch-geheim-99',
    );

    await pumpApp(tester, backend, splash: false);
    await _openConsoleLogin(tester);
    await tester.enterText(find.byType(TextField).first, 'zweiter@example.org');
    await tester.enterText(find.byType(TextField).last, 'auch-geheim-99');
    await _tap(tester, find.widgetWithText(FilledButton, 'Anmelden'));

    await _claim(tester, 'geheim123');
    expect(
      find.textContaining('schon ein Verwalter-Konto'),
      findsOneWidget,
      reason: 'Die Erst-Verknüpfung rastet ein — kein Übernehmen von außen.',
    );
  });

  testWidgets('die Rettungsleine setzt das Gruppenpasswort wirklich neu', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupId = backend.groups.keys.first;

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Neu setzen'));
    await tester.enterText(find.byType(TextField).first, 'frisch-gesetzt-1');
    await tester.enterText(find.byType(TextField).last, 'frisch-gesetzt-1');
    await _tap(tester, find.widgetWithText(FilledButton, 'Neu setzen').last);

    expect(find.textContaining('neu gesetzt'), findsOneWidget);
    expect(
      backend.accounts.values.single.password,
      'frisch-gesetzt-1',
      reason: 'Der Gruppen-Login muss ab jetzt das neue Passwort verlangen.',
    );
    expect(
      logRing.lines.join('\n'),
      isNot(contains('frisch-gesetzt-1')),
      reason: 'Ein Passwort darf nie im Protokoll landen.',
    );
  });

  testWidgets('Löschen scheitert folgenlos an falscher Sudo-Eingabe', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupId = backend.groups.keys.first;

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Gruppe löschen …'));
    await tester.enterText(find.byType(TextField).first, 'falsch');
    await tester.enterText(find.byType(TextField).last, 'daciaracing');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(find.text('Das Admin-Passwort stimmt nicht.'), findsOneWidget);
    expect(backend.groups, hasLength(1), reason: 'Nichts wurde gelöscht.');

    await tester.enterText(find.byType(TextField).first, _adminPassword);
    await tester.enterText(find.byType(TextField).last, 'daciaracin');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(find.textContaining('stimmt nicht mit'), findsOneWidget);
    expect(backend.groups, hasLength(1));
  });

  testWidgets('korrektes Löschen entfernt Gruppe, Konto und Login', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupId = backend.groups.keys.first;

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Gruppe löschen …'));
    await tester.enterText(find.byType(TextField).first, _adminPassword);
    await tester.enterText(find.byType(TextField).last, 'daciaracing');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(
      find.widgetWithText(FilledButton, 'Anmelden'),
      findsOneWidget,
      reason: 'Nach dem Löschen landet man auf dem Login.',
    );
    expect(backend.groups, isEmpty);
    expect(backend.accounts, isEmpty);
    expect(
      backend.adminAccounts,
      isEmpty,
      reason: 'Auch das Verwalter-Konto verschwindet — keine Reste.',
    );
    expect(
      logRing.lines.join('\n'),
      isNot(contains(_adminPassword)),
      reason: 'Das Admin-Passwort darf nie im Protokoll landen.',
    );
  });
}

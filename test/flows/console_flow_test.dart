/// console_flow_test.dart – Die Verwalter-Konsole über die echte App.
///
/// Geprüft werden die Zusagen, an denen Sicherheit hängt: Anlegen erzeugt
/// eine Gruppe, die sofort jemandem gehört; das Gruppenpasswort wird doppelt
/// abgefragt (#107); Übernehmen nur mit Gruppen-Nachweis und nur einmal je
/// Gruppe; der Deckel von fünf Gruppen hält; jede Aktion trifft genau ihre
/// Gruppe; Löschen nur mit Sudo-Bestätigung, und danach lebt das
/// Verwalter-Konto weiter. Und: Kein Passwort landet je in `logRing`.
///
/// Gesucht wird über **Feldnamen**, nicht über Positionen: Die Konsole zeigt
/// Anlegen und Übernehmen gleichzeitig, `find.byType(TextField).first` traf
/// also das falsche Formular.
library;

import 'package:mitfahrbar/core/log.dart';
import 'package:mitfahrbar/data/admin_repository.dart';
import 'package:mitfahrbar/features/console/console_screen.dart';
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

/// Tippt in das Feld mit diesem Beschriftungstext.
Future<void> _fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

/// Vom Gruppen-Login über den dezenten Link in die Konsole und anmelden.
Future<void> _openConsoleLogin(WidgetTester tester) async {
  await _tap(tester, find.text('Verwalter-Konsole'));
}

Future<void> _signInToConsole(WidgetTester tester) async {
  await _openConsoleLogin(tester);
  // Der Login-Screen selbst hat genau zwei Felder — dort bleibt die Position
  // eindeutig.
  await tester.enterText(find.byType(TextField).first, _adminEmail);
  await tester.enterText(find.byType(TextField).last, _adminPassword);
  await _tap(tester, find.widgetWithText(FilledButton, 'Anmelden'));
}

Future<void> _claim(WidgetTester tester, String password) async {
  await _fill(tester, 'Anmeldename der Gruppe', 'daciaracing');
  await _fill(tester, 'Passwort der Gruppe', password);
  await _tap(tester, find.widgetWithText(FilledButton, 'Verknüpfen'));
}

Future<void> _createGroup(
  WidgetTester tester, {
  required String name,
  required String handle,
  required String password,
  String? repeat,
}) async {
  await _fill(tester, 'Name der Gruppe', name);
  await _fill(tester, 'Anmeldename', handle);
  await _fill(tester, 'Gruppenpasswort', password);
  await _fill(tester, 'Gruppenpasswort wiederholen', repeat ?? password);
  await _tap(tester, find.widgetWithText(FilledButton, 'Gruppe anlegen'));
}

void main() {
  testWidgets('Anlegen erzeugt eine Gruppe, die sofort nutzbar ist', (
    tester,
  ) async {
    final backend = FakeBackend();
    backend.adminAccounts[_adminEmail] = FakeAdminAccount(
      password: _adminPassword,
    );
    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    expect(find.byType(ConsoleScreen), findsOneWidget);
    expect(find.textContaining('Noch keine'), findsOneWidget);

    await _createGroup(
      tester,
      name: 'Pendler Nord',
      handle: 'pendlernord',
      password: 'gruppe-geheim-1',
    );

    expect(
      find.textContaining('Verwaltet: pendlernord'),
      findsOneWidget,
      reason: 'Die neue Gruppe erscheint in der Liste des Kontos.',
    );
    final group = backend.groups.values.single;
    expect(group.handle, 'pendlernord');
    expect(
      group.isActive,
      isTrue,
      reason: 'Sofort nutzbar — es gibt keine Freigabe mehr.',
    );
    expect(
      backend.adminAccounts[_adminEmail]!.groupIds,
      [group.id],
      reason:
          'Angelegt und verknüpft in einem Zug: keine Gruppe ohne Besitzer.',
    );
    expect(
      backend.accounts['pendlernord@grp.fahrgemeinschaft.app']!.password,
      'gruppe-geheim-1',
      reason: 'Mit genau diesem Passwort melden sich die Mitglieder an.',
    );
    expect(
      logRing.lines.join('\n'),
      isNot(contains('gruppe-geheim-1')),
      reason: 'Ein Passwort darf nie im Protokoll landen.',
    );
  });

  testWidgets('abweichende Wiederholung legt nichts an (#107)', (tester) async {
    final backend = FakeBackend();
    backend.adminAccounts[_adminEmail] = FakeAdminAccount(
      password: _adminPassword,
    );
    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _createGroup(
      tester,
      name: 'Vertippt',
      handle: 'vertippt',
      password: 'gruppe-geheim-1',
      repeat: 'gruppe-geheim-2',
    );

    expect(find.text('Die Eingaben stimmen nicht überein.'), findsOneWidget);
    expect(
      backend.groups,
      isEmpty,
      reason:
          'Ein Tippfehler im Gruppenpasswort wäre ohne Betreiber nicht mehr '
          'zu heilen — deshalb darf hier nichts entstehen.',
    );
    expect(logRing.lines.join('\n'), isNot(contains('gruppe-geheim-')));
  });

  testWidgets('Übernehmen braucht das echte Gruppen-Login', (tester) async {
    await pumpApp(tester, _backend(), splash: false);
    await _signInToConsole(tester);

    await _claim(tester, 'falsches-passwort');
    expect(
      find.text('Anmeldename oder Gruppenpasswort falsch.'),
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
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);
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

  testWidgets('bei fünf Gruppen verschwindet das Anlegen', (tester) async {
    final backend = FakeBackend();
    backend.adminAccounts[_adminEmail] = FakeAdminAccount(
      password: _adminPassword,
    );
    for (var i = 0; i < 5; i++) {
      backend.createGroupForAdmin(
        adminEmail: _adminEmail,
        handle: 'gruppe$i',
        password: 'gruppe-geheim-$i',
        groupName: 'Gruppe $i',
      );
    }

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    expect(find.textContaining('5 von 5'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Gruppe anlegen'),
      findsNothing,
      reason: 'Wer den Deckel erreicht hat, sieht das Formular nicht mehr.',
    );
    expect(find.textContaining('höchstmöglichen'), findsOneWidget);
    expect(
      () => backend.createGroupForAdmin(
        adminEmail: _adminEmail,
        handle: 'sechste',
        password: 'gruppe-geheim-6',
        groupName: 'Sechste',
      ),
      throwsA(isA<GroupLimitReached>()),
      reason: 'Ein Deckel nur im UI wäre kein Deckel — der Server hält ihn.',
    );
  });

  testWidgets('jede Aktion trifft genau ihre Gruppe', (tester) async {
    final backend = FakeBackend();
    backend.adminAccounts[_adminEmail] = FakeAdminAccount(
      password: _adminPassword,
    );
    backend.createGroupForAdmin(
      adminEmail: _adminEmail,
      handle: 'erste',
      password: 'erste-geheim-1',
      groupName: 'Erste Gruppe',
    );
    backend.createGroupForAdmin(
      adminEmail: _adminEmail,
      handle: 'zweite',
      password: 'zweite-geheim-1',
      groupName: 'Zweite Gruppe',
    );

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    // Die Karte der zweiten Gruppe finden und dort das Passwort neu setzen.
    final secondCard = find.ancestor(
      of: find.text('Verwaltet: zweite'),
      matching: find.byType(Card),
    );
    await _tap(
      tester,
      find.descendant(
        of: secondCard,
        matching: find.widgetWithText(
          FilledButton,
          'Gruppenpasswort neu '
          'setzen',
        ),
      ),
    );
    await _fill(tester, 'Neues Gruppenpasswort', 'frisch-gesetzt-2');
    await _fill(tester, 'Wiederholen', 'frisch-gesetzt-2');
    await _tap(tester, find.widgetWithText(FilledButton, 'Neu setzen'));

    expect(
      backend.accounts['zweite@grp.fahrgemeinschaft.app']!.password,
      'frisch-gesetzt-2',
    );
    expect(
      backend.accounts['erste@grp.fahrgemeinschaft.app']!.password,
      'erste-geheim-1',
      reason: 'Die andere Gruppe des Kontos bleibt unberührt.',
    );
  });

  testWidgets('die Rettungsleine setzt das Gruppenpasswort wirklich neu', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'Gruppenpasswort neu setzen'),
    );
    await _fill(tester, 'Neues Gruppenpasswort', 'frisch-gesetzt-1');
    await _fill(tester, 'Wiederholen', 'frisch-gesetzt-1');
    await _tap(tester, find.widgetWithText(FilledButton, 'Neu setzen'));

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

  testWidgets('Übergabe: Verknüpfung lösen gibt die Gruppe frei', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(
      tester,
      find.widgetWithText(FilledButton, 'Verknüpfung lösen …'),
    );
    await _fill(tester, 'Dein Admin-Passwort', 'falsches-passwort');
    await _tap(tester, find.widgetWithText(FilledButton, 'Lösen'));
    expect(
      find.text('Das Admin-Passwort stimmt nicht.'),
      findsOneWidget,
      reason: 'Ohne Sudo-Beweis bleibt die Verknüpfung bestehen.',
    );

    await _fill(tester, 'Dein Admin-Passwort', _adminPassword);
    await _tap(tester, find.widgetWithText(FilledButton, 'Lösen'));

    expect(
      find.text('Gruppe verknüpfen'),
      findsOneWidget,
      reason: 'Nach dem Lösen zeigt die Konsole wieder das Übernehmen an.',
    );
    expect(backend.adminAccounts[_adminEmail]!.groupIds, isEmpty);
    expect(
      backend.groups,
      hasLength(1),
      reason: 'Lösen ist eine Übergabe — die Gruppendaten bleiben unberührt.',
    );
    expect(
      logRing.lines.join('\n'),
      isNot(contains(_adminPassword)),
      reason: 'Ein Passwort darf nie im Protokoll landen.',
    );
  });

  testWidgets('E-Mail ändern geht den Doppelbestätigungs-Weg', (tester) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.text('E-Mail-Adresse ändern'));
    await _fill(tester, 'Neue E-Mail-Adresse', 'neu@example.org');
    await _tap(tester, find.widgetWithText(FilledButton, 'Ändern'));

    expect(
      backend.emailChangeRequests,
      ['neu@example.org'],
      reason: 'Der Wechsel wurde wirklich angefordert.',
    );
    expect(
      find.textContaining('alte und die neue Adresse'),
      findsOneWidget,
      reason:
          'Die Meldung erklärt, dass erst beide Links den Wechsel gelten '
          'lassen — sonst wundert man sich, warum nichts passiert.',
    );
  });

  testWidgets('Löschen scheitert folgenlos an falscher Sudo-Eingabe', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Gruppe löschen …'));
    await _fill(tester, 'Dein Admin-Passwort', 'falsch');
    await _fill(tester, 'Zur Bestätigung: daciaracing', 'daciaracing');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(find.text('Das Admin-Passwort stimmt nicht.'), findsOneWidget);
    expect(backend.groups, hasLength(1), reason: 'Nichts wurde gelöscht.');

    await _fill(tester, 'Dein Admin-Passwort', _adminPassword);
    await _fill(tester, 'Zur Bestätigung: daciaracing', 'daciaracin');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(find.textContaining('stimmt nicht mit'), findsOneWidget);
    expect(backend.groups, hasLength(1));
  });

  // „Passwort vergessen" hat eine eigene Datei: console_reset_flow_test.dart.

  testWidgets('unbestätigtes Konto: Anmelden erklärt es, Resend geht', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts['frisch@example.org'] = FakeAdminAccount(
      password: 'frisch-geheim-1',
      confirmed: false,
    );
    await pumpApp(tester, backend, splash: false);
    await _openConsoleLogin(tester);

    await tester.enterText(find.byType(TextField).first, 'frisch@example.org');
    await tester.enterText(find.byType(TextField).last, 'frisch-geheim-1');
    await _tap(tester, find.widgetWithText(FilledButton, 'Anmelden'));

    expect(
      find.textContaining('noch nicht bestätigt'),
      findsOneWidget,
      reason:
          'Ein unbestätigtes Konto ist kein „Passwort falsch" — die '
          'Nutzerin muss wissen, dass die Mail der nächste Schritt ist.',
    );
    expect(
      find.widgetWithText(TextField, 'Code aus der Mail'),
      findsOneWidget,
      reason:
          'Und sie landet direkt in der Code-Eingabe, statt den nächsten '
          'Schritt selbst suchen zu müssen.',
    );

    await _tap(tester, find.text('Bestätigungs-Mail erneut senden'));
    expect(
      backend.confirmationResends,
      ['frisch@example.org'],
      reason: 'Der Resend wurde wirklich angefordert.',
    );
    expect(find.textContaining('neuer Code unterwegs'), findsOneWidget);
  });

  testWidgets('das Auge macht das Passwort sichtbar', (tester) async {
    await pumpApp(tester, _backend(), splash: false);
    await _openConsoleLogin(tester);

    TextField password() =>
        tester.widget<TextField>(find.byType(TextField).last);
    expect(password().obscureText, isTrue);

    await _tap(tester, find.byTooltip('Passwort anzeigen'));
    expect(password().obscureText, isFalse);

    await _tap(tester, find.byTooltip('Passwort verbergen'));
    expect(password().obscureText, isTrue);
  });

  testWidgets('Registrieren verlangt die passende Wiederholung', (
    tester,
  ) async {
    final backend = _backend();
    await pumpApp(tester, backend, splash: false);
    await _openConsoleLogin(tester);

    await _tap(tester, find.text('Registrieren'));
    expect(
      find.byType(TextField),
      findsNWidgets(3),
      reason:
          'Registrieren fragt das Passwort doppelt ab — ein Tippfehler '
          'sperrte sonst das frische Konto sofort aus.',
    );

    await tester.enterText(find.byType(TextField).at(0), 'neu@example.org');
    await tester.enterText(find.byType(TextField).at(1), 'ganz-geheim-12');
    await tester.enterText(find.byType(TextField).at(2), 'ganz-geheim-21');
    await _tap(tester, find.widgetWithText(FilledButton, 'Registrieren'));

    expect(find.text('Die Passwörter stimmen nicht überein.'), findsOneWidget);
    expect(
      backend.adminAccounts.containsKey('neu@example.org'),
      isFalse,
      reason: 'Bei abweichender Wiederholung entsteht kein Konto.',
    );

    await tester.enterText(find.byType(TextField).at(2), 'ganz-geheim-12');
    await _tap(tester, find.widgetWithText(FilledButton, 'Registrieren'));

    expect(find.textContaining('Code an neu@example.org'), findsOneWidget);
    expect(backend.adminAccounts.containsKey('neu@example.org'), isTrue);
  });

  testWidgets('korrektes Löschen entfernt die Gruppe, nicht das Konto', (
    tester,
  ) async {
    final backend = _backend();
    backend.adminAccounts[_adminEmail]!.groupIds.add(backend.groups.keys.first);

    await pumpApp(tester, backend, splash: false);
    await _signInToConsole(tester);

    await _tap(tester, find.widgetWithText(FilledButton, 'Gruppe löschen …'));
    await _fill(tester, 'Dein Admin-Passwort', _adminPassword);
    await _fill(tester, 'Zur Bestätigung: daciaracing', 'daciaracing');
    await _tap(tester, find.widgetWithText(FilledButton, 'Endgültig löschen'));

    expect(backend.groups, isEmpty);
    expect(backend.accounts, isEmpty);
    expect(
      backend.adminAccounts.containsKey(_adminEmail),
      isTrue,
      reason:
          'Das Verwalter-Konto überlebt: Es trägt womöglich weitere Gruppen, '
          'und ein Selbst-Löschen wäre Datenverlust an denen.',
    );
    expect(
      find.byType(ConsoleScreen),
      findsOneWidget,
      reason: 'Man bleibt angemeldet und sieht die (nun leere) Liste.',
    );
    expect(find.textContaining('Noch keine'), findsOneWidget);
    expect(
      logRing.lines.join('\n'),
      isNot(contains(_adminPassword)),
      reason: 'Das Admin-Passwort darf nie im Protokoll landen.',
    );
  });
}

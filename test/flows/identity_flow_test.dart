/// identity_flow_test.dart – „Wer bin ich?" über die echte App (#121).
///
/// Die Zuordnung ist **kein Login**: Jeder kann jeden wählen und die Auswahl
/// jederzeit ändern. Sie schützt vor Vertippern, nicht vor Menschen — was hier
/// geprüft wird, ist Bedienung, nicht Sicherheit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

class _Fixture {
  const _Fixture(this.backend, this.anna);
  final FakeBackend backend;
  final String anna;
}

Future<_Fixture> _backend() async {
  final backend = FakeBackend();
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(groupId);
  final anna = await data.createPerson(
    const Person(id: '', name: 'Anna', active: true),
  );
  await data.createPerson(const Person(id: '', name: 'Ben', active: true));
  await data.createPerson(const Person(id: '', name: 'Alt', active: false));
  return _Fixture(backend, anna.id);
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
}

/// Im Dialog tippen — Namen stehen auch im Ranking dahinter.
Future<void> _pickInDialog(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('beim ersten Start wird gefragt, wer man ist', (tester) async {
    final f = await _backend();
    await pumpApp(tester, f.backend, identity: DeviceIdentity.unknown);
    await _login(tester);

    expect(find.text('Wer bist du?'), findsOneWidget);
    expect(find.text('Später'), findsOneWidget);
    expect(
      find.text('Niemand ausgewählt'),
      findsNothing,
      reason:
          'Vor der ersten Frage mahnt der Dialog, nicht zusätzlich das '
          'Banner dahinter — zwei Mahner sind einer zu viel.',
    );

    await _pickInDialog(tester, 'Anna');

    expect(find.text('Wer bist du?'), findsNothing);
    // Der Menüpunkt sagt den Stand, ohne dass man hineingehen muss.
    await _openMenu(tester);
    expect(find.text('Anna'), findsWidgets);
  });

  testWidgets('inaktive Personen stehen nicht zur Auswahl', (tester) async {
    final f = await _backend();
    await pumpApp(tester, f.backend, identity: DeviceIdentity.unknown);
    await _login(tester);

    expect(find.text('Anna'), findsWidgets);
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Alt')),
      findsNothing,
      reason:
          'Wer inaktiv ist, fährt nicht mit — er kann auch nicht der sein, '
          'der hier sitzt.',
    );
  });

  // Zwei Mahner sind einer zu viel: Was bei jedem Start aufpoppt, klickt man
  // blind weg. Erinnert wird über das Banner, an genau einer Stelle.
  testWidgets('„Später" fragt nicht wieder, sondern zeigt das Banner', (
    tester,
  ) async {
    final f = await _backend();
    await pumpApp(tester, f.backend, identity: DeviceIdentity.unknown);
    await _login(tester);

    await tester.tap(find.text('Später'));
    await tester.pumpAndSettle();

    expect(find.text('Wer bist du?'), findsNothing);
    expect(find.text('Niemand ausgewählt'), findsOneWidget);
  });

  testWidgets(
    'wer schon gewählt hat, wird nicht gefragt und sieht kein Banner',
    (tester) async {
      final f = await _backend();
      await pumpApp(
        tester,
        f.backend,
        identity: DeviceIdentity(personId: f.anna, asked: true),
      );
      await _login(tester);

      expect(find.text('Wer bist du?'), findsNothing);
      expect(find.text('Niemand ausgewählt'), findsNothing);
    },
  );

  testWidgets('das Banner führt angetippt zur Auswahl und verschwindet dann', (
    tester,
  ) async {
    final f = await _backend();
    await pumpApp(tester, f.backend, identity: DeviceIdentity.skipped);
    await _login(tester);

    expect(find.text('Niemand ausgewählt'), findsOneWidget);

    // Tippen, nicht nur finden — ein sichtbarer Hinweis, der nirgendwo
    // hinführt, ist die Klasse Fehler des toten Update-Knopfs aus 0.37.0.
    await tester.tap(find.text('Niemand ausgewählt'));
    await tester.pumpAndSettle();
    await _pickInDialog(tester, 'Anna');

    expect(find.text('Niemand ausgewählt'), findsNothing);
  });

  testWidgets('die Auswahl lässt sich im Menü ändern', (tester) async {
    final f = await _backend();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);

    await _openMenu(tester);
    await tester.tap(find.text('Ich bin'));
    await tester.pumpAndSettle();
    await _pickInDialog(tester, 'Ben');

    await _openMenu(tester);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Ich bin'),
        matching: find.text('Ben'),
      ),
      findsOneWidget,
      reason:
          'Pärchen tragen füreinander ein — der Wechsel muss ohne Umweg über '
          'ein Untermenü gehen.',
    );
  });

  // Ohne Auswahl gibt es niemanden, für den man etwas einstellen könnte.
  // Versteckt bliebe unerklärt, warum der Punkt fehlt.
  testWidgets('ohne Auswahl ist „Benachrichtigungen" ausgegraut', (
    tester,
  ) async {
    final f = await _backend();
    await pumpApp(tester, f.backend, identity: DeviceIdentity.skipped);
    await _login(tester);
    await _openMenu(tester);

    expect(find.text('Erst festlegen, wer du bist'), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Benachrichtigungen'),
          )
          .enabled,
      isFalse,
    );
  });

  testWidgets('mit Auswahl ist „Benachrichtigungen" offen', (tester) async {
    final f = await _backend();
    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity(personId: f.anna, asked: true),
    );
    await _login(tester);
    await _openMenu(tester);

    expect(find.text('Erst festlegen, wer du bist'), findsNothing);
    expect(
      tester
          .widget<PopupMenuItem<String>>(
            find.widgetWithText(PopupMenuItem<String>, 'Benachrichtigungen'),
          )
          .enabled,
      isTrue,
    );
  });

  // Wer heute schon Push nutzt, hat die Frage längst beantwortet. Ohne diesen
  // Griff fragte die App die halbe Gruppe nach etwas, das sie schon gesagt hat.
  testWidgets('eine vorhandene Push-Zuordnung wird übernommen, nicht erfragt', (
    tester,
  ) async {
    final f = await _backend();
    final push = FakePushRepository(f.backend);
    // Die Zeile gehört der Gruppe (`register` merkt sich `currentGroupId`) —
    // ohne angemeldete Gruppe landete sie im Niemandsland und die
    // Mandantenprüfung in `stateFor` fände sie zu Recht nicht. Das ist
    // zugleich die Anmeldung, deshalb entfällt hier der Login-Schritt.
    f.backend.setCurrentEmail('daciaracing@grp.fahrgemeinschaft.app');
    await push.register(
      token: 'test-token',
      personId: f.anna,
      platform: 'android',
    );

    await pumpApp(
      tester,
      f.backend,
      identity: DeviceIdentity.unknown,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Wer bist du?'),
      findsNothing,
      reason: 'Die Antwort steht schon in push_devices.',
    );
    expect(find.text('Niemand ausgewählt'), findsNothing);
    await _openMenu(tester);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Ich bin'),
        matching: find.text('Anna'),
      ),
      findsOneWidget,
    );
  });
}

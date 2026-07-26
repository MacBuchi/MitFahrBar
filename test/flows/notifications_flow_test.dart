/// notifications_flow_test.dart – Benachrichtigungen einrichten (Issue #101).
///
/// Der eigentliche Inhalt ist die Zuordnung Gerät → Person: Sie ist bewusst
/// **kein** Login (jeder kann jeden wählen), muss aber trotzdem an der Gruppe
/// hängen — sonst bekäme ein Gerät nach einem Gruppenwechsel weiter die
/// Nachrichten der alten Gruppe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<FakeBackend> _backend() async {
  final backend = FakeBackend();
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(groupId);
  await data.createPerson(const Person(id: '', name: 'Anna', active: true));
  await data.createPerson(const Person(id: '', name: 'Ben', active: true));
  await data.createPerson(const Person(id: '', name: 'Alt', active: false));
  return backend;
}

Future<void> _login(
  WidgetTester tester, {
  String handle = 'daciaracing',
}) async {
  await tester.enterText(find.byType(TextField).first, handle);
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Benachrichtigungen'));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.byType(DropdownButtonFormField<String?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('wer sich zuordnet, bekommt die Vorbelegung angelegt', (
    tester,
  ) async {
    final backend = await _backend();
    final push = FakePushRepository(backend);
    await pumpApp(
      tester,
      backend,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);

    // Vorher gibt es nichts — keine Zeile heißt keine Benachrichtigungen.
    expect(push.prefs, isEmpty);
    expect(find.text('Abends der Blick auf morgen'), findsNothing);

    await _choose(tester, 'Anna');

    expect(push.prefs, hasLength(1));
    final prefs = push.prefs.values.single;
    expect(prefs.eveningTime.format(), '21:00');
    expect(prefs.departureTime.format(), '07:30');
    expect(prefs.eveningEnabled, isTrue);
    expect(find.text('Abends der Blick auf morgen'), findsOneWidget);
  });

  testWidgets('inaktive Personen stehen nicht zur Auswahl', (tester) async {
    final backend = await _backend();
    await pumpApp(tester, backend);
    await _login(tester);
    await _open(tester);

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    expect(find.text('Anna'), findsWidgets);
    expect(
      find.text('Alt'),
      findsNothing,
      reason:
          'Wer inaktiv ist, fährt nicht mit — eine Zustellung an ihn wäre '
          'Lärm, und der Planer kennt ihn ohnehin nicht mehr.',
    );
  });

  testWidgets('ein Schalter landet sofort in den Einstellungen', (
    tester,
  ) async {
    final backend = await _backend();
    final push = FakePushRepository(backend);
    await pumpApp(
      tester,
      backend,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _choose(tester, 'Anna');

    await tester.tap(find.text('Änderungen bis zur Abfahrt'));
    await tester.pumpAndSettle();

    expect(push.prefs.values.single.changesEnabled, isFalse);
  });

  testWidgets('„niemand" nimmt das Gerät aus der Zustellung', (tester) async {
    final backend = await _backend();
    final push = FakePushRepository(backend);
    await pumpApp(
      tester,
      backend,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _choose(tester, 'Anna');
    await _choose(tester, 'niemand');

    expect(push.devices['test-token']?.$2, isNull);
    expect(find.text('Abends der Blick auf morgen'), findsNothing);
    expect(
      push.prefs,
      hasLength(1),
      reason:
          'Die Einstellungen der Person bleiben stehen — ein zweites Gerät '
          'derselben Person soll nicht mit abgeschaltet werden.',
    );
  });

  testWidgets('die Test-Benachrichtigung geht an dieses Gerät', (tester) async {
    final backend = await _backend();
    final push = FakePushRepository(backend);
    await pumpApp(
      tester,
      backend,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _choose(tester, 'Anna');

    // Der Knopf steht unten in der Liste: Was nicht im Blickfeld ist, baut
    // die ListView gar nicht erst — vor dem Tippen also hinscrollen.
    await tester.scrollUntilVisible(
      find.text('Test-Benachrichtigung senden'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test-Benachrichtigung senden'));
    await tester.pumpAndSettle();

    expect(push.tests, ['test-token']);
  });

  testWidgets('ohne Berechtigung bleibt der Screen leer statt kaputt', (
    tester,
  ) async {
    final backend = await _backend();
    await pumpApp(
      tester,
      backend,
      overrides: [
        // Kein Token = abgelehnt oder nicht unterstützt.
        pushTokenProvider.overrideWithValue(
          ({required bool ask}) async => null,
        ),
      ],
    );
    await _login(tester);
    await _open(tester);

    expect(find.text('Abends der Blick auf morgen'), findsNothing);
    expect(
      find.byType(DropdownButtonFormField<String?>),
      findsOneWidget,
      reason:
          'Die Auswahl bleibt bedienbar: Erst beim Zuordnen wird gefragt — '
          'ein Screen, der ohne Berechtigung gar nichts zeigt, führt in die '
          'Sackgasse.',
    );
  });

  testWidgets('ein Gerät der einen Gruppe zeigt in der anderen nichts', (
    tester,
  ) async {
    final backend = await _backend();
    final push = FakePushRepository(backend);
    backend.addGroup(
      handle: 'andere',
      password: 'geheim123',
      name: 'Andere Gruppe',
    );
    await pumpApp(
      tester,
      backend,
      overrides: [pushRepositoryProvider.overrideWithValue(push)],
    );
    await _login(tester);
    await _open(tester);
    await _choose(tester, 'Anna');
    expect(push.devices['test-token']?.$2, isNotNull);

    // Dasselbe Gerät, dasselbe Token, andere Gruppe angemeldet. Geprüft wird
    // hier bewusst am Repository statt über einen zweiten Login-Durchlauf:
    // An- und Abmelden hat mit auth_flow_test.dart einen eigenen Test, und
    // der Inhalt dieses hier ist die Mandantengrenze.
    backend.setCurrentEmail('andere@grp.fahrgemeinschaft.app');
    await tester.pumpAndSettle();

    expect(
      (await push.stateFor('test-token')).personId,
      isNull,
      reason:
          'Die Zuordnung gehört der Gruppe. Sähe die zweite Gruppe sie, '
          'liefe sie beim Zuordnen in eine Unique-Verletzung auf einer '
          'Zeile, die die RLS ihr nicht einmal zeigen darf.',
    );
  });
}

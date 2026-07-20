/// persons_flow_test.dart – Personen anlegen und stilllegen, echte App.
library;

import 'package:fahrgemeinschaft/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

FakeBackend _backend() {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  backend
      .dataFor(id)
      .createPerson(const Person(id: '', name: 'Anna', active: true));
  return backend;
}

Future<void> _openPersons(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Zugang'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Personen verwalten'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('eine neue Person anlegen und in der Liste sehen', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Bernd'), findsNothing);

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Person anlegen'),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Bernd');
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    // Ohne ref.invalidate(personsProvider) bliebe die Liste hier auf dem
    // Stand vom Login stehen — der Speichern-Vorgang sähe aus, als wäre er
    // fehlgeschlagen.
    expect(
      find.text('Bernd'),
      findsOneWidget,
      reason: 'Die angelegte Person muss ohne Neuanmeldung erscheinen.',
    );
  });

  testWidgets('ohne Namen wird nicht angelegt', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Person anlegen'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    expect(find.text('Ein Name wird gebraucht.'), findsOneWidget);
    expect(
      find.byType(AlertDialog),
      findsOneWidget,
      reason: 'Der Dialog bleibt offen, damit die Eingabe nachgeholt wird.',
    );
  });

  // Löschen gibt es bewusst nicht: person_id in trip_participations hängt an
  // ON DELETE CASCADE, ein Löschen würde also die Teilnahmen und damit die
  // Punkte aller anderen rückwirkend verändern. Stilllegen ist der Ersatz.
  testWidgets('stillgelegte Person verschwindet aus „Wer ist dran"', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);

    expect(find.text('Anna'), findsWidgets);

    await _openPersons(tester);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    // Nicht tester.pageBack(): das sucht den Tooltip „Back", die App läuft
    // aber auf Deutsch.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      find.text('Anna'),
      findsNothing,
      reason: 'Inaktive Personen gehören nicht mehr in die Rangliste.',
    );
  });
}

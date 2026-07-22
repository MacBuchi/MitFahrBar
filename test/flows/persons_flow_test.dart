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
    // Bewusst kein schwebender Knopf: Der überdeckte die unterste Person
    // (Handy-Fund 2026-07-22) — „Person anlegen" steht unter der Liste.
    expect(find.byType(FloatingActionButton), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Person anlegen'));
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

  // Die Sitzplätze zählen inklusive Fahrer — steht so an der Beschriftung,
  // sonst trägt der eine die Zahl aus dem Fahrzeugschein ein und der andere
  // zieht sich selbst ab.
  testWidgets('Sitzplätze lassen sich pflegen und stehen in der Liste', (
    tester,
  ) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Person anlegen'));
    await tester.pumpAndSettle();
    expect(find.text('Sitzplätze inkl. Fahrer'), findsOneWidget);

    // Das Feld ist mit der Vorgabe befüllt — sonst wüsste niemand, was gilt.
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller?.text,
      '5',
    );

    await tester.enterText(find.byType(TextField).first, 'Bernd');
    await tester.enterText(find.byType(TextField).last, '7');
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('7 Sitze'), findsOneWidget);
  });

  // Vorgabe 5 = Fahrer + 4, der normale PKW. Damit greift die Prüfung vom
  // ersten Tag an, ohne dass jemand etwas pflegen muss.
  testWidgets('ohne Angabe gilt der normale PKW mit 5 Sitzen', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Person anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Bernd');
    await tester.enterText(find.byType(TextField).last, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 Sitze'), findsWidgets);
  });

  testWidgets('ein Einsitzer wird abgelehnt', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Person anlegen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Bernd');
    await tester.enterText(find.byType(TextField).last, '1');
    await tester.tap(find.widgetWithText(FilledButton, 'Anlegen'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sitzplätze bitte als ganze Zahl ab 2.'),
      findsOneWidget,
      reason: 'Ein Einsitzer kann keine Fahrgemeinschaft fahren.',
    );
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('ohne Namen wird nicht angelegt', (tester) async {
    await pumpApp(tester, _backend());
    await _login(tester);
    await _openPersons(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Person anlegen'));
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

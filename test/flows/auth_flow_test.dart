/// auth_flow_test.dart – Anmeldung, Status-Gate und Mandantentrennung.
library;

import 'package:mitfahrbar/models/group.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

void main() {
  testWidgets('Anmeldung führt von der Login-Maske in die App', (tester) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    await backend
        .dataFor(groupId)
        .createPerson(const Person(id: '', name: 'Anna', active: true));

    await pumpApp(tester, backend);

    // Ohne Anmeldung ist nur die Login-Maske sichtbar.
    expect(find.text('Anmelden'), findsOneWidget);
    expect(find.text('Übersicht'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'daciaracing');
    await tester.enterText(find.byType(TextField).last, 'geheim123');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();

    // Nach der Anmeldung ist die App mit ihren Tabs da.
    expect(find.text('Dacia Racing'), findsWidgets);
    expect(find.text('Wer ist dran?'), findsOneWidget);
  });

  testWidgets('falsches Passwort meldet Fehler und lässt nicht durch', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );

    await pumpApp(tester, backend);
    await tester.enterText(find.byType(TextField).first, 'daciaracing');
    await tester.enterText(find.byType(TextField).last, 'falsch');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Anmeldung fehlgeschlagen'), findsOneWidget);
    expect(find.text('Wer ist dran?'), findsNothing);
  });

  testWidgets('eine nicht aktive Gruppe kommt nicht in die App', (
    tester,
  ) async {
    final backend = FakeBackend()
      ..addGroup(
        handle: 'neugruppe',
        password: 'geheim123',
        name: 'Neue Gruppe',
        status: GroupStatus.pending,
      );

    await pumpApp(tester, backend);
    await tester.enterText(find.byType(TextField).first, 'neugruppe');
    await tester.enterText(find.byType(TextField).last, 'geheim123');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();

    // Seit #108 gibt es keine Freigabe mehr: 'pending' heißt „nie in Gebrauch
    // genommen" (Fremd-Signup gegen die Gruppen-Domain), nicht „wartet".
    expect(find.text('Nicht in Gebrauch'), findsOneWidget);
    expect(find.textContaining('Verwalter-Konsole'), findsOneWidget);
    // Kein Zugriff auf die App-Inhalte.
    expect(find.text('Wer ist dran?'), findsNothing);
    expect(find.text('Übersicht'), findsNothing);
  });

  testWidgets(
    'ein stillgelegter Status wird erklärt, nicht als Fehler gezeigt',
    (tester) async {
      // Der Beweis für Invariante 2 auf UI-Ebene: Der Server darf einen Zustand
      // setzen, den diese Fassung nicht kennt. `Group.statusFrom` liest ihn als
      // `archived`, und dieser Zweig hat eine Erklärung. Ohne beides sähe die
      // Nutzerin „Fehler: Invalid argument" — und der Sperr-Schirm greift
      // bewusst nie, solange es kein installierbares Update gibt. Damit wäre
      // jede künftige Statusänderung ein Release-Zwang.
      final backend = FakeBackend()
        ..addGroup(
          handle: 'stillgelegt',
          password: 'geheim123',
          name: 'Alte Gruppe',
          status: GroupStatus.archived,
        );

      await pumpApp(tester, backend);
      await tester.enterText(find.byType(TextField).first, 'stillgelegt');
      await tester.enterText(find.byType(TextField).last, 'geheim123');
      await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
      await tester.pumpAndSettle();

      expect(find.text('Gruppe stillgelegt'), findsOneWidget);
      expect(find.textContaining('Fehler'), findsNothing);
      expect(find.text('Wer ist dran?'), findsNothing);
    },
  );

  testWidgets('Gruppen sehen die Daten anderer Gruppen nicht', (tester) async {
    final backend = FakeBackend();
    final aId = backend.addGroup(
      handle: 'gruppe-a',
      password: 'geheim123',
      name: 'Gruppe A',
    );
    final bId = backend.addGroup(
      handle: 'gruppe-b',
      password: 'geheim123',
      name: 'Gruppe B',
    );

    await backend
        .dataFor(aId)
        .createPerson(const Person(id: '', name: 'Anna aus A', active: true));
    await backend
        .dataFor(bId)
        .createPerson(const Person(id: '', name: 'Bert aus B', active: true));

    await pumpApp(tester, backend);
    await tester.enterText(find.byType(TextField).first, 'gruppe-a');
    await tester.enterText(find.byType(TextField).last, 'geheim123');
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();

    expect(find.text('Anna aus A'), findsWidgets);
    expect(find.text('Bert aus B'), findsNothing);
  });
}

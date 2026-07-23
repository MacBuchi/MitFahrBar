/// history_flow_test.dart – Solo-Fahrten in der Historie (Issue #61).
library;

import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
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

void main() {
  testWidgets('eine Solo-Fahrt steht blass da und sagt, dass sie nicht zählt', (
    tester,
  ) async {
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
    final bert = await data.createPerson(
      const Person(id: '', name: 'Bert', active: true),
    );
    await data.createTrip(DateTime(2026, 3, 2), {
      anna.id: ParticipationStatus.driver,
      bert.id: ParticipationStatus.passenger,
    });
    await data.createTrip(DateTime(2026, 3, 3), {
      anna.id: ParticipationStatus.driver,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(find.text('Historie'));
    await tester.pumpAndSettle();

    expect(find.textContaining('allein gefahren, zählt nicht'), findsOneWidget);

    // Die normale Fahrt trägt den Hinweis nicht — und die Solo-Fahrt bleibt
    // antippbar, vielleicht fehlt ja nur ein vergessener Mitfahrer.
    expect(find.textContaining('Mit: Bert'), findsOneWidget);
    await tester.tap(find.textContaining('allein gefahren'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Speichern'),
      findsOneWidget,
      reason: 'Antippen führt weiter in die Bearbeitung.',
    );
  });

  testWidgets('die Punkte ignorieren die Solo-Fahrt', (tester) async {
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
    await data.createPerson(const Person(id: '', name: 'Bert', active: true));
    await data.createTrip(DateTime(2026, 3, 3), {
      anna.id: ParticipationStatus.driver,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    // Nur eine Solo-Fahrt in der Historie: Auf der Übersicht bleibt alles
    // ausgeglichen, niemand hat Punkte gesammelt.
    expect(find.textContaining('gut'), findsNothing);
    expect(find.textContaining('schuldet'), findsNothing);
  });
}

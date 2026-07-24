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

  // Issue #62: Fahren an einem Tag mehrere Autos, hat jede Fahrt ihre
  // Zeile — ab der zweiten mit der Marke „2. Auto", damit die Liste nicht
  // wie ein Doppel-Eintrag aussieht. Die Nummer ist die Position in der
  // Liste, keine Aussage über die Abfahrtsfolge.
  testWidgets('die zweite Fahrt eines Tages trägt die Marke „2. Auto"', (
    tester,
  ) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(groupId);
    final ids = <String, String>{};
    for (final name in ['Anna', 'Bert', 'Clara', 'Dora']) {
      final p = await data.createPerson(
        Person(id: '', name: name, active: true),
      );
      ids[name] = p.id;
    }
    // Ein normaler Tag davor und ein 2-Auto-Tag.
    await data.createTrip(DateTime(2026, 3, 2), {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });
    await data.createTrip(DateTime(2026, 3, 3), {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });
    await data.createTrip(DateTime(2026, 3, 3), {
      ids['Clara']!: ParticipationStatus.driver,
      ids['Dora']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(find.text('Historie'));
    await tester.pumpAndSettle();

    expect(
      find.text('2. Auto'),
      findsOneWidget,
      reason:
          'Genau die zweite Fahrt des 3.3. trägt die Marke — die erste des '
          'Tages und die Einzelfahrt vom 2.3. bleiben ohne.',
    );
  });
}

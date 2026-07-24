/// dashboard_charts_flow_test.dart – Die Auswertungen auf der Startseite.
library;

import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
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

String _setUpGroup(FakeBackend backend) => backend.addGroup(
  handle: 'daciaracing',
  password: 'geheim123',
  name: 'Dacia Racing',
);

/// Hohe Testfläche: Die ListView baut nur, was sichtbar ist – auf der
/// Standardgröße läge die Hälfte der Karten unter der Kante, und ein
/// `findsNothing` wäre dann auch dann erfüllt, wenn die Karte existiert.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('mit Fahrten zeigt die Startseite die Auswertungen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    final data = backend.dataFor(groupId);

    final ids = <String>[];
    for (final name in ['Anna', 'Bert']) {
      final person = await data.createPerson(
        Person(id: '', name: name, active: true),
      );
      ids.add(person.id);
    }
    await data.createTrip(DateTime.now(), {
      ids[0]: ParticipationStatus.driver,
      ids[1]: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.text('Gemeinsam erreicht'), findsOneWidget);
    expect(find.text('Fahrten pro Monat'), findsOneWidget);
    expect(find.text('Wie ihr unterwegs seid'), findsOneWidget);
    // Die Legende benennt die Kategorien – Farbe allein trägt die Zuordnung
    // nie allein.
    expect(find.text('gefahren'), findsOneWidget);
    expect(find.text('mitgefahren'), findsOneWidget);
    expect(find.text('1-way'), findsOneWidget);
  });

  testWidgets('ohne Fahrten bleiben die Diagramme aus', (tester) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    await backend
        .dataFor(groupId)
        .createPerson(const Person(id: '', name: 'Anna', active: true));

    await pumpApp(tester, backend);
    await _login(tester);

    // Eine leere Achse sagt weniger als gar keine Karte.
    expect(find.text('Fahrten pro Monat'), findsNothing);
    expect(find.text('Wie ihr unterwegs seid'), findsNothing);
  });
}

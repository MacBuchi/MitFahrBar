/// trip_entry_flow_test.dart – Fahrt über die Kachel-Maske eintragen.
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

void main() {
  testWidgets(
    'Fahrt eintragen: Kacheln wählen, Fahrer wird gesetzt, speichern',
    (tester) async {
      final backend = FakeBackend();
      final groupId = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(groupId);
      for (final name in ['Anna', 'Bert', 'Clara']) {
        await data.createPerson(Person(id: '', name: name, active: true));
      }

      await pumpApp(tester, backend);
      await _login(tester);

      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
      );
      await tester.pumpAndSettle();

      // Ohne Auswahl ist Speichern gesperrt.
      expect(find.text('Mindestens 1 Person auswählen'), findsOneWidget);

      // Zwei Teilnehmer auswählen.
      await tester.tap(find.text('Anna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bert'));
      await tester.pumpAndSettle();

      // Die App hat automatisch einen Fahrer gesetzt.
      expect(find.text('Fahrer'), findsOneWidget);
      expect(find.textContaining('Speichern –'), findsOneWidget);

      await tester.tap(find.textContaining('Speichern –'));
      await tester.pumpAndSettle();

      // Die Fahrt ist gespeichert.
      final trips = await data.loadTrips();
      expect(trips, hasLength(1));
      expect(trips.single.participations, hasLength(2));
      expect(trips.single.driverId, isNotNull);
    },
  );

  testWidgets('zweiter Tap macht aus „dabei" eine 1-way-Fahrt', (tester) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(groupId);
    for (final name in ['Anna', 'Bert']) {
      await data.createPerson(Person(id: '', name: name, active: true));
    }

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anna')); // dabei (Fahrer)
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bert')); // dabei
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bert')); // -> 1-way
    await tester.pumpAndSettle();

    expect(find.text('1-way'), findsOneWidget);

    await tester.tap(find.textContaining('Speichern –'));
    await tester.pumpAndSettle();

    final trip = (await data.loadTrips()).single;
    expect(
      trip.participations.values.where((s) => s.name == 'oneWay'),
      hasLength(1),
    );
  });
}

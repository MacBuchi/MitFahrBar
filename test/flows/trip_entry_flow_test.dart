/// trip_entry_flow_test.dart – Fahrt über die Kachel-Maske eintragen.
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

  // Je länger eine Gruppe existiert, desto mehr Namen sammeln sich an, die
  // niemand mehr antippt. Rein alphabetisch stehen die mitten zwischen den
  // Stammgästen und man sucht sich jeden Abend neu zurecht.
  testWidgets('wer lange nicht dabei war, rutscht nach unten', (tester) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(groupId);
    for (final name in ['Anna', 'Bert', 'Zora']) {
      await data.createPerson(Person(id: '', name: name, active: true));
    }
    final persons = {for (final p in await data.loadPersons()) p.name: p.id};
    final today = DateTime.now();

    // Zora war zuletzt vor über einem halben Jahr dabei, Anna und Bert
    // gestern — alphabetisch stünde Zora trotzdem gleichrangig dazwischen.
    await data.createTrip(today.subtract(const Duration(days: 200)), {
      persons['Zora']!: ParticipationStatus.driver,
      persons['Anna']!: ParticipationStatus.passenger,
    });
    await data.createTrip(today.subtract(const Duration(days: 1)), {
      persons['Anna']!: ParticipationStatus.driver,
      persons['Bert']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    final heading = find.text('Länger nicht dabei');
    expect(heading, findsOneWidget);

    final headingY = tester.getTopLeft(heading).dy;
    expect(
      tester.getTopLeft(find.text('Anna')).dy,
      lessThan(headingY),
      reason: 'Stammgäste gehören über die Trennlinie.',
    );
    expect(tester.getTopLeft(find.text('Bert')).dy, lessThan(headingY));
    expect(
      tester.getTopLeft(find.text('Zora')).dy,
      greaterThan(headingY),
      reason: 'Wer seit 200 Tagen nicht dabei war, ist kein Stammgast.',
    );
  });

  testWidgets('ohne Historie bleibt die Liste ungeteilt', (tester) async {
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

    expect(
      find.text('Länger nicht dabei'),
      findsNothing,
      reason:
          'Eine frische Gruppe hat keine Stammgäste — dann wäre jeder unter '
          'der Trennlinie und die Überschrift nur verwirrend.',
    );
  });

  // Hinweis, keine Sperre: Zur Not rückt man zusammen oder es fahren zwei
  // Autos. Verbieten würde heißen, eine Fahrt nicht eintragen zu können,
  // die tatsächlich so stattgefunden hat.
  testWidgets('zu viele Leute fürs Auto werden angemerkt', (tester) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(groupId);
    // Anna fährt einen Zweisitzer, die anderen haben nichts hinterlegt.
    await data.createPerson(
      const Person(id: '', name: 'Anna', active: true, seats: 2),
    );
    for (final name in ['Bert', 'Clara']) {
      await data.createPerson(Person(id: '', name: name, active: true));
    }

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    // Anna + Bert = 2 Personen, das passt noch.
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sitzplätze'), findsNothing);

    // Mit Clara sind es drei — einer zu viel.
    await tester.tap(find.text('Clara'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Annas Auto hat 2 Sitzplätze — ihr seid 3.'),
      findsOneWidget,
    );

    // Speichern bleibt möglich.
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.textContaining('Speichern'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('ohne gepflegte Sitzplätze gibt es keine Warnung', (
    tester,
  ) async {
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
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    expect(
      find.textContaining('Sitzplätze'),
      findsNothing,
      reason: 'Eine fehlende Angabe darf nie zu einer Warnung werden.',
    );
  });

  // Eine Fahrt im Voraus einzutragen verschiebt die Punkte aller anderen
  // für etwas, das noch nicht passiert ist. Geplant wird im Wochenplaner.
  testWidgets('in die Zukunft lässt sich nichts eintragen', (tester) async {
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

    expect(
      find.text('Morgen'),
      findsNothing,
      reason: 'Der Schnellwahl-Chip für morgen ist bewusst entfallen.',
    );
    expect(
      find.text('Gestern'),
      findsOneWidget,
      reason: 'Nachtragen bleibt der häufige Fall und muss leicht bleiben.',
    );
    expect(find.text('Heute'), findsOneWidget);
  });

  // Ändern verschiebt die Punkte aller Beteiligten rückwirkend — das darf
  // nicht mit einem Tipper passieren.
  testWidgets('das Ändern einer eingetragenen Fahrt fragt nach', (
    tester,
  ) async {
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
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final now = DateTime.now();
    await data.createTrip(DateTime(now.year, now.month, now.day), {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    // Über die Historie in die Bearbeitung.
    await tester.tap(find.text('Historie'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    // Der Knopf trägt den Fahrernamen („Speichern – Anna fährt").
    await tester.tap(find.textContaining('Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Eingetragene Fahrt ändern?'), findsOneWidget);

    // Abbrechen lässt die Fahrt unangetastet.
    await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
    await tester.pumpAndSettle();
    expect(find.text('Eingetragene Fahrt ändern?'), findsNothing);
    expect(
      (await data.loadTrips()).single.participations[ids['Anna']],
      ParticipationStatus.driver,
    );
  });
}

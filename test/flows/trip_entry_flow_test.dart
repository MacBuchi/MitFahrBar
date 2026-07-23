/// trip_entry_flow_test.dart – Fahrt über die Kachel-Maske eintragen.
library;

import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/plan_ride.dart';
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

  // Issue #61: 1-way braucht jemanden, der wirklich fährt. Ist nur eine
  // Person dabei, springt der zweite Tap direkt auf „raus" — sonst stünde
  // die Maske in einem Zustand, aus dem kein Fahrer mehr möglich ist.
  testWidgets('die einzige Person kann nicht 1-way werden', (tester) async {
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

    await tester.tap(find.text('Anna')); // dabei (einzige) -> wird Fahrer
    await tester.pumpAndSettle();
    // „Anna" steht jetzt doppelt da (Kachel + Fahrer-Feld) — getippt wird
    // die Teilnehmer-Kachel weiter unten.
    await tester.tap(find.text('Anna').last); // -> direkt raus, kein 1-way
    await tester.pumpAndSettle();

    expect(find.text('1-way'), findsNothing);
    expect(find.text('Mindestens 1 Person auswählen'), findsOneWidget);
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

  // Vorgabe ist der normale PKW (Fahrer + 4). Wer nichts pflegt, bekommt
  // deshalb erst ab dem sechsten Menschen einen Hinweis — und nicht schon,
  // weil die Angabe fehlt.
  testWidgets('der voreingestellte Fünfsitzer trägt drei ohne Murren', (
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
      reason: 'Drei Leute passen in jeden normalen PKW.',
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

  // Issue #65: Wer im Wochenplan steht, ist beim Eintragen schon gewählt —
  // 1-way bleibt 1-way, den Fahrer setzt weiterhin die Fairness.
  testWidgets('der Wochenplan belegt die Auswahl vor', (tester) async {
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
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await data.setAvailability(today, ids['Anna']!, PlanRide.full);
    await data.setAvailability(today, ids['Bert']!, PlanRide.oneWay);

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Vorauswahl aus dem Wochenplan übernommen.'),
      findsOneWidget,
    );
    // Anna ist die einzige volle Teilnehmerin und damit Fahrerin.
    expect(find.text('Speichern – Anna fährt'), findsOneWidget);
    expect(find.text('1-way'), findsOneWidget); // Bert wie geplant
    expect(find.text('–'), findsOneWidget); // Clara bleibt draußen
  });

  testWidgets('beim Datumswechsel wandert die Vorauswahl mit', (tester) async {
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
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    await data.setAvailability(today, ids['Anna']!, PlanRide.full);
    await data.setAvailability(yesterday, ids['Bert']!, PlanRide.full);

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Speichern – Anna fährt'), findsOneWidget);

    await tester.tap(find.text('Gestern'));
    await tester.pumpAndSettle();

    expect(find.text('Speichern – Bert fährt'), findsOneWidget);
    expect(find.text('–'), findsOneWidget); // Anna stand gestern nicht im Plan
  });

  // Der Dirty-Schutz: Sobald von Hand gewählt wurde, überschreibt kein
  // Datumswechsel (und keine spät eintreffende Antwort) die Auswahl.
  testWidgets('Handarbeit überlebt den Datumswechsel', (tester) async {
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
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    await data.setAvailability(today, ids['Anna']!, PlanRide.full);
    await data.setAvailability(yesterday, ids['Bert']!, PlanRide.full);

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clara')); // von Hand dazu → Handarbeit
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gestern'));
    await tester.pumpAndSettle();

    // Keine Neu-Vorbelegung: Anna + Clara bleiben gewählt, Bert draußen.
    expect(find.text('fährt'), findsOneWidget);
    expect(find.text('dabei'), findsOneWidget);
    expect(find.text('–'), findsOneWidget); // nur Bert
    expect(
      find.text('Vorauswahl aus dem Wochenplan übernommen.'),
      findsNothing,
    );
  });

  // Dieselbe Regel wie im Planer (Issue #54): Wer inaktiv ist, taucht auch
  // über alte Plan-Einträge nicht wieder auf.
  testWidgets('Verfügbarkeit inaktiver Personen belegt nicht vor', (
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
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await data.setAvailability(today, ids[name]!, PlanRide.full);
    }
    await data.updatePerson(
      Person(id: ids['Clara']!, name: 'Clara', active: false),
    );

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    // Inaktiv und nicht gewählt heißt: gar nicht erst auf der Maske.
    expect(find.text('Clara'), findsNothing);
    expect(find.text('fährt'), findsOneWidget);
    expect(find.text('dabei'), findsOneWidget);
  });

  // Ein reiner 1-way-Plan hat keinen möglichen Fahrer — die Vorbelegung
  // zeigt das ehrlich, statt jemanden zum Fahrer zu erfinden.
  testWidgets('nur 1-way im Plan lässt Speichern gesperrt', (tester) async {
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
    final today = DateTime(now.year, now.month, now.day);
    await data.setAvailability(today, ids['Anna']!, PlanRide.oneWay);

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Fahrt eintragen'),
    );
    await tester.pumpAndSettle();

    expect(find.text('1-way'), findsOneWidget);
    expect(find.text('Mindestens 1 Person auswählen'), findsOneWidget);
  });

  // Beim Bearbeiten zeigt die Maske die Fahrt, wie sie war — der Plan des
  // Tages hat dort nichts mehr zu sagen.
  testWidgets('Bearbeiten wird nicht vorbelegt', (tester) async {
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
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    await data.createTrip(yesterday, {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });
    await data.setAvailability(yesterday, ids['Clara']!, PlanRide.full);

    await pumpApp(tester, backend);
    await _login(tester);
    await tester.tap(find.text('Historie'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ListTile).first);
    await tester.pumpAndSettle();

    expect(
      find.text('Vorauswahl aus dem Wochenplan übernommen.'),
      findsNothing,
    );
    expect(find.text('–'), findsOneWidget); // Clara bleibt draußen
  });
}

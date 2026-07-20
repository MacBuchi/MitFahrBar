/// dashboard_ranking_flow_test.dart – „Wer ist dran" in der echten App.
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
  // „2,5 Punkte · Fahranteil 40 %" waren zwei nackte Zahlen ohne Richtung.
  // Punkte sind zero-sum: negativ heißt, die Gruppe schuldet einem noch
  // Fahrten — genau andersherum, als die Zahl sich anfühlt (Issue #26).
  testWidgets('die Rangliste sagt, in welche Richtung die Punkte zeigen', (
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

    // Anna fährt, Bert fährt mit: Anna +1, Bert −1.
    await data.createTrip(DateTime(2026, 3, 2), {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.textContaining('schuldet 1'), findsOneWidget);
    expect(find.textContaining('hat 1 gut'), findsOneWidget);
    expect(
      find.textContaining('Punkte'),
      findsNothing,
      reason: 'Die richtungslose Formulierung soll verschwunden sein.',
    );
  });

  // Die Quote (Ø Mitfahrer je eigener Fahrt) erklärt, warum jemand trotz
  // vieler Fahrten wenig Punkte hat. Sie stand bisher nur in der Statistik.
  testWidgets('volle und fast leere Autos werden benannt', (tester) async {
    final backend = FakeBackend();
    final groupId = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(groupId);
    for (final name in ['Voll', 'Mittel', 'Leer', 'Gast1', 'Gast2']) {
      await data.createPerson(Person(id: '', name: name, active: true));
    }
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};

    // Drei eigene Fahrten je Person — das ist die Schwelle, ab der markiert
    // wird. Voll nimmt je 3 mit, Mittel je 2, Leer je 1.
    for (var i = 0; i < 3; i++) {
      await data.createTrip(DateTime(2026, 3, 2 + i), {
        ids['Voll']!: ParticipationStatus.driver,
        ids['Mittel']!: ParticipationStatus.passenger,
        ids['Gast1']!: ParticipationStatus.passenger,
        ids['Gast2']!: ParticipationStatus.passenger,
      });
      await data.createTrip(DateTime(2026, 4, 2 + i), {
        ids['Mittel']!: ParticipationStatus.driver,
        ids['Gast1']!: ParticipationStatus.passenger,
        ids['Gast2']!: ParticipationStatus.passenger,
      });
      await data.createTrip(DateTime(2026, 5, 2 + i), {
        ids['Leer']!: ParticipationStatus.driver,
        ids['Gast1']!: ParticipationStatus.passenger,
      });
    }

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.text('Volle Kischt'), findsOneWidget);
    expect(find.text('Fast alloi'), findsOneWidget);
    // Die Quote steht seit v0.15.0 nur noch in den Titeln; in der Zeile
    // selbst steht der Fahranteil in Prozent.
    expect(find.textContaining('Ø 3,0 mit'), findsNothing);
    expect(find.textContaining('Ø 1,0 mit'), findsNothing);
    expect(find.textContaining(RegExp(r'fährt\s*\d+\s*%')), findsWidgets);
  });

  testWidgets('ohne genug Fahrten bleibt die Startseite unmarkiert', (
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

    await data.createTrip(DateTime(2026, 3, 2), {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
      ids['Clara']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    expect(
      find.text('Volle Kischt'),
      findsNothing,
      reason:
          'Nach einer einzigen Fahrt sagt die Quote nichts — ein Titel wäre '
          'reine Dekoration und würde bei jeder Fahrt wandern.',
    );
    expect(find.text('Fast alloi'), findsNothing);
  });

  // Seit Issue #38 steuert der Fahranteil die Reihenfolge nicht mehr. Er
  // steht als Gesicht *und* als Prozentzahl da: Das Gesicht sagt auf einen
  // Blick, wer viel fahren musste, die Zahl bleibt für alle, die es genau
  // wissen wollen.
  testWidgets('der Fahranteil steht als Gesicht und als Prozentzahl', (
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

    // Anna fährt beide Tage, Bert fährt nie mit dem eigenen Auto: Annas
    // Fahranteil liegt über dem Schnitt, Berts darunter.
    for (final day in [DateTime(2026, 3, 2), DateTime(2026, 3, 3)]) {
      await data.createTrip(day, {
        ids['Anna']!: ParticipationStatus.driver,
        ids['Bert']!: ParticipationStatus.passenger,
      });
    }

    await pumpApp(tester, backend);
    await _login(tester);

    expect(
      find.textContaining(RegExp(r'fährt\s*100\s*%')),
      findsOneWidget,
      reason: 'Anna fuhr an allen ihren Tagen selbst.',
    );
    expect(
      find.textContaining(RegExp(r'fährt\s*0\s*%')),
      findsOneWidget,
      reason: 'Bert ist nie selbst gefahren.',
    );
    expect(
      find.bySemanticsLabel(RegExp('fährt am häufigsten in der Gruppe')),
      findsOneWidget,
      reason: 'Anna trägt das traurigste Gesicht — sie musste alles fahren.',
    );
    expect(
      find.bySemanticsLabel(RegExp('fährt am seltensten in der Gruppe')),
      findsOneWidget,
      reason: 'Bert trägt das glücklichste.',
    );
  });
}

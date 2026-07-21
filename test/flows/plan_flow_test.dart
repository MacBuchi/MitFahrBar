/// plan_flow_test.dart – Wochenplaner über die echte App.
library;

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<FakeBackend> _backend(List<String> names) async {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  for (final name in names) {
    await backend
        .dataFor(id)
        .createPerson(Person(id: '', name: name, active: true));
  }
  return backend;
}

Future<void> _openPlan(WidgetTester tester) async {
  await tester.tap(find.text('Woche'));
  await tester.pumpAndSettle();
}

/// Zelle im Raster über ihre Beschriftung finden — dieselbe, die ein
/// Screenreader vorliest. Die Beschriftung endet auf den Zustand („dabei",
/// „nur eine Richtung", …); [state] prüft ihn mit.
Finder _cell(String person, DateTime day, {String? state}) {
  final prefix = '$person, ${DateFormat('E', 'de').format(day)}';
  return find.bySemanticsLabel(
    RegExp('^${RegExp.escape(prefix)}, ${state ?? '.*'}\$'),
  );
}

void main() {
  testWidgets('der Planer zeigt Montag bis Freitag und alle Personen', (
    tester,
  ) async {
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    expect(find.text('Wochenplan'), findsOneWidget);
    expect(find.text('Anna'), findsWidgets);
    expect(find.text('Bert'), findsWidgets);
    // Nicht auf exakt fünf prüfen: Die ListView baut nur die sichtbaren
    // Tageszeilen, auf einem kurzen Testbildschirm sind das weniger.
    expect(
      find.textContaining('Noch niemand verfügbar'),
      findsWidgets,
      reason:
          'Ohne Verfügbarkeiten gibt es nichts vorzuschlagen — und das '
          'soll dastehen, statt die Zeile leer zu lassen.',
    );
    // Nicht auf „fährt" allein prüfen — das steht schon im Einleitungstext.
    expect(find.textContaining('fährt · Vorschlag'), findsNothing);
  });

  // Der eigentliche Zweck: aus Verfügbarkeiten wird ein Fahrer-Vorschlag.
  testWidgets('angetippte Verfügbarkeit erzeugt einen Fahrer-Vorschlag', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', monday));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('fährt · Vorschlag'),
      findsOneWidget,
      reason: 'Sobald jemand kann, muss der Planer einen Fahrer vorschlagen.',
    );
    handle.dispose();
  });

  // Ohne Vorwärts-Simulation stünde an beiden Tagen derselbe Name.
  testWidgets('über zwei Tage wechselt der vorgeschlagene Fahrer', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final week = planningWeek();
    for (final day in [week[0], week[1]]) {
      for (final name in ['Anna', 'Bert']) {
        await tester.tap(_cell(name, day));
        await tester.pumpAndSettle();
      }
    }

    expect(find.textContaining('Anna fährt'), findsOneWidget);
    expect(
      find.textContaining('Bert fährt'),
      findsOneWidget,
      reason:
          'Der zweite Tag muss gegen die Statistik inklusive des ersten '
          'gerechnet werden.',
    );
    handle.dispose();
  });

  testWidgets('ohne Personen erklärt der Planer, was fehlt', (tester) async {
    await pumpApp(tester, await _backend([]));
    await _login(tester);
    await _openPlan(tester);

    expect(find.textContaining('Erst Personen anlegen'), findsOneWidget);
  });

  // 1-way gibt es im Fahrten-Editor seit jeher; im Planer fehlte es. Der
  // zweite Tap ist dieselbe Geste wie dort, damit man sie nur einmal lernt.
  testWidgets('der zweite Tap macht aus „dabei" eine 1-way-Fahrt', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    expect(_cell('Anna', monday, state: 'kann nicht'), findsOneWidget);

    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'dabei|fährt'), findsOneWidget);

    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'nur eine Richtung'), findsOneWidget);

    // Dritter Tap zurück auf Anfang — sonst käme man aus 1-way nie heraus.
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'kann nicht'), findsOneWidget);
    handle.dispose();
  });

  // Ein halber Weg stellt kein Auto.
  testWidgets('wer nur eine Richtung fährt, wird nicht Fahrer', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    // Anna zweimal antippen: dabei → nur eine Richtung. Bert einmal.
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', monday));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Bert fährt'),
      findsOneWidget,
      reason: 'Anna kann an dem Tag nur eine Richtung und scheidet aus.',
    );
    expect(find.textContaining('Anna fährt'), findsNothing);
    handle.dispose();
  });

  // Beim Durchklicken der echten Web-App aufgefallen: Der Tag meldete
  // „Noch niemand verfügbar", obwohl jemand eingetragen war — nur eben
  // 1-way. Dann sucht die Nutzerin den Fehler bei sich.
  testWidgets('nur 1-way heißt kein Fahrer, nicht „niemand verfügbar"', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();

    expect(_cell('Anna', monday, state: 'nur eine Richtung'), findsOneWidget);
    expect(
      find.textContaining('Kein Fahrer möglich'),
      findsOneWidget,
      reason: 'Anna ist verfügbar — sie kann nur nicht fahren.',
    );
    // Die übrigen Tage sind wirklich leer und sagen das auch weiterhin.
    // Kein fester Zähler: Die Liste baut nur, was sichtbar ist.
    expect(find.textContaining('Noch niemand verfügbar'), findsWidgets);
    handle.dispose();
  });

  // Ein eingetragener Tag ist Geschichte. Bliebe das Raster dort bedienbar,
  // würde ein Fehlgriff stillschweigend die Planung einer gefahrenen Fahrt
  // ändern — und der Tag sähe aus wie jeder andere.
  testWidgets('ein eingetragener Tag ist gesperrt und führt zum Bearbeiten', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final backend = await _backend(['Anna', 'Bert']);
    final data = backend.dataFor(backend.currentGroupId ?? 'group-1');
    final ids = {for (final p in await data.loadPersons()) p.name: p.id};
    final monday = planningWeek().first;
    await data.createTrip(monday, {
      ids['Anna']!: ParticipationStatus.driver,
      ids['Bert']!: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    expect(
      _cell('Anna', monday, state: '.*bereits eingetragen'),
      findsOneWidget,
      reason: 'Die Zelle sagt auch dem Screenreader, warum nichts geht.',
    );
    expect(find.textContaining('ist gefahren'), findsOneWidget);

    // Kein „Eintragen" mehr — der Tag ist durch.
    expect(find.widgetWithText(FilledButton, 'Eintragen'), findsNothing);
    final edit = find.widgetWithText(OutlinedButton, 'Bearbeiten');
    expect(edit, findsOneWidget);

    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Speichern'),
      findsOneWidget,
      reason: 'Der Knopf führt direkt in die Bearbeitung dieser Fahrt.',
    );
    handle.dispose();
  });

  testWidgets('wer die meisten mitnimmt, bekommt das Hajo', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert', 'Clara']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    // Genau ein Tag mit Fahrer, also gibt es einen eindeutigen Sieger.
    expect(find.textContaining('Nimmt diese Woche die meisten mit'), findsOne);
    expect(find.textContaining('Hajo,'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('ohne Mitfahrer gibt es kein Hajo', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    // Nur Anna kann — sie fährt allein, das ist kein Mitnehmen.
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();

    expect(find.textContaining('Hajo,'), findsNothing);
    handle.dispose();
  });
}

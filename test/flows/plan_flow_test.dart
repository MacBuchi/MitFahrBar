/// plan_flow_test.dart – Wochenplaner über die echte App.
library;

import 'dart:async';

import 'package:fahrgemeinschaft/core/fairness.dart';
import 'package:fahrgemeinschaft/data/providers.dart';
import 'package:fahrgemeinschaft/models/person.dart';
import 'package:fahrgemeinschaft/models/plan_ride.dart';
import 'package:fahrgemeinschaft/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Schreibt erst, wenn der Test es erlaubt — macht die Optimistik sichtbar.
class _SlowWriteRepository extends FakeRoutingCarpoolRepository {
  _SlowWriteRepository(super.backend);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) async {
    await _gate.future;
    await super.setAvailability(date, personId, ride);
  }
}

/// Jeder Schreib scheitert — der Planer muss zur Server-Wahrheit zurück.
class _FailingWriteRepository extends FakeRoutingCarpoolRepository {
  _FailingWriteRepository(super.backend);

  @override
  Future<void> setAvailability(
    DateTime date,
    String personId,
    PlanRide? ride,
  ) async {
    throw Exception('kein Netz');
  }
}

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
    expect(find.textContaining('Das vollste Auto der Woche'), findsOne);
    expect(find.textContaining('Hajo,'), findsOneWidget);
    handle.dispose();
  });

  // Entschieden 2026-07-22: Gefeiert wird das vollste Auto eines Tages,
  // bei Gleichstand alle — nicht mehr die Wochensumme mit Titel-Verzicht.
  testWidgets('bei Gleichstand feiern beide Fahrer', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert', 'Clara']));
    await _login(tester);
    await _openPlan(tester);

    final week = planningWeek();
    // Montag fährt Anna (2 Mitfahrer), Dienstag Bert (2 Mitfahrer) — die
    // Vorwärts-Simulation setzt die Fahrer genau so, weil Anna nach Montag
    // im Plus steht.
    for (final day in [week[0], week[1]]) {
      for (final name in ['Anna', 'Bert', 'Clara']) {
        await tester.tap(_cell(name, day));
        await tester.pumpAndSettle();
      }
    }

    expect(find.textContaining('Anna fährt'), findsOneWidget);
    expect(find.textContaining('Bert fährt'), findsOneWidget);
    expect(find.textContaining('Die vollsten Autos der Woche'), findsOne);
    expect(find.textContaining('Hajo, Anna & Bert!'), findsOneWidget);
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

  // Issue #59: Das Hajo wiegt wie die Punkte — eine 1-way-Mitfahrt halb.
  // Nach Köpfen stünde es hier 1:1 (beide Tage je ein Mitfahrer) und beide
  // Fahrer würden gefeiert; nach Punkten schlägt die ganze Mitfahrt (1,0)
  // die halbe (0,5).
  testWidgets('eine 1-way-Mitfahrt wiegt im Hajo nur halb', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert', 'Clara']));
    await _login(tester);
    await _openPlan(tester);

    final week = planningWeek();
    // Montag: Anna fährt, Bert nur eine Richtung (zweiter Tap) → 0,5.
    await tester.tap(_cell('Anna', week[0]));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', week[0]));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', week[0]));
    await tester.pumpAndSettle();
    // Dienstag: Bert (schuldet nach Montag am meisten) fährt Clara — 1,0.
    await tester.tap(_cell('Bert', week[1]));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Clara', week[1]));
    await tester.pumpAndSettle();

    expect(find.textContaining('Bert fährt'), findsOneWidget);
    expect(find.textContaining('Hajo, Bert!'), findsOneWidget);
    expect(
      find.textContaining('Hajo, Anna'),
      findsNothing,
      reason: 'Nach Köpfen wäre es ein Gleichstand — nach Punkten nicht.',
    );
    handle.dispose();
  });

  // Der Trägheits-Fix vom 2026-07-22: Der Tap wird sofort eingerechnet,
  // der Netz-Schreib läuft hinterher. Der Fake schreibt erst, wenn der
  // Test es erlaubt — wäre der Planer noch synchron, bliebe die Zelle
  // bis dahin leer.
  testWidgets('ein Tap wirkt sofort, bevor der Server antwortet', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final backend = await _backend(['Anna', 'Bert']);
    final slow = _SlowWriteRepository(backend);
    await pumpApp(
      tester,
      backend,
      overrides: [carpoolRepositoryProvider.overrideWithValue(slow)],
    );
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    await tester.tap(_cell('Anna', monday));
    await tester.pump();

    expect(
      _cell('Anna', monday, state: 'fährt'),
      findsOneWidget,
      reason: 'Die Zelle muss umspringen, obwohl der Schreib noch hängt.',
    );

    slow.release();
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'fährt'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('schlägt der Schreib fehl, springt die Zelle zurück', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final backend = await _backend(['Anna', 'Bert']);
    await pumpApp(
      tester,
      backend,
      overrides: [
        carpoolRepositoryProvider.overrideWithValue(
          _FailingWriteRepository(backend),
        ),
      ],
    );
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek().first;
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();

    expect(find.text('Speichern fehlgeschlagen.'), findsOneWidget);
    expect(
      _cell('Anna', monday, state: 'kann nicht'),
      findsOneWidget,
      reason:
          'Nach dem Fehlschlag muss wieder die Server-Wahrheit stehen — '
          'sonst zeigt der Plan etwas, das nie gespeichert wurde.',
    );
    handle.dispose();
  });

  // Marcus' Handy-Fund vom 2026-07-22: Eine inaktive Person hatte noch eine
  // Verfügbarkeit aus ihrer aktiven Zeit — das Raster zeigte sie nicht,
  // aber der Planer zählte sie als Kopf (falsches Hajo), und „Eintragen"
  // hätte sie als Mitfahrt gebucht und die Punkte rückwirkend verschoben.
  testWidgets('Verfügbarkeiten inaktiver Personen zählen nicht', (
    tester,
  ) async {
    final backend = FakeBackend();
    final id = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(id);
    final anna = await data.createPerson(
      const Person(id: '', name: 'Anna', active: true),
    );
    final bert = await data.createPerson(
      const Person(id: '', name: 'Bert', active: true),
    );
    final ghost = await data.createPerson(
      const Person(id: '', name: 'Carla', active: true),
    );
    final monday = planningWeek().first;
    for (final p in [anna, bert, ghost]) {
      await data.setAvailability(monday, p.id, PlanRide.full);
    }
    // Erst nach dem Eintragen der Verfügbarkeit inaktiv gestellt — genau
    // die Reihenfolge, in der der Geist entsteht.
    await data.updatePerson(
      Person(id: ghost.id, name: ghost.name, active: false),
    );

    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    // Fahrer + genau EIN Mitfahrer — Carla darf nicht mitzählen.
    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dabei: Anna, Bert'), findsOneWidget);
    expect(
      find.textContaining('Carla'),
      findsNothing,
      reason:
          'Eine inaktive Person darf beim Bestätigen nicht in die Fahrt '
          'gebucht werden — das verschöbe rückwirkend die Punkte aller.',
    );
  });

  // Zugesagt in Issue #38: Der Punktestand steht im Raster vor dem Namen,
  // damit man dem Vorschlag ansieht, warum er auf diese Person fällt.
  testWidgets('das Raster zeigt den Punktestand vor dem Namen', (tester) async {
    final backend = FakeBackend();
    final id = backend.addGroup(
      handle: 'daciaracing',
      password: 'geheim123',
      name: 'Dacia Racing',
    );
    final data = backend.dataFor(id);
    final anna = await data.createPerson(
      const Person(id: '', name: 'Anna', active: true),
    );
    final bert = await data.createPerson(
      const Person(id: '', name: 'Bert', active: true),
    );
    // Anna nimmt Bert mit: Anna +1, Bert −1.
    await data.createTrip(DateTime(2026, 3, 9), {
      anna.id: ParticipationStatus.driver,
      bert.id: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    expect(find.text('+1'), findsOneWidget);
    // Typografisches Minus (U+2212), nicht der Bindestrich — gleiche Breite
    // wie das Plus, damit die Spalte nicht flattert.
    expect(find.text('−1'), findsOneWidget);
  });
}

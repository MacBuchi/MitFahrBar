/// plan_flow_test.dart – Wochenplaner über die echte App.
library;

import 'dart:async';

import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/plan_ride.dart';
import 'package:mitfahrbar/models/trip.dart';
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

/// Wie [_backend], nur mit Sitzplätzen je Person — die Zutat, aus der
/// Mehr-Auto-Tage entstehen (Issue #62).
Future<FakeBackend> _seatBackend(Map<String, int> seats) async {
  final backend = FakeBackend();
  final id = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  for (final e in seats.entries) {
    await backend
        .dataFor(id)
        .createPerson(
          Person(id: '', name: e.key, active: true, seats: e.value),
        );
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
    final monday = planningWeek(testToday).first;
    expect(
      find.textContaining('KW ${isoWeekNumber(monday)}'),
      findsOneWidget,
      reason:
          'Der Raster-Kopf nennt Kalenderwoche und Zeitraum zur '
          'Orientierung (#84).',
    );
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

    final monday = planningWeek(testToday).first;
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

    final week = planningWeek(testToday);
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

    final monday = planningWeek(testToday).first;
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

    final monday = planningWeek(testToday).first;
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

    final monday = planningWeek(testToday).first;
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
    final monday = planningWeek(testToday).first;
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

    final monday = planningWeek(testToday).first;
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

    final week = planningWeek(testToday);
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

    final monday = planningWeek(testToday).first;
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

    final week = planningWeek(testToday);
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

  // Issue #60: Der Planer rechnet vor, was die geplante Woche ändern würde —
  // je Person als Punktediff, umschaltbar auf die Fahrraten-Änderung in
  // Promille. Reine Vorschau, die echten Punkte bleiben unberührt.
  testWidgets('„Was diese Woche ändert" kann Punkte und Fahrrate', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', monday));
    await tester.pumpAndSettle();

    // Frische Gruppe: Anna fährt und nimmt Bert mit.
    expect(find.text('Was diese Woche ändert:'), findsOneWidget);
    expect(find.text('Anna +1'), findsOneWidget);
    expect(find.text('Bert −1'), findsOneWidget);

    await tester.tap(find.text('Fahrrate'));
    await tester.pumpAndSettle();
    expect(find.text('Anna +1000 ‰'), findsOneWidget);
    expect(
      find.text('Bert ±0 ‰'),
      findsOneWidget,
      reason:
          'Mitfahren ändert die eigene Fahrrate dieser Woche nicht — '
          'die Null ist ehrlich.',
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

    final monday = planningWeek(testToday).first;
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

    final monday = planningWeek(testToday).first;
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
    final monday = planningWeek(testToday).first;
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

  // ---------- Mehrere Autos je Tag (Issue #62) ----------

  // Alle Autos zu klein für den Tag → der Planer teilt auf, statt wie
  // früher stillschweigend EIN zu kleines Auto vorzuschlagen.
  testWidgets('reicht kein Auto allein, schlägt der Planer zwei vor', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      await _seatBackend({'Anna': 2, 'Bert': 2, 'Clara': 2, 'Dora': 2}),
    );
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert', 'Clara', 'Dora']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    expect(
      find.textContaining('fahren · 2 Autos · Vorschlag'),
      findsOneWidget,
      reason: 'Vier Leute, lauter Zweisitzer — zwei Autos sind das Minimum.',
    );
    // Beide Fahrer tragen im Raster das Auto-Symbol.
    final weekday = DateFormat('E', 'de').format(monday);
    expect(
      find.bySemanticsLabel(
        RegExp('^[^,]+, ${RegExp.escape(weekday)}, fährt\$'),
      ),
      findsNWidgets(2),
    );
    handle.dispose();
  });

  testWidgets('der Fahrer-Dialog rechnet Sitze live und kennt kein 1-way', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(
      tester,
      await _seatBackend({'Anna': 2, 'Bert': 2, 'Clara': 2, 'Dora': 2}),
    );
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }
    // Dora zweimal: nur eine Richtung — sie zählt als Kopf, stellt aber
    // kein Auto.
    await tester.tap(_cell('Dora', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Dora', monday));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fahrer ändern'));
    await tester.pumpAndSettle();

    Finder tile(String name) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(CheckboxListTile, name),
    );
    expect(
      tile('Dora'),
      findsNothing,
      reason:
          '1-way stand früher zur Wahl und die Auswahl verfiel still — '
          'jetzt steht gar nicht erst da, was kein Auto stellt.',
    );
    // Vorschlag: zwei Zweisitzer für vier Köpfe (Dora sitzt ja mit drin).
    expect(find.text('Reicht für alle 4.'), findsOneWidget);

    // Einen Fahrer abwählen → die Rechnung sagt ehrlich, dass es knapp wird
    // — wählen darf man es trotzdem (Menschenentscheidung).
    final checked = [
      for (final name in ['Anna', 'Bert', 'Clara'])
        if (tester.widget<CheckboxListTile>(tile(name)).value ?? false) name,
    ];
    await tester.tap(tile(checked.first));
    await tester.pumpAndSettle();
    expect(find.text('Reicht für 2 von 4.'), findsOneWidget);

    // Alle drei wählen und übernehmen → von Hand gesetzt.
    for (final name in ['Anna', 'Bert', 'Clara']) {
      if (!(tester.widget<CheckboxListTile>(tile(name)).value ?? false)) {
        await tester.tap(tile(name));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.text('Übernehmen'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('fahren · 3 Autos · von Hand gesetzt'),
      findsOneWidget,
    );

    // „Zurück zum Vorschlag" räumt das Übersteuern wieder ab.
    await tester.tap(find.byTooltip('Fahrer ändern'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurück zum Vorschlag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fahren · 2 Autos · Vorschlag'), findsOneWidget);
    handle.dispose();
  });

  // Der Kern von Issue #62: Eintragen öffnet den Editor je Auto — vorbelegt
  // mit den Insassen DIESES Autos, ohne Rückfrage-Lärm, und gebucht wird
  // erst mit jedem Speichern.
  testWidgets('Eintragen am 2-Auto-Tag: Editor je Auto, nichts still', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final backend = await _seatBackend({
      'Anna': 2,
      'Bert': 2,
      'Clara': 2,
      'Dora': 2,
    });
    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert', 'Clara', 'Dora']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen'));
    await tester.pumpAndSettle();
    expect(find.text('2 Fahrten eintragen?'), findsOneWidget);
    await tester.tap(find.text("Los geht's"));
    await tester.pumpAndSettle();

    // Auto 1: der Seed belegt die Insassen dieses Autos vor — nicht den
    // ganzen Tag, wie es der Plan-Prefill (#65) täte.
    expect(find.text('Fahrt eintragen · Auto 1/2'), findsOneWidget);
    expect(
      find.text('Vorbelegt aus dem Wochenplan · Auto 1 von 2.'),
      findsOneWidget,
    );
    expect(
      find.text('Vorauswahl aus dem Wochenplan übernommen.'),
      findsNothing,
    );
    expect(find.text('fährt'), findsOneWidget);
    expect(find.text('dabei'), findsOneWidget);
    expect(
      find.text('–'),
      findsNWidgets(2),
      reason: 'Die zwei Insassen von Auto 2 gehören nicht in Auto 1.',
    );

    await tester.tap(find.textContaining('Speichern –'));
    await tester.pumpAndSettle();

    // Auto 2 folgt automatisch — die „Weitere Fahrt?"-Rückfrage schweigt,
    // denn die erste Fahrt ist hier erwartet, kein Versehen.
    expect(find.text('Fahrt eintragen · Auto 2/2'), findsOneWidget);
    expect(find.text('Weitere Fahrt an diesem Tag?'), findsNothing);
    await tester.tap(find.textContaining('Speichern –'));
    await tester.pumpAndSettle();
    expect(find.text('Weitere Fahrt an diesem Tag?'), findsNothing);

    // Zurück im Planer: der Tag ist durch.
    expect(find.textContaining('sind gefahren'), findsOneWidget);

    final data = backend.dataFor(backend.currentGroupId ?? 'group-1');
    final trips = await data.loadTrips();
    expect(trips, hasLength(2));
    for (final trip in trips) {
      expect(trip.participations, hasLength(2));
      expect(trip.driverId, isNotNull);
    }
    expect(
      trips.expand((t) => t.participations.keys).toSet(),
      hasLength(4),
      reason: 'Jede Person genau einmal gebucht, nichts doppelt.',
    );
    handle.dispose();
  });

  // Abbruch ist eine ehrliche Antwort: Was gespeichert ist, bleibt; der
  // Rest wird NICHT still nachgebucht.
  testWidgets('Abbruch nach Auto 1 lässt den Rest ungebucht', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = await _seatBackend({'Anna': 2, 'Bert': 2, 'Clara': 2});
    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Los geht's"));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Speichern –'));
    await tester.pumpAndSettle();

    expect(find.text('Fahrt eintragen · Auto 2/2'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Der Tag steht mit der einen echten Fahrt da — kein zweiter Trip.
    expect(find.textContaining('ist gefahren'), findsOneWidget);
    final data = backend.dataFor(backend.currentGroupId ?? 'group-1');
    expect(await data.loadTrips(), hasLength(1));
    handle.dispose();
  });

  // Regression: Der Ein-Auto-Tag behält seinen Ein-Tipp-Eintrag mit
  // Bestätigungsdialog — kein Editor-Umweg.
  testWidgets('ein Tag mit einem Auto bleibt der Ein-Tipp-Eintrag', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final backend = await _backend(['Anna', 'Bert', 'Clara']);
    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert', 'Clara']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen'));
    await tester.pumpAndSettle();
    expect(find.text('Fahrt eintragen?'), findsOneWidget);
    expect(find.textContaining('Dabei:'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Eintragen').last);
    await tester.pumpAndSettle();

    final data = backend.dataFor(backend.currentGroupId ?? 'group-1');
    final trips = await data.loadTrips();
    expect(trips, hasLength(1));
    expect(trips.single.participations, hasLength(3));
    handle.dispose();
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

  // Die Leitplanke aus #121. Sie ist eine **Vertipper-Bremse, keine Sperre**:
  // Über die Rückfrage kommt jeder durch, und Pärchen, die füreinander
  // eintragen, sind mit zwei Tipps oft schneller als mit dem Durchschalten.
  //
  // Alle übrigen Tests dieser Datei laufen ohne `identity:` — sie prüfen
  // damit weiterhin das freie Raster. Das ist kein Zufall, sondern der Beleg
  // für „ohne gewählte Person bleibt alles wie bisher".
  group('Nur die eigene Zeile', () {
    /// Wie [_backend], gibt aber die IDs zurück — die Geräte-Zuordnung
    /// braucht eine.
    Future<(FakeBackend, Map<String, String>)> backendWithIds(
      List<String> names,
    ) async {
      final backend = FakeBackend();
      final group = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final ids = <String, String>{};
      for (final name in names) {
        final person = await backend
            .dataFor(group)
            .createPerson(Person(id: '', name: name, active: true));
        ids[name] = person.id;
      }
      return (backend, ids);
    }

    testWidgets('die eigene Zelle schaltet direkt weiter', (tester) async {
      final handle = tester.ensureSemantics();
      final (backend, ids) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      // Zweimal tippen: Wer als Einzige verfügbar ist, wird sofort als
      // Fahrerin vorgeschlagen — die Zelle läse dann „fährt". Nach dem
      // zweiten Tipp ist sie 1-way und kommt als Fahrerin nicht in Frage,
      // der Zustand ist also eindeutig.
      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(_cell('Anna', monday, state: 'nur eine Richtung'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('eine fremde Zelle fragt nach, statt zu schalten', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (backend, ids) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        _cell('Bert', monday, state: 'kann nicht'),
        findsOneWidget,
        reason: 'Der Tipp allein darf noch nichts geändert haben.',
      );
      // Alle drei Zustände stehen zur Wahl — die Rückfrage erledigt es
      // gleich mit, statt nur zu fragen.
      for (final label in ['dabei', 'nur eine Richtung', 'kann nicht']) {
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
      }
      handle.dispose();
    });

    testWidgets('eine Auswahl in der Rückfrage schreibt den Zustand', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (backend, ids) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('nur eine Richtung'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _cell('Bert', monday, state: 'nur eine Richtung'),
        findsOneWidget,
        reason:
            'Zwei Tipps zu jedem Zustand — beim Durchschalten wären es bis '
            'zu drei.',
      );
      handle.dispose();
    });

    testWidgets('Abbrechen lässt den Zustand unverändert', (tester) async {
      final handle = tester.ensureSemantics();
      final (backend, ids) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(_cell('Bert', monday, state: 'kann nicht'), findsOneWidget);
      handle.dispose();
    });

    // Wer die Startabfrage überspringt, soll nicht schlechter dastehen als
    // vor dem Release.
    testWidgets('ohne gewählte Person bleibt es beim Durchschalten', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (backend, _) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(tester, backend, identity: DeviceIdentity.skipped);
      await _login(tester);
      await _openPlan(tester);

      // Zweimal, aus demselben Grund wie oben: Als einziger Verfügbarer
      // würde Bert nach dem ersten Tipp als Fahrer vorgeschlagen.
      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(_cell('Bert', monday, state: 'nur eine Richtung'), findsOneWidget);
      handle.dispose();
    });

    /// Die Schriftstärke des Namens in der Rasterzeile — `null`, wenn die
    /// Zeile nichts Eigenes setzt.
    FontWeight? weightOf(WidgetTester tester, String name) =>
        tester.widget<Text>(find.text(name)).style?.fontWeight;

    testWidgets('die eigene Zeile ist hervorgehoben', (tester) async {
      final (backend, ids) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      expect(
        weightOf(tester, 'Anna'),
        FontWeight.w600,
        reason:
            'Im Raster sucht man zuerst sich selbst. Die Hervorhebung ist '
            'Orientierung, keine Berechtigung — jeder darf weiterhin für '
            'jeden eintragen.',
      );
      expect(
        weightOf(tester, 'Bert'),
        isNot(FontWeight.w600),
        reason: 'Fremde Zeilen bleiben, wie sie waren.',
      );
    });

    testWidgets('ohne gewählte Person ist keine Zeile hervorgehoben', (
      tester,
    ) async {
      final (backend, _) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(tester, backend, identity: DeviceIdentity.skipped);
      await _login(tester);
      await _openPlan(tester);

      expect(weightOf(tester, 'Anna'), isNot(FontWeight.w600));
      expect(
        weightOf(tester, 'Bert'),
        isNot(FontWeight.w600),
        reason:
            'Wer die Startabfrage überspringt, sieht das Raster wie vor dem '
            'Release — dieselbe Regel wie beim Durchschalten.',
      );
    });
  });
}

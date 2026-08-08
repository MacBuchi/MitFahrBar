/// plan_flow_test.dart – Wochenplaner über die echte App.
library;

import 'dart:async';

import 'package:mitfahrbar/core/fairness.dart';
import 'package:mitfahrbar/data/device_identity.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
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

/// Setzt einen Zustand über das Zell-Menü (#183).
///
/// Seit v0.64.0 trägt ein Tap auf die leere Zelle nur noch ein; alles andere
/// öffnet das Menü. „Zweimal tippen für 1-way" gibt es nicht mehr — der
/// Zyklus wäre mit vier Stufen unbenutzbar geworden.
Future<void> _pick(
  WidgetTester tester,
  String person,
  DateTime day,
  String label,
) async {
  // Eine leere Zelle muss erst eingetragen werden, sonst öffnet der Tap kein
  // Menü, sondern trägt ein.
  if (_cell(person, day, state: 'kann nicht').evaluate().isNotEmpty) {
    await tester.tap(_cell(person, day));
    await tester.pumpAndSettle();
  }
  await tester.tap(_cell(person, day));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ListTile, label),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tippt „Ich möchte fahren" im Zell-Menü von [person] an [day].
///
/// Öffnet das Menü unabhängig vom Zustand der Zelle: Eine leere eigene
/// Zelle trägt beim ersten Tap nur ein — dann noch einmal.
Future<void> _wantToDrive(
  WidgetTester tester,
  String person,
  DateTime day,
) async {
  await tester.tap(_cell(person, day));
  await tester.pumpAndSettle();
  if (find.byType(AlertDialog).evaluate().isEmpty) {
    await tester.tap(_cell(person, day));
    await tester.pumpAndSettle();
  }
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ListTile, 'Ich möchte fahren'),
    ),
  );
  await tester.pumpAndSettle();
}

/// Öffnet „Zeiten & Treffpunkt" aus dem Zell-Menü von [person].
Future<void> _openTimes(
  WidgetTester tester,
  String person,
  DateTime day,
) async {
  await tester.tap(_cell(person, day));
  await tester.pumpAndSettle();
  if (find.widgetWithText(ListTile, 'Zeiten & Treffpunkt').evaluate().isEmpty) {
    await tester.tap(_cell(person, day));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.widgetWithText(ListTile, 'Zeiten & Treffpunkt'));
  await tester.pumpAndSettle();
}

/// Wer von [names] an [day] im Zustand [state] steht — für Aufbauten, in
/// denen der Vorschlag zwischen punktgleichen Personen nicht festliegt.
String _personIn(String state, DateTime day, List<String> names) => names
    .firstWhere((name) => _cell(name, day, state: state).evaluate().isNotEmpty);

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

  // Der Ausgangskorb (#132) ist der Weg, auf dem eine Änderung binnen einer
  // Minute aufs Handy kommt statt erst nach Stunden. Er hängt an einem
  // Zuhörer auf dem fertigen Plan — dass der wirklich feuert, sieht man weder
  // am Analyzer noch an einem Test, der nur den Rechenteil prüft.
  testWidgets('ein Tap im Planer schreibt den Ausgangskorb', (tester) async {
    final handle = tester.ensureSemantics();
    final backend = await _backend(['Anna', 'Bert']);
    await pumpApp(tester, backend);
    await _login(tester);
    await _openPlan(tester);

    final group = backend.currentGroupId!;
    final monday = planningWeek(testToday).first;
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    await tester.tap(_cell('Bert', monday));
    await tester.pumpAndSettle();

    final box = backend.outbox[group] ?? const [];
    final annasMonday = box.firstWhere(
      (entry) => entry.date == monday && entry.body.contains('Du fährst'),
      orElse: () => throw StateError('keine Zeile mit Fahrer-Text'),
    );
    expect(
      annasMonday.titleEvening,
      contains('Mo,'),
      reason: 'Die Kopfzeile nennt den Tag, um den es geht.',
    );
    expect(
      box.where((entry) => entry.date == monday).length,
      2,
      reason:
          'Für JEDE aktive Person eine Zeile, nicht nur für die Anwesenden: '
          'Wer später herausfällt, soll davon erfahren, und ob er schon eine '
          'Abend-Meldung hat, weiß nur der Versender.',
    );
    handle.dispose();
  });

  // #177: Ab Freitagmittag zeigt der Planer die KOMMENDE Woche — der Korb
  // rechnet dann nur noch deren Zeilen. Räumt er dabei alles vor dem
  // nächsten Montag weg, nimmt er diesem Freitag die Zeilen, aus denen am
  // Nachmittag seine Rückfahrt-Erinnerung feuern muss (und mit ihnen die
  // Sofort-Meldungen des Tages, #163).
  //
  // Der Ablauf ist der echte: vormittags geschrieben, nachmittags neu
  // geöffnet. Ein von Hand in den Korb gelegter Eintrag prüfte nur, ob das
  // Fake filtert.
  testWidgets('am Freitagnachmittag überlebt der Freitag im Korb', (
    tester,
  ) async {
    final backend = await _backend(['Anna', 'Bert']);
    final friday = DateTime(2026, 7, 31);
    var now = DateTime(2026, 7, 31, 9);

    await pumpApp(
      tester,
      backend,
      overrides: [nowProvider.overrideWithValue(() => now)],
    );
    await _login(tester);

    final group = backend.currentGroupId!;
    expect(
      (backend.outbox[group] ?? const []).where((e) => e.date == friday),
      isNotEmpty,
      reason:
          'Vormittags gehört der Freitag zur Planwoche — ohne seine Zeilen '
          'prüfte der Rest dieses Tests nichts.',
    );

    // Nachmittags neu geöffnet: `planningWeek` steht jetzt auf der kommenden
    // Woche, der erste Schreibvorgang räumt auf.
    now = DateTime(2026, 7, 31, 14);
    await pumpApp(
      tester,
      backend,
      overrides: [nowProvider.overrideWithValue(() => now)],
    );
    if (find.widgetWithText(FilledButton, 'Anmelden').evaluate().isNotEmpty) {
      await _login(tester);
    }

    expect(
      planningWeek(now).first,
      DateTime(2026, 8, 3),
      reason:
          'Die Vorbedingung des Falls: Der Planer blickt voraus. Ohne sie '
          'liefe der Test gegen eine Woche, die den Freitag ohnehin enthält.',
    );
    expect(
      (backend.outbox[group] ?? const []).where((e) => e.date == friday),
      isNotEmpty,
      reason:
          'Der Planer darf vorausblicken, der Korb darf nicht den Tag '
          'wegwerfen, über den er noch meldet. Ohne diese Zeilen käme am '
          'Freitag um 16:20 keine Rückfahrt-Erinnerung — und niemand merkte '
          'es, weil ausbleibende Meldungen nichts rot machen.',
    );
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

    // Ein Tap trägt ein — der Alltagsfall bleibt ein Klick (#183).
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'dabei|fährt'), findsOneWidget);

    // Der zweite Tap schaltet NICHT weiter, sondern öffnet das Menü. Bei drei
    // Zuständen war das Durchschalten schon lästig; mit „fahren wollen" und
    // den Zeiten wäre es unbenutzbar geworden.
    await tester.tap(_cell('Anna', monday));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      _cell('Anna', monday, state: 'dabei|fährt'),
      findsOneWidget,
      reason: 'Das Öffnen allein darf noch nichts geändert haben.',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ListTile, 'nur eine Richtung'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_cell('Anna', monday, state: 'nur eine Richtung'), findsOneWidget);

    // Und wieder heraus — aus 1-way muss ein Weg zurückführen.
    await _pick(tester, 'Anna', monday, 'kann nicht');
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
    // Anna auf 1-way, Bert einfach dabei.
    await _pick(tester, 'Anna', monday, 'nur eine Richtung');
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
    await _pick(tester, 'Anna', monday, 'nur eine Richtung');

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
    // Montag: Anna fährt, Bert nur eine Richtung → 0,5.
    await tester.tap(_cell('Anna', week[0]));
    await tester.pumpAndSettle();
    await _pick(tester, 'Bert', week[0], 'nur eine Richtung');
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
    // Beide Fahrer tragen im Raster das Auto-Symbol — und seit #183 die
    // Nummer ihres Autos dahinter.
    final weekday = DateFormat('E', 'de').format(monday);
    expect(
      find.bySemanticsLabel(
        RegExp('^[^,]+, ${RegExp.escape(weekday)}, fährt, Auto \\d\$'),
      ),
      findsNWidgets(2),
    );
    handle.dispose();
  });

  // #183: Bei mehreren Autos muss man auf einen Blick sehen, mit wem man
  // fährt. Die Marke trägt Farbe UND Nummer; geprüft wird die Nummer, denn
  // die ist es, die ein Screenreader vorliest und die auch trägt, wenn
  // jemand Farbtöne nicht unterscheidet.
  testWidgets('bei zwei Autos sagt jede Zelle, in welchem sie sitzt', (
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

    final weekday = DateFormat('E', 'de').format(monday);
    // Alle vier sitzen in einem der beiden Autos, keiner ohne Zuordnung.
    expect(
      find.bySemanticsLabel(
        RegExp('^[^,]+, ${RegExp.escape(weekday)}, [^,]+, Auto [12]\$'),
      ),
      findsNWidgets(4),
    );
    // Und beide Autos sind wirklich besetzt — stünde überall „Auto 1",
    // wäre die Marke da und trotzdem wertlos.
    for (final number in [1, 2]) {
      expect(
        find.bySemanticsLabel(
          RegExp('^[^,]+, ${RegExp.escape(weekday)}, [^,]+, Auto $number\$'),
        ),
        findsNWidgets(2),
        reason: 'Zwei Zweisitzer: In jedem sitzen Fahrer plus ein Mitfahrer.',
      );
    }
    handle.dispose();
  });

  testWidgets('bei EINEM Auto bleibt die Marke weg', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, await _backend(['Anna', 'Bert']));
    await _login(tester);
    await _openPlan(tester);

    final monday = planningWeek(testToday).first;
    for (final name in ['Anna', 'Bert']) {
      await tester.tap(_cell(name, monday));
      await tester.pumpAndSettle();
    }

    final weekday = DateFormat('E', 'de').format(monday);
    expect(
      find.bySemanticsLabel(
        RegExp('^[^,]+, ${RegExp.escape(weekday)}, .*Auto \\d\$'),
      ),
      findsNothing,
      reason:
          'Bei einem Auto sitzen ohnehin alle darin. Eine Marke daran wäre '
          'Dekoration in einem Raster, das ohnehin dicht ist.',
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
    // Dora nur eine Richtung — sie zählt als Kopf, stellt aber kein Auto.
    await _pick(tester, 'Dora', monday, 'nur eine Richtung');

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

    testWidgets('die leere eigene Zelle trägt mit einem Tap ein', (
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
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Der Alltagsfall — sich für einen Tag eintragen — bleibt ein '
            'Klick. Ein Menü davor machte den häufigen Weg doppelt so teuer.',
      );
      // Als einzige Verfügbare wird sie sofort als Fahrerin vorgeschlagen,
      // die Zelle liest dann „fährt" statt „dabei".
      expect(_cell('Anna', monday, state: 'dabei|fährt'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('der zweite Tap auf die eigene Zelle öffnet das Menü', (
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
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason:
            'Statt auf eine vierte Zyklus-Stufe: 1-way, fahren wollen und '
            'die Zeiten des Tages stehen im Menü. Bei drei Stufen war das '
            'Durchschalten schon lästig.',
      );
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
    testWidgets('ohne gewählte Person trägt der erste Tap ein', (tester) async {
      final handle = tester.ensureSemantics();
      final (backend, _) = await backendWithIds(['Anna', 'Bert']);
      await pumpApp(tester, backend, identity: DeviceIdentity.skipped);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason:
            'Ohne Zuordnung zählt jede Zeile als eigene, nicht als fremde. '
            'Wer die Startabfrage übersprungen hat, hatte die Rückfrage nie '
            '— sie ihm jetzt zu geben hieße, ihn dafür zu bestrafen. Im '
            'Demo-Modus (README-Screenshots) ist die Zuordnung ohnehin aus.',
      );
      expect(_cell('Bert', monday, state: 'dabei|fährt'), findsOneWidget);
      handle.dispose();
    });

    // Der eigentliche Riegel des neuen Modells (#183): Eine fremde Zelle
    // öffnet das Menü AUCH LEER. Ohne das träfe ein Fehltipp jemand anderen
    // mit einem einzigen Klick — genau die Vertipper-Bremse aus #121, die
    // vorher am Durchschalten hing.
    testWidgets('eine leere fremde Zelle öffnet das Menü, statt einzutragen', (
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
      expect(_cell('Bert', monday, state: 'kann nicht'), findsOneWidget);
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        _cell('Bert', monday, state: 'kann nicht'),
        findsOneWidget,
        reason: 'Der Tipp allein darf für Bert noch nichts geändert haben.',
      );
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

  // „Ich möchte fahren" (#183) — die volle Matrix aus Zustand der Person
  // (leer / dabei / 1-way) × Zustand des Tages (Vorschlag / von Hand
  // gesetzt). Der erste Fall ist der gemeldete Fehler vom 07.08.: Der Pin
  // allein verfiel in `planWeek` als tote Auswahl, und sichtbar geschah
  // nichts. Seitdem gilt: Wer fahren will, wird zuerst eingetragen — und
  // ein Vorschlag wird ersetzt, eine Menschenentscheidung bekommt
  // Gesellschaft.
  group('Ich möchte fahren', () {
    testWidgets('leere fremde Zelle: trägt ein UND pinnt (der Repro-Fall)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = FakeBackend();
      final gid = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final ids = <String, String>{};
      for (final name in ['Anna', 'Bert']) {
        final person = await backend
            .dataFor(gid)
            .createPerson(Person(id: '', name: name, active: true));
        ids[name] = person.id;
      }
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: ids['Anna'], asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      // Anna trägt sich ein — sie ist damit die Vorgeschlagene.
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      // Berts LEERE Zelle: fremde Zeile, das Menü geht sofort auf.
      await _wantToDrive(tester, 'Bert', monday);

      expect(
        _cell('Bert', monday, state: 'fährt'),
        findsOneWidget,
        reason:
            'Der Pin allein verfiele als tote Auswahl — „Ich möchte fahren" '
            'muss Bert zuerst eintragen, sonst passiert sichtbar nichts.',
      );
      expect(
        find.textContaining('Bert fährt · von Hand gesetzt'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('auf einem Vorschlags-Tag wird ERSETZT — ein Auto', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      // Wer der Vorschlag ist, liegt bei Punktgleichheit nicht fest — der
      // Test nimmt, wen es getroffen hat, und lässt den ANDEREN wollen.
      final passenger = _personIn('dabei', monday, ['Anna', 'Bert']);
      await _wantToDrive(tester, passenger, monday);

      expect(
        find.textContaining('$passenger fährt · von Hand gesetzt'),
        findsOneWidget,
        reason: '„Ich möchte fahren" auf einem Vorschlag heißt: statt dessen.',
      );
      expect(
        find.textContaining('2 Autos'),
        findsNothing,
        reason:
            'Aus dem Ersetzen eines Vorschlags darf kein zweites Auto '
            'entstehen — das wäre die falsche Hälfte der Regel.',
      );
      handle.dispose();
    });

    testWidgets('zwei Freiwillige sind zwei Autos, niemand wird entpinnt', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      final passenger = _personIn('dabei', monday, ['Anna', 'Bert']);
      final suggested = passenger == 'Anna' ? 'Bert' : 'Anna';
      // Erst pinnt sich der Nicht-Vorgeschlagene …
      await _wantToDrive(tester, passenger, monday);
      // … dann will der andere AUCH fahren: Gesellschaft, kein Ersetzen.
      await _wantToDrive(tester, suggested, monday);

      expect(
        find.textContaining('fahren · 2 Autos · von Hand gesetzt'),
        findsOneWidget,
        reason:
            'Eine Menschenentscheidung löscht nie still eine andere — der '
            'zweite Freiwillige ist das zweite Auto (und bei nur zwei '
            'Leuten ehrlich: zwei Solo-Autos, kein Mitfahrer, zählt nichts).',
      );
      handle.dispose();
    });

    testWidgets('aus 1-way wird volle Fahrt plus Fahrer', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await _pick(tester, 'Bert', monday, 'nur eine Richtung');
      expect(find.textContaining('Anna fährt'), findsOneWidget);

      await _wantToDrive(tester, 'Bert', monday);

      expect(
        _cell('Bert', monday, state: 'fährt'),
        findsOneWidget,
        reason:
            '1-way schließt Fahren aus — der Pin allein verfiele. Fahren '
            'wollen heißt: beide Richtungen, also volle Fahrt.',
      );
      expect(
        find.textContaining('Bert fährt · von Hand gesetzt'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('leer auf einem GESETZTEN Tag: eintragen + zweites Auto', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert', 'Clara']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      final passenger = _personIn('dabei', monday, ['Anna', 'Bert']);
      await _wantToDrive(tester, passenger, monday);
      // Clara ist noch leer und will auf dem gesetzten Tag fahren.
      await _wantToDrive(tester, 'Clara', monday);

      expect(_cell('Clara', monday, state: 'fährt, Auto [12]'), findsOneWidget);
      expect(find.textContaining('2 Autos · von Hand gesetzt'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('1-way auf einem GESETZTEN Tag: volle Fahrt + zweites Auto', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert', 'Clara']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      final passenger = _personIn('dabei', monday, ['Anna', 'Bert']);
      await _wantToDrive(tester, passenger, monday);
      await _pick(tester, 'Clara', monday, 'nur eine Richtung');
      await _wantToDrive(tester, 'Clara', monday);

      expect(_cell('Clara', monday, state: 'fährt, Auto [12]'), findsOneWidget);
      expect(find.textContaining('2 Autos · von Hand gesetzt'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('beim aktuellen Fahrer erscheint der Eintrag nicht', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      // Anna ist als Einzige verfügbar und damit die Fahrerin — ihr Menü:
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Ich möchte fahren'),
        findsNothing,
        reason: 'Wer schon fährt, hat keinen Grund, es zu wollen.',
      );
      handle.dispose();
    });
  });

  // Wer die Zeit setzen darf (#188) — gemeldet am 07.08. aus 0.66.1: Der
  // Eintrag stand in JEDER Zelle. Ein Mitfahrer traf damit sein Auto, also
  // ein fremdes: Er verschob die Abfahrt eines Wagens, den er nicht fährt,
  // und schrieb dabei den ganzen Fahrersatz des Tages fest.
  //
  // Geprüft wird am geöffneten Menü, nicht an einem `find` ins Leere: Ein
  // Test, der nur sucht, wäre auch dann grün, wenn der Tap gar nichts
  // öffnet — dieselbe Lehre wie beim toten Update-Knopf in 0.37.0.
  group('Zeiten setzt, wer fährt (#188)', () {
    testWidgets('ein Mitfahrer bekommt den Eintrag nicht', (tester) async {
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
      final names = ['Anna', 'Bert', 'Clara', 'Dora'];
      for (final name in names) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      // Zwei Autos mit je zwei Plätzen: zwei Fahrer, zwei Mitfahrer.
      final rider = _personIn('dabei, Auto [12]', monday, names);
      await tester.tap(_cell(rider, monday));
      await tester.pumpAndSettle();

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason:
            'Die Zelle ist gefüllt, der Tap MUSS das Menü öffnen — sonst '
            'prüft der Rest dieses Tests gar nichts.',
      );
      expect(
        find.widgetWithText(ListTile, 'Ich möchte fahren'),
        findsOneWidget,
        reason:
            'Und es ist das richtige Menü: Ein Mitfahrer darf weiterhin '
            'alles, was ihn selbst betrifft.',
      );
      expect(
        find.widgetWithText(ListTile, 'Zeiten & Treffpunkt'),
        findsNothing,
        reason:
            'Nur nicht die Abfahrt eines Autos verschieben, das er nicht '
            'fährt — und schon gar nicht dessen Fahrer festschreiben.',
      );
      handle.dispose();
    });

    testWidgets('wer an dem Tag nicht mitfährt, erst recht nicht', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      // Anna fährt, Bert kann nur hin — 1-way schließt das Fahren aus.
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await _pick(tester, 'Bert', monday, 'nur eine Richtung');

      await tester.tap(_cell('Bert', monday, state: 'nur eine Richtung'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Zeiten & Treffpunkt'),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('der Fahrer behält ihn', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await tester.tap(_cell('Anna', monday, state: 'fährt'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(ListTile, 'Zeiten & Treffpunkt'),
        findsOneWidget,
        reason:
            'Die andere Richtung: Der Riegel darf den Weg nicht ganz '
            'zumauern — sonst könnte niemand mehr eine Zeit setzen.',
      );
      handle.dispose();
    });
  });

  // Das Einverständnis mit einer Abfahrt (#189, Stufe B2, entschieden
  // 07.08.): Wer sich in ein Auto mit abweichenden Bedingungen einträgt,
  // wird gefragt. Ja pinnt, Nein schließt aus — und erzwingt notfalls ein
  // zweites Auto. Die Tests TIPPEN und prüfen erst, dass der Dialog
  // überhaupt offen ist; ein reines `find` wäre auch bei einem toten Tap
  // grün (die 0.37.0-Lehre).
  group('Einverständnis mit einer Abfahrt (#189)', () {
    Future<FakeBackend> deviatingBackend() async {
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
      await data.createPerson(const Person(id: '', name: 'Bert', active: true));
      final monday = planningWeek(testToday).first;
      await data.setAvailability(monday, anna.id, PlanRide.full);
      // Annas Auto fährt früher — die Bedingung, um die es geht.
      await data.saveCarDefaults(
        monday,
        anna.id,
        const GroupDefaults(outboundTime: DayTime(6, 45)),
      );
      return backend;
    }

    testWidgets('Eintragen in ein abweichendes Auto fragt nach — Ja pinnt', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = await deviatingBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();

      expect(
        find.text('Andere Abfahrt'),
        findsOneWidget,
        reason:
            'Der Tap trägt ein UND muss fragen: Bert landet in einem Auto, '
            'das früher fährt als die festen Vorgaben.',
      );
      expect(find.textContaining('06:45'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Passt'));
      await tester.pumpAndSettle();

      final choices = await backend
          .dataFor(backend.currentGroupId!)
          .loadSeatChoices(monday, days: 1);
      expect(
        choices[monday]?.single.accepted,
        isTrue,
        reason: 'Das Ja ist ein Pin und muss in der Ablage stehen.',
      );
      expect(
        choices[monday]?.single.terms,
        '06:45||',
        reason:
            'Gespeichert wird, WOZU zugestimmt wurde — sonst wäre die '
            'Zusage ein Blankoscheck für jede spätere Zeit.',
      );

      // Erneut durchschalten (dabei → 1-way) fragt NICHT noch einmal: Die
      // Entscheidung zu genau diesen Bedingungen liegt vor.
      await tester.tap(_cell('Bert', monday, state: 'dabei'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(ListTile, 'nur eine Richtung'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsNothing);
      handle.dispose();
    });

    testWidgets('Nein schließt aus — und erzwingt das zweite Auto', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = await deviatingBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Nein, so nicht'));
      await tester.pumpAndSettle();

      expect(
        _cell('Bert', monday, state: 'fährt, Auto 2.*'),
        findsOneWidget,
        reason:
            '„Zu diesen Bedingungen nicht" heißt: jemand anderes muss '
            'fahren — hier kann das nur Bert selbst sein. Beim '
            'Spezialfahrer fährt niemand mit.',
      );
      expect(_cell('Anna', monday, state: 'fährt, Auto 1.*'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('das Menü zeigt die Bedingungen und lässt umentscheiden', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = await deviatingBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Passt'));
      await tester.pumpAndSettle();

      // Der Weg zum Umentscheiden: das eigene Zell-Menü.
      await tester.tap(_cell('Bert', monday, state: 'dabei'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Dein Auto fährt anders'),
        findsOneWidget,
        reason:
            'Ohne diesen Eintrag gäbe es kein „Nein in zwei Taps" — die '
            'Rückfrage beim Eintragen wäre die einzige Gelegenheit.',
      );
      await tester.tap(find.widgetWithText(ListTile, 'Dein Auto fährt anders'));
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Nein, so nicht'));
      await tester.pumpAndSettle();

      expect(
        _cell('Bert', monday, state: 'fährt, Auto 2.*'),
        findsOneWidget,
        reason: 'Das Umentscheiden wirkt sofort: eigenes Auto.',
      );

      // Der Fahrer selbst sieht den Eintrag nicht — er stimmt seiner
      // eigenen Abfahrt nicht zu.
      await tester.tap(_cell('Anna', monday, state: 'fährt, Auto 1.*'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Dein Auto fährt anders'),
        findsNothing,
      );
      handle.dispose();
    });
  });

  // Die nachträgliche Rückfrage (#200, Stufe 2 der Sitzwahl): Verschiebt der
  // Fahrer die Abfahrt, NACHDEM jemand zugesagt hat, veraltet die Zusage und
  // wirkt nicht mehr — bis v0.68.0 erfuhr man das nur passiv. Die Tests
  // tippen die echte Benachrichtigung an (`backend.tapPush`) und laufen
  // damit durch die Verdrahtung in `app.dart`, nicht an ihr vorbei.
  group('Erneut fragen, wenn die zugesagte Abfahrt sich verschiebt (#200)', () {
    /// Anna fährt und weicht ab (06:45), Bert kann ebenfalls — der Aufbau,
    /// in dem eine Zusage überhaupt entstehen kann.
    Future<(FakeBackend, String)> consentBackend() async {
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
      // Clara ist dabei, damit ein Nein überhaupt jemanden zum Fahren übrig
      // lässt — sonst wäre der Ersatzfahrer Bert selbst, und die Begründung
      // am gesperrten Eintrag läse „Bert wird gebraucht, Bert fährt sonst
      // nicht mit".
      final clara = await data.createPerson(
        const Person(id: '', name: 'Clara', active: true),
      );
      final monday = planningWeek(testToday).first;
      await data.setAvailability(monday, anna.id, PlanRide.full);
      await data.setAvailability(monday, clara.id, PlanRide.full);
      await data.saveCarDefaults(
        monday,
        anna.id,
        const GroupDefaults(outboundTime: DayTime(6, 45)),
      );
      return (backend, bert.id);
    }

    /// Bert trägt sich ein und sagt der Abfahrt zu.
    Future<void> consent(WidgetTester tester, DateTime monday) async {
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Passt'));
      await tester.pumpAndSettle();
    }

    /// Anna verschiebt ihre Abfahrt — **am Backend**, wie es ihr eigenes
    /// Gerät täte. Berts App weiß davon noch nichts.
    Future<void> moveDeparture(FakeBackend backend, DateTime monday) async {
      final data = backend.dataFor(backend.currentGroupId!);
      final anna = (await data.loadPersons()).firstWhere(
        (p) => p.name == 'Anna',
      );
      await data.saveCarDefaults(
        monday,
        anna.id,
        const GroupDefaults(outboundTime: DayTime(5, 30)),
      );
    }

    testWidgets('eine verschobene Abfahrt fragt den Zusager neu', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final (backend, bertId) = await consentBackend();
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: bertId, asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await consent(tester, monday);
      expect(
        find.text('Andere Abfahrt'),
        findsNothing,
        reason: 'Aufbau: Bert hat zu 06:45 zugesagt, es ist Ruhe.',
      );

      await moveDeparture(backend, monday);
      backend.tapPush();
      await tester.pumpAndSettle();

      expect(
        find.text('Andere Abfahrt'),
        findsOneWidget,
        reason:
            'Berts Zusage galt 06:45 und gilt nicht mehr. Ohne die Frage '
            'würde er stillschweigend auf 05:30 gezogen — genau das, was '
            'die Zusage verhindern soll.',
      );
      expect(find.textContaining('05:30'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, 'Nein, so nicht'));
      await tester.pumpAndSettle();

      final choices = await backend
          .dataFor(backend.currentGroupId!)
          .loadSeatChoices(monday, days: 1);
      expect(
        choices[monday]?.single.accepted,
        isFalse,
        reason: 'Die neue Antwort gilt der neuen Zeit, nicht der alten.',
      );
      expect(choices[monday]?.single.terms, '05:30||');
      handle.dispose();
    });

    testWidgets('der Tipp holt den Plan frisch — sonst fragt niemand', (
      tester,
    ) async {
      // Die zweite Hälfte des Features und die unsichtbare: Die
      // Plan-Provider überleben den Seitenwechsel. Ohne das Auffrischen
      // beim Tipp sähe Bert den Stand von vorhin — und die Rückfrage
      // wüsste gar nicht, dass seine Zusage überholt ist.
      final handle = tester.ensureSemantics();
      final (backend, bertId) = await consentBackend();
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: bertId, asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await consent(tester, monday);
      await moveDeparture(backend, monday);

      // Ohne Tipp bleibt der Schirm auf dem alten Stand — das ist der
      // Zustand, den das Auffrischen behebt.
      await tester.tap(find.text('Übersicht'));
      await tester.pumpAndSettle();
      await _openPlan(tester);
      expect(find.text('Andere Abfahrt'), findsNothing);

      backend.tapPush();
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Wegtippen ist eine Zusage — und fragt nicht wieder', (
      tester,
    ) async {
      // **Opt-out** (entschieden 08.08.): Wer nicht ablehnt, ist zugesagt.
      // Vorher schrieb ein Wegtippen gar nichts, und die Folge war still und
      // teuer — bei der nächsten Verschiebung fand die Rückfrage nichts
      // Veraltetes und schwieg, die Person wurde mitgezogen. Beide Hälften
      // hängen an diesem Test: die abgelegte Zusage UND dass sie die Frage
      // beruhigt, ohne dass es dafür einen Merker im Schirm braucht.
      final handle = tester.ensureSemantics();
      final (backend, bertId) = await consentBackend();
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: bertId, asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await consent(tester, monday);
      await moveDeparture(backend, monday);
      backend.tapPush();
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsNothing);

      final afterDismiss = await backend
          .dataFor(backend.currentGroupId!)
          .loadSeatChoices(monday, days: 1);
      expect(
        afterDismiss[monday]?.single.accepted,
        isTrue,
        reason: 'Wer nicht ablehnt, ist zugesagt — das gehört in die Ablage.',
      );
      expect(
        afterDismiss[monday]?.single.terms,
        '05:30||',
        reason: 'Und zwar zu den Bedingungen, die auf dem Schirm standen.',
      );

      // Jeder weitere Tipp lädt den Plan neu. Die Frage bleibt trotzdem
      // weg — nicht durch einen Merker im Schirm, sondern weil jetzt eine
      // gültige Entscheidung in der Ablage steht.
      backend.tapPush();
      await tester.pumpAndSettle();
      expect(
        find.text('Andere Abfahrt'),
        findsNothing,
        reason: 'Eine beantwortete Frage kommt nicht zurück.',
      );

      // **Verschiebt der Fahrer aber ERNEUT, ist es eine neue Frage.** Die
      // Zusage galt 05:30 und gilt für 04:15 nicht.
      final data = backend.dataFor(backend.currentGroupId!);
      final anna = (await data.loadPersons()).firstWhere(
        (p) => p.name == 'Anna',
      );
      await data.saveCarDefaults(
        monday,
        anna.id,
        const GroupDefaults(outboundTime: DayTime(4, 15)),
      );
      backend.tapPush();
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);
      expect(find.textContaining('04:15'), findsWidgets);
      handle.dispose();
    });

    testWidgets('ein erzwungenes Auto ist im Umschalter gesperrt (#203)', (
      tester,
    ) async {
      // Gemeldet am 08.08.: Das Abwählen des zweiten Fahrers wirkte nicht.
      // Es KONNTE nicht wirken — jemand hat dem ersten Auto abgesagt und
      // muss irgendwo sitzen, also setzt die Rechnung den Fahrer sofort
      // zurück. Der Dialog nahm die Anweisung trotzdem an und verwarf sie
      // stumm; das ist die Klasse „toter Knopf" aus 0.37.0. Jetzt steht der
      // Grund am Eintrag, und abwählen geht gar nicht erst.
      final handle = tester.ensureSemantics();
      final (backend, bertId) = await consentBackend();
      final monday = planningWeek(testToday).first;
      await pumpApp(
        tester,
        backend,
        identity: DeviceIdentity(personId: bertId, asked: true),
      );
      await _login(tester);
      await _openPlan(tester);

      // Bert lehnt Annas Abfahrt ab — das erzwingt ein zweites Auto.
      await tester.tap(_cell('Bert', monday));
      await tester.pumpAndSettle();
      expect(find.text('Andere Abfahrt'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Nein, so nicht'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Fahrer ändern').first);
      await tester.pumpAndSettle();
      expect(find.text('Wer fährt?'), findsOneWidget);

      final forced = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((t) => t.onChanged == null)
          .toList();
      expect(
        forced,
        hasLength(1),
        reason:
            'Genau ein Fahrer steht nur wegen der Absage im Satz — und der '
            'ist nicht abwählbar.',
      );
      expect(
        find.textContaining('wird gebraucht — Bert fährt sonst nicht mit'),
        findsOneWidget,
        reason:
            '„Ausgegraut" allein sagt nicht, warum — und schon gar nicht, '
            'mit wem man reden muss.',
      );

      // Und die Gegenprobe im selben Dialog: Annas Auto hat niemand
      // erzwungen, es bleibt abwählbar.
      final free = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .where((t) => t.onChanged != null);
      expect(free, isNotEmpty);
      handle.dispose();
    });

    testWidgets('ohne „Ich bin" fragt niemand nach', (tester) async {
      // Die Zuordnung ist ein Geräte-Merkmal (#121) — ohne sie weiß der
      // Schirm nicht, WESSEN Zusage überholt ist, und darf niemanden
      // ansprechen. Im Demo-Modus ist sie ohnehin aus; dort entstehen die
      // README-Screenshots.
      final handle = tester.ensureSemantics();
      final (backend, _) = await consentBackend();
      await pumpApp(tester, backend, identity: DeviceIdentity.skipped);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await consent(tester, monday);
      await moveDeparture(backend, monday);
      backend.tapPush();
      await tester.pumpAndSettle();

      expect(find.text('Andere Abfahrt'), findsNothing);
      handle.dispose();
    });
  });

  // Sein Auto aussuchen (#199) — der wörtliche Wunsch aus #189, den Stufe B2
  // offengelassen hatte: Der Pin bestätigte bis v0.67.0 nur den Platz, den
  // die Automatik ohnehin vergeben hatte. Die Tests TIPPEN, und der
  // Sperr-Test prüft, dass der Dialog offen BLEIBT — ein Eintrag, der
  // annimmt und still verfällt, sähe von außen genauso aus.
  group('Mit wem fahren? (#199)', () {
    /// Vier Zweisitzer, alle dabei — das ergibt zwei Autos mit je einem
    /// Mitfahrer.
    Future<FakeBackend> twoCarBackend() async {
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert', 'Cora', 'Dirk']) {
        final person = await data.createPerson(
          Person(id: '', name: name, active: true, seats: 2),
        );
        await data.setAvailability(monday, person.id, PlanRide.full);
      }
      return backend;
    }

    /// In welchem Auto [name] laut Raster sitzt — 1 oder 2.
    int carOfCell(String name, DateTime day) =>
        _cell(name, day, state: '.*Auto 1').evaluate().isNotEmpty ? 1 : 2;

    testWidgets('ein Mitfahrer wechselt sein Auto', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = await twoCarBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      // Wer fährt, entscheiden die Punkte — der Test hält sich daran, statt
      // eine Reihenfolge zu behaupten, die eine Formeländerung umwirft.
      final riders = ['Anna', 'Bert', 'Cora', 'Dirk']
          .where(
            (n) => _cell(n, monday, state: 'dabei.*').evaluate().isNotEmpty,
          )
          .toList();
      expect(riders, hasLength(2), reason: 'Aufbau: zwei Autos, zwei Sitze.');
      final rider = riders.first;
      final from = carOfCell(rider, monday);
      final toDriver = ['Anna', 'Bert', 'Cora', 'Dirk'].firstWhere(
        (n) =>
            _cell(n, monday, state: 'fährt.*').evaluate().isNotEmpty &&
            carOfCell(n, monday) != from,
      );

      await tester.tap(_cell(rider, monday, state: 'dabei.*'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ListTile, 'Mit wem fahren?'),
        findsOneWidget,
        reason: 'Ab zwei Autos gibt es etwas auszusuchen.',
      );
      await tester.tap(find.widgetWithText(ListTile, 'Mit wem fahren?'));
      await tester.pumpAndSettle();

      expect(
        find.text('Mit wem fährt $rider?'),
        findsOneWidget,
        reason: 'Der Tipp muss den Auswahl-Dialog wirklich öffnen.',
      );
      await tester.tap(find.widgetWithText(ListTile, toDriver));
      await tester.pumpAndSettle();

      expect(
        carOfCell(rider, monday),
        carOfCell(toDriver, monday),
        reason: 'Die Wahl wirkt sofort: $rider sitzt jetzt bei $toDriver.',
      );

      final choices = await backend
          .dataFor(backend.currentGroupId!)
          .loadSeatChoices(monday, days: 1);
      expect(
        choices[monday]?.single.accepted,
        isTrue,
        reason: 'Eine Wahl ist dieselbe Zeile wie ein „Passt" — ein Pin.',
      );
      handle.dispose();
    });

    testWidgets('„Egal" nimmt die Wahl zurück — ohne Fehlermeldung', (
      tester,
    ) async {
      // Die zweite Hälfte ist der eigentliche Test: Der Rückweg lief über
      // die Liste, die der Notifier selbst hält, und löschte darin — ein
      // `ConcurrentModificationError`, den der Schirm als „Speichern
      // fehlgeschlagen" meldete, OBWOHL gespeichert wurde. Im Browser
      // gefunden, nachdem die Suite grün war; deshalb prüft der Test die
      // Meldung mit und nicht nur das Ergebnis.
      final handle = tester.ensureSemantics();
      final backend = await twoCarBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      final names = ['Anna', 'Bert', 'Cora', 'Dirk'];
      final rider = names.firstWhere(
        (n) => _cell(n, monday, state: 'dabei.*').evaluate().isNotEmpty,
      );
      final from = carOfCell(rider, monday);
      final toDriver = names.firstWhere(
        (n) =>
            _cell(n, monday, state: 'fährt.*').evaluate().isNotEmpty &&
            carOfCell(n, monday) != from,
      );

      await tester.tap(_cell(rider, monday, state: 'dabei.*'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Mit wem fahren?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, toDriver));
      await tester.pumpAndSettle();
      expect(carOfCell(rider, monday), isNot(from));

      await tester.tap(_cell(rider, monday, state: 'dabei.*'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Mit wem fahren?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Egal'));
      await tester.pumpAndSettle();

      expect(
        find.text('Speichern fehlgeschlagen.'),
        findsNothing,
        reason: 'Eine Meldung über einen Fehler, den es nicht gab.',
      );
      expect(
        carOfCell(rider, monday),
        from,
        reason: 'Ohne Zusage verteilt MitFahrBar wieder wie zuvor.',
      );
      final choices = await backend
          .dataFor(backend.currentGroupId!)
          .loadSeatChoices(monday, days: 1);
      expect(choices[monday] ?? const [], isEmpty);
      handle.dispose();
    });

    testWidgets('ein volles Auto ist gesperrt, nicht überbucht', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = await twoCarBackend();
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      final names = ['Anna', 'Bert', 'Cora', 'Dirk'];
      final riders = names
          .where(
            (n) => _cell(n, monday, state: 'dabei.*').evaluate().isNotEmpty,
          )
          .toList();
      final rider = riders.first;
      final other = riders.last;
      final otherCar = carOfCell(other, monday);
      final otherDriver = names.firstWhere(
        (n) =>
            _cell(n, monday, state: 'fährt.*').evaluate().isNotEmpty &&
            carOfCell(n, monday) == otherCar,
      );

      // Der andere Mitfahrer sagt seinem Auto fest zu — der einzige
      // Mitfahrer-Platz des Zweisitzers ist damit vergeben.
      await tester.tap(_cell(other, monday, state: 'dabei.*'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Mit wem fahren?'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, otherDriver));
      await tester.pumpAndSettle();

      await tester.tap(_cell(rider, monday, state: 'dabei.*'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Mit wem fahren?'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, otherDriver),
          matching: find.textContaining('voll'),
        ),
        findsOneWidget,
        reason: '„Ausgegraut" allein sagt nicht, warum.',
      );
      final entry = tester.widget<ListTile>(
        find.widgetWithText(ListTile, otherDriver),
      );
      expect(entry.enabled, isFalse);

      await tester.tap(find.widgetWithText(ListTile, otherDriver));
      await tester.pumpAndSettle();
      expect(
        find.text('Mit wem fährt $rider?'),
        findsOneWidget,
        reason:
            'Der gesperrte Eintrag tut nichts — der Dialog bleibt offen. '
            'Ein angenommener Pin verfiele in planWeek still, und von '
            'außen sähe beides gleich aus.',
      );
      expect(carOfCell(rider, monday), isNot(otherCar));
      handle.dispose();
    });

    testWidgets('bei einem Auto und beim Fahrer fehlt der Eintrag', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final backend = FakeBackend();
      final id = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(id);
      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        final person = await data.createPerson(
          Person(id: '', name: name, active: true),
        );
        await data.setAvailability(monday, person.id, PlanRide.full);
      }
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      await tester.tap(_cell('Bert', monday, state: 'dabei'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(ListTile, 'Mit wem fahren?'),
        findsNothing,
        reason:
            'Bei einem Auto sitzen ohnehin alle darin — dieselbe Regel wie '
            'bei den Auto-Marken.',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Abbrechen'));
      await tester.pumpAndSettle();

      await tester.tap(_cell('Anna', monday, state: 'fährt'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ListTile, 'Mit wem fahren?'),
        findsNothing,
        reason: 'Ein Fahrer sitzt in seinem eigenen Auto.',
      );
      handle.dispose();
    });
  });

  // Sichtbarkeit der Abweichungen (#183) — der zweite gemeldete Fehler vom
  // 07.08.: Eine gespeicherte Auto-Zeit war NIRGENDS zu sehen; der Push
  // hätte zur neuen Zeit geweckt, aber kein Schirm sagte es.
  group('Abweichungen sichtbar', () {
    testWidgets('eine Tages-Abweichung steht an der Tageszeile', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await _openTimes(tester, 'Anna', monday);
      // Ein Auto: kein Umschalter, der Schirm bearbeitet den Tag.
      expect(find.text('Ganzer Tag'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Abfahrt hin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('hin 07:30'),
        findsOneWidget,
        reason: 'Die Abweichung muss an der Tageszeile stehen — im Text.',
      );
      expect(
        find.bySemanticsLabel(RegExp('Abweichende Zeiten')),
        findsOneWidget,
        reason: '… und als Uhr am Datum.',
      );
      handle.dispose();
    });

    testWidgets('eine Auto-Abweichung: Tageszeile, Fahrer-Glyph und Pin', (
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
      final names = ['Anna', 'Bert', 'Clara', 'Dora'];
      for (final name in names) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      final driver = _personIn('fährt, Auto [12]', monday, names);
      await _openTimes(tester, driver, monday);
      // Zwei Autos: Umschalter da, das eigene Auto ist vorgewählt.
      expect(find.text('Ganzer Tag'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Abfahrt hin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('hin 07:30'),
        findsOneWidget,
        reason:
            'Die Auto-Abweichung gehört an die Tageszeile („Auto N: …") — '
            'genau das fehlte im gemeldeten Fall.',
      );
      expect(
        _cell(driver, monday, state: 'fährt, Auto [12], andere Zeiten'),
        findsOneWidget,
        reason:
            'Und ans Raster: das Uhr-Glyph am Fahrer, dessen Auto abweicht — '
            'auch für den Screenreader.',
      );
      // Der Pin: Die Zeile in `plan_overrides` muss stehen. Sichtbar wird
      // „von Hand gesetzt" erst, wenn der Vorschlag kippen WÜRDE — die
      // festgeschriebene Menge ist ja gerade die vorgeschlagene. Genau
      // dafür ist der Pin da; geprüft wird deshalb die Ablage, nicht das
      // Etikett.
      final plan = await backend
          .dataFor(backend.currentGroupId!)
          .loadPlan(monday, days: 1);
      expect(
        plan.overrides[monday],
        isNotEmpty,
        reason:
            'Die Zeit zu setzen schreibt die Fahrer des Tages fest — sonst '
            'hinge sie morgen an einem anderen Auto, sobald jemand seine '
            'Verfügbarkeit ändert.',
      );
      handle.dispose();
    });

    testWidgets('nur der Treffpunkt: Marker statt Uhr', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, await _backend(['Anna', 'Bert']));
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      await tester.tap(_cell('Anna', monday));
      await tester.pumpAndSettle();
      await _openTimes(tester, 'Anna', monday);
      await tester.enterText(find.byType(TextField), 'Werkstor');
      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Werkstor'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Abweichender Treffpunkt')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Abweichende Zeiten')),
        findsNothing,
        reason: 'Ohne abweichende Zeit wäre die Uhr eine falsche Aussage.',
      );
      handle.dispose();
    });

    testWidgets('Auto-Treffpunkt: Marker-Glyph am Fahrer', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        await _seatBackend({'Anna': 2, 'Bert': 2, 'Clara': 2, 'Dora': 2}),
      );
      await _login(tester);
      await _openPlan(tester);

      final monday = planningWeek(testToday).first;
      final names = ['Anna', 'Bert', 'Clara', 'Dora'];
      for (final name in names) {
        await tester.tap(_cell(name, monday));
        await tester.pumpAndSettle();
      }
      final driver = _personIn('fährt, Auto [12]', monday, names);
      await _openTimes(tester, driver, monday);
      await tester.enterText(find.byType(TextField), 'Werkstor');
      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      expect(
        _cell(driver, monday, state: 'fährt, Auto [12], anderer Treffpunkt'),
        findsOneWidget,
      );
      expect(find.textContaining('Werkstor'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('eine verwaiste Auto-Zeile ist unsichtbar', (tester) async {
      final handle = tester.ensureSemantics();
      final backend = FakeBackend();
      final gid = backend.addGroup(
        handle: 'daciaracing',
        password: 'geheim123',
        name: 'Dacia Racing',
      );
      final data = backend.dataFor(gid);
      final ids = <String, String>{};
      for (final name in ['Anna', 'Bert', 'Clara']) {
        final person = await data.createPerson(
          Person(id: '', name: name, active: true),
        );
        ids[name] = person.id;
      }
      final monday = planningWeek(testToday).first;
      for (final name in ['Anna', 'Bert']) {
        await data.setAvailability(monday, ids[name]!, PlanRide.full);
      }
      // Claras Zeile ist übrig geblieben — sie fährt an dem Tag nicht.
      await data.saveCarDefaults(
        monday,
        ids['Clara']!,
        const GroupDefaults(outboundTime: DayTime(5, 0)),
      );
      await pumpApp(tester, backend);
      await _login(tester);
      await _openPlan(tester);

      expect(
        find.textContaining('05:00'),
        findsNothing,
        reason:
            'Die Zeile wirkt beim Auflösen nicht — sie anzuzeigen hieße, '
            'eine Zeit zu behaupten, zu der niemand geweckt wird. Der '
            'gemeldete Fehler mit umgekehrtem Vorzeichen.',
      );
      expect(find.bySemanticsLabel(RegExp('Abweichende Zeiten')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('andere Zeiten')),
        findsNothing,
        reason:
            'Auch kein Glyph an irgendeiner Zelle — die Tageszeile und das '
            'Raster sind zwei Anzeigen, und beide müssen die verwaiste '
            'Zeile ignorieren.',
      );
      handle.dispose();
    });
  });
}

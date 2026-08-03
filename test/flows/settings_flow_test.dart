/// settings_flow_test.dart – Der Parameter-Screen über die echte App
/// (Issue #91).
///
/// Der eigentliche Inhalt dieses Tests ist nicht das Formular, sondern die
/// Grenze: Gespeichert werden **nur** Arbeitsweg und Preise. `one_way_factor`
/// und `points_weight` müssen die Runde unverändert überstehen — sie
/// verschieben rückwirkend die Punkte aller und gehören deshalb nicht in
/// einen Screen, den jedes Mitglied öffnen kann.
library;

import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Gruppe mit einer gefahrenen Fahrt — damit die Statistik echte Kilometer
/// zeigt, an denen die geänderte Strecke sichtbar wird.
Future<FakeBackend> _backend({AppSettings? settings}) async {
  final backend = FakeBackend();
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(groupId);
  if (settings != null) await data.saveSettings(settings);
  await data.createPerson(
    const Person(
      id: '',
      name: 'Anna',
      active: true,
      energyType: EnergyType.diesel,
      consumptionPer100km: 6,
    ),
  );
  await data.createPerson(const Person(id: '', name: 'Ben', active: true));
  final ids = {for (final p in await data.loadPersons()) p.name: p.id};
  await data.createTrip(DateTime(2026, 7, 20), {
    ids['Anna']!: ParticipationStatus.driver,
    ids['Ben']!: ParticipationStatus.passenger,
  });
  return backend;
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Parameter'));
  await tester.pumpAndSettle();
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

void main() {
  testWidgets('der Arbeitsweg lässt sich ändern und wirkt in der Statistik', (
    tester,
  ) async {
    // Hohe Fläche: Die Personen-Karten stehen seit v0.56.0 am ENDE der
    // Statistik-Chart-Seite — auf der Standardgröße baute die ListView sie
    // nie, und der km-Nachweis unten fände nichts.
    tester.view.physicalSize = const Size(420, 5200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = await _backend();
    await pumpApp(tester, backend);
    await _login(tester);
    await _openSettings(tester);

    // Vorbelegt mit dem Stand der Gruppe, deutsch geschrieben.
    expect(find.text('30,00'), findsOneWidget);

    await tester.enterText(_field('Arbeitsweg einfach (km)'), '42,5');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    final saved = await backend.dataFor('group-1').loadSettings();
    expect(saved.commuteKm, 42.5);

    // Und die Statistik rechnet sofort damit: 1 Fahrtag × 42,5 km × 2.
    await tester.tap(find.text('Statistik'));
    await tester.pumpAndSettle();
    expect(find.text('85 km'), findsNWidgets(2));
  });

  testWidgets('Punkte-Parameter überstehen das Speichern unverändert', (
    tester,
  ) async {
    // Eine Gruppe, die bewusst NICHT auf den Vorgaben steht.
    final backend = await _backend(
      settings: const AppSettings(oneWayFactor: 0.25, pointsWeight: 0.5),
    );
    await pumpApp(tester, backend);
    await _login(tester);
    await _openSettings(tester);

    await tester.enterText(_field('Dieselpreis (€ je Liter)'), '1,95');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    final saved = await backend.dataFor('group-1').loadSettings();
    expect(saved.dieselPricePerLiter, 1.95);
    // Die beiden Werte darf der Screen nicht anfassen — sonst änderte ein
    // Preis-Update rückwirkend die Punkte der ganzen Gruppe.
    expect(saved.oneWayFactor, 0.25);
    expect(saved.pointsWeight, 0.5);
  });

  testWidgets('Unsinn im Feld wird abgefangen, nicht gespeichert', (
    tester,
  ) async {
    final backend = await _backend();
    await pumpApp(tester, backend);
    await _login(tester);
    await _openSettings(tester);

    await tester.enterText(_field('Arbeitsweg einfach (km)'), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    expect(find.text('Arbeitsweg bitte als Zahl größer 0.'), findsOneWidget);
    final saved = await backend.dataFor('group-1').loadSettings();
    expect(saved.commuteKm, 30);
  });
}

/// settings_flow_test.dart – Der Parameter-Screen über die echte App
/// (Issues #91, #139).
///
/// Der eigentliche Inhalt dieses Tests ist nicht das Formular, sondern die
/// Grenze: Gespeichert werden **nur** Werte, die die Punkte nie berühren.
/// `one_way_factor` und `points_weight` müssen die Runde unverändert
/// überstehen — sie verschieben rückwirkend die Punkte aller und gehören
/// deshalb nicht in einen Screen, den jedes Mitglied öffnen kann.
///
/// Seit #139 steht daneben „Fahrt & Treffpunkt". Es schreibt in eine ANDERE
/// Tabelle (`group_defaults`), am selben Knopf — geprüft wird deshalb beides
/// zusammen: dass die Vorgaben ankommen und dass die Punkte-Parameter dabei
/// unangetastet bleiben.
library;

import 'package:mitfahrbar/models/app_settings.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

/// Gruppe mit einer gefahrenen Fahrt — damit die Statistik echte Kilometer
/// zeigt, an denen die geänderte Strecke sichtbar wird.
Future<FakeBackend> _backend({
  AppSettings? settings,
  GroupDefaults? defaults,
}) async {
  final backend = FakeBackend();
  final groupId = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  final data = backend.dataFor(groupId);
  if (settings != null) await data.saveSettings(settings);
  if (defaults != null) await data.saveGroupDefaults(defaults);
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

/// Hohe Fläche, damit das ganze Formular gebaut wird.
///
/// Seit #139 steht unter den Kosten-Werten noch „Fahrt & Treffpunkt": Auf der
/// Standardgröße liegen Zeit-Zeilen und Speichern-Knopf außerhalb, und eine
/// ListView baut, was sie nicht zeigt, gar nicht erst.
void _tall(WidgetTester tester, {double height = 1800}) {
  tester.view.physicalSize = Size(420, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

/// Die Zeile einer Vorgabe-Zeit — Titel und Wert stehen darin.
Finder _timeTile(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(ListTile));

void main() {
  testWidgets('der Arbeitsweg lässt sich ändern und wirkt in der Statistik', (
    tester,
  ) async {
    // Noch höher: Die Personen-Karten stehen seit v0.56.0 am ENDE der
    // Statistik-Chart-Seite — auf der Standardgröße baute die ListView sie
    // nie, und der km-Nachweis unten fände nichts.
    _tall(tester, height: 5200);

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
    _tall(tester);
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
    _tall(tester);
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

  testWidgets('Fahrt & Treffpunkt landen in den Vorgaben (#139)', (
    tester,
  ) async {
    _tall(tester);
    final backend = await _backend(
      settings: const AppSettings(oneWayFactor: 0.25, pointsWeight: 0.5),
    );
    await pumpApp(tester, backend);
    await _login(tester);
    await _openSettings(tester);

    // Ungepflegt heißt ungepflegt — der Screen erfindet keine Uhrzeit.
    expect(
      find.descendant(
        of: _timeTile('Abfahrt hin'),
        matching: find.text('Nicht festgelegt'),
      ),
      findsOneWidget,
    );

    // Der Wähler startet auf 7:30; „OK" übernimmt genau das.
    await tester.tap(find.text('Abfahrt hin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: _timeTile('Abfahrt hin'),
        matching: find.text('07:30 Uhr'),
      ),
      findsOneWidget,
    );

    await tester.enterText(_field('Treffpunkt'), 'Parkplatz Rathaus');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    final data = backend.dataFor('group-1');
    final saved = await data.loadGroupDefaults();
    expect(saved.outboundTime, const DayTime(7, 30));
    expect(saved.meetingPoint, 'Parkplatz Rathaus');
    // Nicht angefasst bleibt nicht gesetzt: Ein Speichern darf keine
    // Rückfahrzeit erfinden.
    expect(saved.returnTime, isNull);

    // Und die Punkte-Parameter überstehen auch den zweiten Schreibweg.
    final settings = await data.loadSettings();
    expect(settings.oneWayFactor, 0.25);
    expect(settings.pointsWeight, 0.5);
  });

  testWidgets('eine gesetzte Zeit lässt sich wieder leeren', (tester) async {
    _tall(tester);
    final backend = await _backend(
      defaults: const GroupDefaults(
        outboundTime: DayTime(7, 15),
        returnTime: DayTime(16, 30),
        meetingPoint: 'Parkplatz Rathaus',
      ),
    );
    await pumpApp(tester, backend);
    await _login(tester);
    await _openSettings(tester);

    expect(
      find.descendant(
        of: _timeTile('Abfahrt hin'),
        matching: find.text('07:15 Uhr'),
      ),
      findsOneWidget,
    );

    // Ohne diesen Weg wäre eine einmal gesetzte Zeit nicht mehr loszuwerden:
    // Der Wähler kennt kein „nichts", und der Upsert schreibt immer alle
    // drei Felder.
    await tester.tap(
      find.descendant(
        of: _timeTile('Abfahrt hin'),
        matching: find.byIcon(Icons.backspace_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(_field('Treffpunkt'), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
    await tester.pumpAndSettle();

    final saved = await backend.dataFor('group-1').loadGroupDefaults();
    expect(saved.outboundTime, isNull);
    expect(saved.meetingPoint, isNull);
    // Die andere Zeit bleibt stehen — geleert wird, was geleert wurde.
    expect(saved.returnTime, const DayTime(16, 30));
  });
}

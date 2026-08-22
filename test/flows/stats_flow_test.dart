/// stats_flow_test.dart – Die Statistik-Seite als Chart-Seite (v0.56.0).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/price_area.dart';
import 'package:mitfahrbar/models/trip.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

String _setUpGroup(FakeBackend backend) => backend.addGroup(
  handle: 'daciaracing',
  password: 'geheim123',
  name: 'Dacia Racing',
);

/// Sehr hohe Testfläche: Die Seite trägt acht Sektionen, und die ListView
/// baut nur, was sichtbar ist — auf einer normalen Fläche wäre ein
/// `findsNothing` für die unteren Karten auch dann erfüllt, wenn sie
/// existieren (dieselbe Falle wie im Dashboard-Flow-Test).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 5200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _openStats(WidgetTester tester) async {
  await tester.tap(find.text('Statistik'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mit vollen Daten zeigt die Statistik alle Sektionen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    final data = backend.dataFor(groupId);

    final ids = <String>[];
    for (final person in const [
      Person(
        id: '',
        name: 'Anna',
        active: true,
        energyType: EnergyType.diesel,
        consumptionPer100km: 6,
      ),
      Person(
        id: '',
        name: 'Bert',
        active: true,
        energyType: EnergyType.petrol,
        consumptionPer100km: 8,
      ),
      // Ohne Verbrauch: spart nichts, fährt aber mit.
      Person(id: '', name: 'Clara', active: true),
    ]) {
      ids.add((await data.createPerson(person)).id);
    }
    final (anna, bert, clara) = (ids[0], ids[1], ids[2]);

    // Alle Daten relativ zu [testToday] (Mi, 22.07.2026): Anna fährt vier
    // Mittwoche (Dominanz 4/5), Bert Freitag/Mittwoch/Samstag; ein Solo-Tag
    // am 16.07. bricht die Serie nach fünf Fahrtagen.
    Future<void> ride(DateTime day, String driver, List<String> riders) =>
        data.createTrip(day, {
          driver: ParticipationStatus.driver,
          for (final rider in riders) rider: ParticipationStatus.passenger,
        });
    await ride(DateTime(2026, 6, 24), anna, [bert]);
    await ride(DateTime(2026, 7, 1), anna, [bert]);
    await ride(DateTime(2026, 7, 8), anna, [bert]);
    // Anna, nicht Bert: Im Juli braucht der Kilometerheld einen klaren
    // Sieger — bei Gleichstand entschiede die generierte Id.
    await ride(DateTime(2026, 7, 10), anna, [bert]);
    await ride(DateTime(2026, 7, 15), bert, [anna]);
    await ride(DateTime(2026, 7, 16), anna, const []); // solo
    await ride(DateTime(2026, 7, 18), bert, [anna, clara]); // Samstag
    await ride(testToday, anna, [bert, clara]);

    // Gemessene Wochenwerte, damit die Sektion „Spritpreise" erscheint —
    // samt Region, wie bei einer Gruppe, die das Archiv wirklich benutzt.
    final prices = FakePriceRepository(backend);
    prices.areas[groupId] = const PriceArea(
      label: 'Bad Rappenau',
      lat: 49.24,
      lng: 9.1,
    );
    prices.weeks[groupId] = [
      for (final week in const [28, 29, 30]) ...[
        PricePoint(
          week: IsoWeek(2026, week),
          series: PriceSeries.diesel,
          value: 1.60,
          origin: PriceOrigin.measured,
        ),
        PricePoint(
          week: IsoWeek(2026, week),
          series: PriceSeries.e5,
          value: 1.75,
          origin: PriceOrigin.measured,
        ),
      ],
    ];

    await pumpApp(
      tester,
      backend,
      overrides: [priceRepositoryProvider.overrideWithValue(prices)],
    );
    await _login(tester);
    await _openStats(tester);

    // Alle Karten-Titel der Seite.
    expect(find.text('Fahrten pro Woche'), findsOneWidget);
    expect(find.text('Gemeinsam gespart'), findsOneWidget);
    expect(find.text('Wer hat wie viel erspart?'), findsOneWidget);
    expect(find.text('CO₂ eingespart'), findsOneWidget);
    expect(find.text('Spritpreise'), findsOneWidget);
    expect(find.text('Wie ihr unterwegs seid'), findsOneWidget);
    expect(find.text('Euer Wochen-Muster'), findsOneWidget);
    expect(find.text('Alle Zahlen je Person'), findsOneWidget);

    // Fahrten pro Woche: Ø und Rekord stehen im Untertitel; der Rekord
    // (KW 29, drei Fahrten) liegt im Fenster.
    expect(
      find.textContaining('Ø 0,7 je Woche · Rekord: KW 29 mit 3 Fahrten'),
      findsOneWidget,
    );
    expect(find.text('Rekord'), findsOneWidget, reason: 'Legenden-Chip');

    // Die Ring-Mitte trägt die Summe als Widget — samt Untertitel-Zusage,
    // dass es die Zahl der Übersicht ist.
    expect(find.text('zusammen'), findsOneWidget);
    expect(
      find.textContaining('zusammen die Zahl der Übersicht'),
      findsOneWidget,
    );

    // CO₂: Kachel erklärt die Rechnung, die Solo-km-Kachel steht daneben.
    expect(find.textContaining('E-Autos zählen 0'), findsOneWidget);
    expect(find.text('Solo-Fahrten vermieden'), findsOneWidget);

    // Unterwegs: Saldo je Person und genau EINE „ist dran"-Marke.
    expect(find.textContaining('· Saldo'), findsWidgets);
    expect(find.text('ist dran'), findsOneWidget);

    // Heatmap: Mo–Fr immer, die Samstagsfahrt öffnet Sa, So bleibt zu.
    for (final label in const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa']) {
      expect(find.text(label), findsOneWidget, reason: 'Spalte $label');
    }
    expect(find.text('So'), findsNothing);
    expect(
      find.textContaining('Mittwochs fährt fast immer Anna'),
      findsOneWidget,
    );

    // Insights: deterministisch an [testToday] (KW 30, vier verfügbare
    // Karten → Offset 2): Kilometerheld und Serien-Rekord.
    expect(find.textContaining('KILOMETERHELD · JULI'), findsOneWidget);
    expect(find.textContaining('240 km am Steuer'), findsOneWidget);
    expect(find.text('SERIEN-REKORD'), findsOneWidget);
    expect(
      find.text('5 Fahrtage in Folge ohne Solo-Fahrt.'),
      findsOneWidget,
      reason: 'der Solo-Tag am 16.07. beendet die Serie — kein „läuft noch"',
    );

    // Der Verwaltungs-Knopf der Preis-Sektion führt nach /prices. Erkannt
    // am eingerichteten Bereich, nicht mehr am Abfrage-Knopf: Der ist mit
    // dem Live-Takt gefallen, und „&  Abruf" stand nur noch für ihn.
    await tester.tap(find.text('Preis-Region'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Umkreis 20 km'), findsOneWidget);
  });

  testWidgets('ohne Verbrauch und Preise bleiben Fahrten und Muster', (
    tester,
  ) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    final data = backend.dataFor(groupId);
    final anna = (await data.createPerson(
      const Person(id: '', name: 'Anna', active: true),
    )).id;
    final bert = (await data.createPerson(
      const Person(id: '', name: 'Bert', active: true),
    )).id;
    await data.createTrip(testToday, {
      anna: ParticipationStatus.driver,
      bert: ParticipationStatus.passenger,
    });
    await data.createTrip(testToday.subtract(const Duration(days: 7)), {
      bert: ParticipationStatus.driver,
      anna: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);
    await _openStats(tester);

    // Ohne Verbrauchsdaten gibt es nichts zu sparen und kein CO₂; ohne
    // Wochenwerte keine Preis-Sektion. DIE FAHRTEN BLEIBEN: „Fahrten pro
    // Woche" hängt bewusst nicht am Preisarchiv.
    expect(find.text('Fahrten pro Woche'), findsOneWidget);
    expect(find.text('Wie ihr unterwegs seid'), findsOneWidget);
    expect(find.text('Euer Wochen-Muster'), findsOneWidget);
    expect(find.text('Gemeinsam gespart'), findsNothing);
    expect(find.text('Wer hat wie viel erspart?'), findsNothing);
    expect(find.text('CO₂ eingespart'), findsNothing);
    expect(find.text('Spritpreise'), findsNothing);

    // Zwei berechenbare Insights (Strecke, Kilometerheld) — beide gezeigt,
    // die Rotation greift erst oberhalb der Platzzahl.
    expect(find.text('STRECKEN-MEILENSTEIN'), findsOneWidget);
    expect(find.textContaining('KILOMETERHELD'), findsOneWidget);
    expect(find.text('SERIEN-REKORD'), findsNothing);

    // Die Personen-Karten stehen weiterhin am Ende.
    expect(find.text('Alle Zahlen je Person'), findsOneWidget);
    expect(find.text('Punkte'), findsNWidgets(2));
  });

  testWidgets('ohne Fahrten bleiben die Diagramme aus', (tester) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    await backend
        .dataFor(groupId)
        .createPerson(const Person(id: '', name: 'Anna', active: true));

    await pumpApp(tester, backend);
    await _login(tester);
    await _openStats(tester);

    expect(find.text('Fahrten pro Woche'), findsNothing);
    expect(find.text('Euer Wochen-Muster'), findsNothing);
    expect(find.text('Gemeinsam gespart'), findsNothing);
  });
}

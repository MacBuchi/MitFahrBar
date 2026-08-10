/// dashboard_charts_flow_test.dart – Die Auswertungen auf der Startseite.
library;

import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/widgets/savings_chart.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/person.dart';
import 'package:mitfahrbar/models/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show NumberFormat;

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

/// Hohe Testfläche: Die ListView baut nur, was sichtbar ist – auf der
/// Standardgröße läge die Hälfte der Karten unter der Kante, und ein
/// `findsNothing` wäre dann auch dann erfüllt, wenn die Karte existiert.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('mit Fahrten zeigt die Startseite die Auswertungen', (
    tester,
  ) async {
    _useTallSurface(tester);
    final backend = FakeBackend();
    final groupId = _setUpGroup(backend);
    final data = backend.dataFor(groupId);

    final ids = <String>[];
    for (final name in ['Anna', 'Bert']) {
      final person = await data.createPerson(
        Person(id: '', name: name, active: true),
      );
      ids.add(person.id);
    }
    // An [testToday], NICHT an DateTime.now(): Die App läuft in Flow-Tests
    // an einer festen Uhr. Eine Fahrt an der echten Wanduhr läge, sobald
    // der Kalender weiterzieht, aus Sicht der App in der Zukunft — genau
    // so ist ein Vorgänger dieses Tests am 01.08.2026 von selbst rot
    // geworden, ohne dass jemand Code angefasst hatte.
    await data.createTrip(testToday, {
      ids[0]: ParticipationStatus.driver,
      ids[1]: ParticipationStatus.passenger,
    });
    await data.createTrip(testToday.subtract(const Duration(days: 7)), {
      ids[1]: ParticipationStatus.driver,
      ids[0]: ParticipationStatus.passenger,
    });

    await pumpApp(tester, backend);
    await _login(tester);

    expect(find.text('Gemeinsam erreicht'), findsOneWidget);
    expect(find.text('Fahrten und Ersparnis'), findsOneWidget);
    expect(find.text('Wie ihr unterwegs seid'), findsOneWidget);
    // Die Legende benennt die Kategorien – Farbe allein trägt die Zuordnung
    // nie allein. Die Säulen brauchen die Nennung doppelt: Sie haben keine
    // Achse, die sie erklärt.
    expect(find.text('gefahren'), findsOneWidget);
    expect(find.text('mitgefahren'), findsOneWidget);
    expect(find.text('1-way'), findsOneWidget);
    expect(find.text('Fahrten je Woche'), findsOneWidget);
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

    // Eine leere Achse sagt weniger als gar keine Karte.
    expect(find.text('Fahrten und Ersparnis'), findsNothing);
    expect(find.text('Wie ihr unterwegs seid'), findsNothing);
  });

  group('Ersparnis-Diagramm', () {
    /// Zwei Personen mit Fahrzeug — ohne Verbrauch gibt es keine Ersparnis,
    /// und die Karte hätte nichts zu zeigen.
    Future<(String, List<String>)> seedDrivers(FakeBackend backend) async {
      final groupId = _setUpGroup(backend);
      final data = backend.dataFor(groupId);
      final ids = <String>[];
      for (final name in ['Anna', 'Bert']) {
        final person = await data.createPerson(
          Person(
            id: '',
            name: name,
            active: true,
            energyType: EnergyType.diesel,
            consumptionPer100km: 6,
          ),
        );
        ids.add(person.id);
      }
      // Zwei Fahrten in verschiedenen Wochen, Rollen getauscht: So hat jede
      // Person eine eigene Linie.
      await data.createTrip(testToday, {
        ids[0]: ParticipationStatus.driver,
        ids[1]: ParticipationStatus.passenger,
      });
      await data.createTrip(testToday.subtract(const Duration(days: 7)), {
        ids[1]: ParticipationStatus.driver,
        ids[0]: ParticipationStatus.passenger,
      });
      return (groupId, ids);
    }

    testWidgets('die Karte zeigt beide Personen und die Gruppe', (
      tester,
    ) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await seedDrivers(backend);

      await pumpApp(tester, backend);
      await _login(tester);

      expect(find.text('Fahrten und Ersparnis'), findsOneWidget);
      // Die Legende benennt jede Linie — Farbe allein trägt die Zuordnung
      // nie allein, und bei mehreren Personen schon gar nicht.
      expect(find.text('Zusammen'), findsOneWidget);
      expect(find.widgetWithText(SavingsTrendChart, 'Anna'), findsOneWidget);
      expect(find.widgetWithText(SavingsTrendChart, 'Bert'), findsOneWidget);
    });

    testWidgets('ein Tipp auf einen Namen blendet dessen Linie aus', (
      tester,
    ) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await seedDrivers(backend);

      await pumpApp(tester, backend);
      await _login(tester);

      // Der Namens-Text im Diagramm — nicht `widgetWithText(SavingsTrend…)`:
      // Das fände das CHART-Widget, und ein Tap darauf träfe den Canvas
      // statt des Chips (beim Schreiben dieses Tests genau so passiert).
      Finder chip(String name) => find.descendant(
        of: find.byType(SavingsTrendChart),
        matching: find.text(name),
      );
      Opacity chipOf(String name) => tester.widget<Opacity>(
        find.ancestor(of: chip(name), matching: find.byType(Opacity)).first,
      );

      expect(chipOf('Anna').opacity, 1);

      // Getippt, nicht nur gefunden — ein toter Chip sähe genauso aus.
      await tester.tap(chip('Anna'));
      await tester.pumpAndSettle();
      expect(
        chipOf('Anna').opacity,
        lessThan(1),
        reason: 'der abgewählte Name muss sich sichtbar abwählen',
      );
      expect(chipOf('Bert').opacity, 1, reason: 'nur Anna war gemeint');

      // Der zweite Tipp holt die Linie zurück.
      await tester.tap(chip('Anna'));
      await tester.pumpAndSettle();
      expect(chipOf('Anna').opacity, 1);
    });

    testWidgets('Kachel und Diagramm nennen dieselbe Summe', (tester) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      final (groupId, _) = await seedDrivers(backend);
      final prices = FakePriceRepository(backend);
      // Ein gemessener Wochenpreis weit über der Konstante: Rechnete die
      // Kachel weiter über `savedCosts` mit der Konstante und nur das
      // Diagramm je Woche, liefen die beiden Zahlen hier auseinander — und
      // zwar sichtbar untereinander auf derselben Seite.
      prices.weeks[groupId] = [
        for (var back = 0; back < 3; back++)
          PricePoint(
            week: IsoWeek.of(testToday.subtract(Duration(days: 7 * back))),
            series: PriceSeries.diesel,
            value: 5,
            origin: PriceOrigin.measured,
          ),
      ];

      await pumpApp(
        tester,
        backend,
        overrides: [priceRepositoryProvider.overrideWithValue(prices)],
      );
      await _login(tester);

      // 2 Mitfahrten × 6 l/100 km × 60 km × 5 €/l = 36 €. Der Betrag wird
      // über dasselbe NumberFormat erzeugt wie im Code — deutsches
      // Währungsformat trennt mit einem geschützten Leerzeichen, ein
      // getipptes Leerzeichen fände nichts.
      final expected = NumberFormat.currency(
        locale: 'de',
        symbol: '€',
        decimalDigits: 0,
      ).format(36);

      expect(
        find.textContaining(expected),
        findsNWidgets(2),
        reason:
            'genau zwei Stellen nennen die Summe — die Kachel „Kraftstoff '
            'gespart" und der Untertitel der Karte. Rechnete die Kachel '
            'weiter mit der Konstante, stünden hier zwei verschiedene Zahlen.',
      );
      expect(find.textContaining('$expected seit'), findsOneWidget);
    });

    testWidgets('ohne Preise fehlt die Kachel, statt 0 € zu behaupten', (
      tester,
    ) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await seedDrivers(backend);

      await pumpApp(
        tester,
        backend,
        overrides: [
          priceRepositoryProvider.overrideWithValue(_NoPrices(backend)),
        ],
      );
      await _login(tester);

      // Der Fall aus dem Funkloch: Das Preisarchiv ist bewusst nicht im
      // Zwischenspeicher, die Ersparnis lässt sich also nicht rechnen. Bis
      // v0.79.0 stand die Kachel dann auf „0 €" — eine erfundene Zahl neben
      // zwei echten, unter einer Leiste, die „Stand heute 07:12" sagt.
      expect(
        find.text('Gemeinsam erreicht'),
        findsOneWidget,
        reason: 'Personen-km und Fahrten stimmen auch ohne Preise',
      );
      expect(find.text('Personen-km'), findsOneWidget);
      expect(find.text('Kraftstoff gespart'), findsNothing);
      expect(
        find.text(
          NumberFormat.currency(
            locale: 'de',
            symbol: '€',
            decimalDigits: 0,
          ).format(0),
        ),
        findsNothing,
      );
    });

    testWidgets('ohne gemessenen Preis ist die Kurve als geschätzt markiert', (
      tester,
    ) async {
      _useTallSurface(tester);
      final backend = FakeBackend();
      await seedDrivers(backend);

      await pumpApp(tester, backend);
      await _login(tester);

      // Keine Preiszeile: Die ganze Kurve steht auf der Konstante aus den
      // Parametern. Ohne diesen Hinweis sähe eine gerechnete Linie aus wie
      // eine gemessene — dieselbe Regel wie im Preis-Diagramm.
      expect(find.text('Preis geschätzt'), findsOneWidget);
    });
  });
}

/// Ein Preisarchiv, das nicht antwortet — der Zustand ohne Empfang.
///
/// Es ist bewusst nicht im Zwischenspeicher (die mit Abstand meisten Zeilen,
/// entschieden 05.08.2026); ohne Netz gibt es also keine Wochenpreise, und
/// die Ersparnis ist schlicht unbekannt.
class _NoPrices extends FakePriceRepository {
  _NoPrices(super.backend);

  @override
  Future<List<PricePoint>> loadWeeks() async =>
      throw Exception('ClientException: kein Netz');
}

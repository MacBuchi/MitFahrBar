/// prices_flow_test.dart – Preisarchiv: Bereich einrichten, Verlauf ansehen.
///
/// Der Screen ist Entwicklungsstand und rührt die Kostenrechnung nicht an.
/// Geprüft wird deshalb vor allem, was ihn ehrlich hält: dass ein Wert aus
/// den Parametern als solcher gekennzeichnet ist, und dass der
/// Abfrage-Knopf keinen Erfolg meldet, den er nicht geprüft hat.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/data/price_repository.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:mitfahrbar/models/price_area.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

({FakeBackend backend, String group}) _backend() {
  final backend = FakeBackend();
  final group = backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  return (backend: backend, group: group);
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'daciaracing');
  await tester.enterText(find.byType(TextField).last, 'geheim123');
  await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
  await tester.pumpAndSettle();
}

/// Über die Parameter, nicht über das Hauptmenü — dort sitzt der Weg.
Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.account_circle_outlined));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Parameter'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Spritpreise ansehen'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ohne Bereich führt der Screen durch die Ortssuche', (
    tester,
  ) async {
    final (:backend, group: _) = _backend();
    final prices = FakePriceRepository(backend)
      ..places = const [
        GeoPlace(
          label: 'Bad Rappenau, Landkreis Heilbronn',
          lat: 49.24,
          lng: 9.1,
        ),
      ];
    await pumpApp(
      tester,
      backend,
      overrides: [priceRepositoryProvider.overrideWithValue(prices)],
    );
    await _login(tester);
    await _open(tester);

    expect(find.text('Wo tankt ihr?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Bad Rappenau');
    await tester.tap(find.widgetWithText(FilledButton, 'Ort suchen'));
    await tester.pumpAndSettle();

    expect(find.text('Bad Rappenau, Landkreis Heilbronn'), findsOneWidget);

    await tester.tap(find.text('Bad Rappenau, Landkreis Heilbronn'));
    await tester.pumpAndSettle();

    // Gespeichert und umgeschaltet: Der Bereich steht jetzt in der „Tabelle",
    // und der Screen zeigt den Verlauf statt der Einrichtung.
    expect(prices.areas.values.single.label, contains('Bad Rappenau'));
    expect(find.text('Wo tankt ihr?'), findsNothing);
    expect(find.textContaining('Umkreis 20 km'), findsOneWidget);
  });

  testWidgets('ohne jede Messung ist die Linie als ungemessen gekennzeichnet', (
    tester,
  ) async {
    final (:backend, :group) = _backend();
    final prices = FakePriceRepository(backend);
    prices.areas[group] = const PriceArea(
      label: 'Bad Rappenau',
      lat: 49.24,
      lng: 9.1,
    );
    // Bewusst KEINE Wochenwerte: Dann besteht die ganze Reihe aus den
    // Konstanten — und genau das muss die Legende sagen, sonst liest sich
    // eine erfundene Linie wie eine gemessene.
    await pumpApp(
      tester,
      backend,
      overrides: [priceRepositoryProvider.overrideWithValue(prices)],
    );
    await _login(tester);
    await _open(tester);

    // „nicht gemessen" statt „aus den Parametern": Gestrichelt bedeutet
    // seit dem Nachfüll-Lauf überwiegend eine überbrückte Woche zwischen
    // zwei Messungen. Die Konstante steckt zwar hinter genau diesem Fall
    // hier, aber die Legende steht über allen — sie darf keine Herkunft
    // behaupten, die für den Großteil der Striche nicht stimmt.
    expect(find.text('nicht gemessen'), findsWidgets);
    expect(find.text('aus den Parametern'), findsNothing);
    expect(find.text('Kraftstoff'), findsOneWidget);
    // Zwei Diagramme, weil €/l und €/kWh nicht auf eine Achse gehören.
    expect(find.text('Strom'), findsOneWidget);
  });

  testWidgets('der Abfrage-Knopf meldet nur, was er geprüft hat', (
    tester,
  ) async {
    final (:backend, :group) = _backend();
    final prices = FakePriceRepository(backend)
      ..next = const SampleResult(stored: 0, failed: true);
    prices.areas[group] = const PriceArea(
      label: 'Bad Rappenau',
      lat: 49.24,
      lng: 9.1,
    );
    await pumpApp(
      tester,
      backend,
      overrides: [priceRepositoryProvider.overrideWithValue(prices)],
    );
    await _login(tester);
    await _open(tester);

    // Getippt, nicht nur gefunden: Ein Test, der die Sichtbarkeit prüft,
    // hätte den toten Update-Knopf aus 0.37.0 auch durchgelassen.
    await tester.tap(find.text('Jetzt abfragen'));
    await tester.pumpAndSettle();

    expect(prices.samples, 1);
    expect(
      find.text('Die Preise konnten gerade nicht abgefragt werden.'),
      findsOneWidget,
    );
  });

  testWidgets('ein geglückter Abruf nennt die Zahl der Tankstellen', (
    tester,
  ) async {
    final (:backend, :group) = _backend();
    final prices = FakePriceRepository(backend)
      ..next = const SampleResult(stored: 93, failed: false);
    prices.areas[group] = const PriceArea(
      label: 'Bad Rappenau',
      lat: 49.24,
      lng: 9.1,
    );
    await pumpApp(
      tester,
      backend,
      overrides: [priceRepositoryProvider.overrideWithValue(prices)],
    );
    await _login(tester);
    await _open(tester);

    await tester.tap(find.text('Jetzt abfragen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('93 Tankstellen'), findsOneWidget);
  });
}

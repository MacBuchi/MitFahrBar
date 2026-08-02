/// savings_chart_interaction_test.dart – Zoomen und Schieben im
/// Fahrten-und-Ersparnis-Diagramm.
///
/// Die Gesten werden **ausgeführt**, nicht nur verdrahtet gefunden — ein
/// Test, der nur prüft, dass ein GestureDetector existiert, hätte auch
/// einen toten Rückruf durchgelassen (dieselbe Klasse Fehler wie der tote
/// Update-Knopf in 0.37.0).
///
/// Beobachtet wird am Painter: Der sichtbare Ausschnitt (`visibleFrom`/
/// `visibleTo`) ist seine Eingabe, und die Zeitachse auf Canvas ist für
/// Widget-Finder unsichtbar. Die Klasse ist privat, ihre Felder sind es
/// nicht — `dynamic` kommt heran.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/widgets/savings_chart.dart';

SavingsChart _chart(int count) {
  final weeks = <IsoWeek>[const IsoWeek(2025, 1)];
  while (weeks.length < count) {
    weeks.add(weeks.last.next);
  }
  final line = [for (var i = 0; i < count; i++) (i + 1) * 5.0];
  return SavingsChart(
    weeks: weeks,
    group: line,
    perPerson: {'anna': line},
    carriedOver: 0,
    estimatedFrom: const {},
    tripCounts: List<int>.filled(count, 1),
  );
}

Future<void> _pump(WidgetTester tester, SavingsChart chart) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: SavingsTrendChart(
              chart: chart,
              names: const {'anna': 'Anna'},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _canvas => find
    .descendant(
      of: find.byType(SavingsTrendChart),
      matching: find.byType(CustomPaint),
    )
    .first;

/// Der sichtbare Ausschnitt, wie ihn der Painter bekommen hat.
(double, double) _window(WidgetTester tester) {
  // ignore: avoid_dynamic_calls
  final dynamic painter = tester.widget<CustomPaint>(_canvas).painter;
  // ignore: avoid_dynamic_calls
  return (painter.visibleFrom as double, painter.visibleTo as double);
}

/// Zwei Finger auseinanderziehen — der Pinch, mit dem gezoomt wird.
/// [shift] verschiebt die Geste aus der Mitte heraus.
Future<void> _pinchOut(WidgetTester tester, {double shift = 0}) async {
  final center = tester.getCenter(_canvas) + Offset(shift, 0);
  final first = await tester.startGesture(center - const Offset(20, 0));
  final second = await tester.startGesture(center + const Offset(20, 0));
  await tester.pump(const Duration(milliseconds: 20));
  await first.moveBy(const Offset(-80, 0));
  await second.moveBy(const Offset(80, 0));
  await tester.pump(const Duration(milliseconds: 20));
  await first.up();
  await second.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('zwei Finger zoomen die Zeitachse', (tester) async {
    await _pump(tester, _chart(60));
    final (fullFrom, fullTo) = _window(tester);
    expect(fullTo - fullFrom, 59, reason: 'anfangs ist alles sichtbar');

    await _pinchOut(tester);

    final (from, to) = _window(tester);
    expect(
      to - from,
      lessThan(59),
      reason: 'Auseinanderziehen muss den Ausschnitt verengen',
    );
    expect(
      to - from,
      greaterThanOrEqualTo(8),
      reason: 'enger als acht Wochen zeigt keine Kurve mehr',
    );
  });

  testWidgets('ein Finger schiebt den gezoomten Ausschnitt', (tester) async {
    await _pump(tester, _chart(60));
    await _pinchOut(tester);
    final (from, _) = _window(tester);

    // Nach links ziehen holt spätere Wochen herein.
    await tester.drag(_canvas, const Offset(-60, 0));
    await tester.pumpAndSettle();

    final (shifted, _) = _window(tester);
    expect(shifted, greaterThan(from));
  });

  testWidgets('ungezoomtes Ziehen lässt den Ausschnitt in Ruhe', (
    tester,
  ) async {
    await _pump(tester, _chart(60));

    await tester.drag(_canvas, const Offset(-60, 0));
    await tester.pumpAndSettle();

    final (from, to) = _window(tester);
    expect((from, to), (0.0, 59.0));
  });

  testWidgets('Doppeltipp setzt den Zoom zurück', (tester) async {
    await _pump(tester, _chart(60));
    await _pinchOut(tester);
    final (from, to) = _window(tester);
    expect(to - from, lessThan(59), reason: 'sonst prüft der Test nichts');

    await tester.tap(_canvas);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(_canvas);
    await tester.pumpAndSettle();

    expect(_window(tester), (0.0, 59.0));
  });

  testWidgets('die Woche unter den Fingern bleibt beim Zoomen stehen', (
    tester,
  ) async {
    await _pump(tester, _chart(60));

    // Bewusst weit RECHTS gekniffen: In der Mitte bewegte der Anker das
    // Fenster fast nicht, und der Test blieb auch ohne Anker grün — genau
    // so beim ersten Scharfstellen gemessen. Am Rand liegt der Unterschied
    // bei über 15 Wochen.
    await _pinchOut(tester, shift: 120);

    final (from, _) = _window(tester);
    expect(
      from,
      greaterThan(5),
      reason:
          'Der Zoom muss dort einengen, wo die Finger liegen. Ohne Anker '
          'klebt `from` bei 0, und jeder Zoom zöge nach links.',
    );
  });
}

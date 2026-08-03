/// weekly_bars_test.dart – Das Rekord-Label im Wochen-Balkendiagramm.
///
/// Gefunden beim ersten Web-Durchklick (nicht von einem Test): Der Rekord
/// in der zweitletzten Woche schrieb „KW 30 · 5" mitten in die
/// Randbeschriftung „diese Woche". Die Perlenschnur-Lektion in neu: Was
/// nur im Bild sichtbar ist, braucht nach dem Fund einen Test, der die
/// Grenze festhält.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/stats_data.dart';
import 'package:mitfahrbar/core/widgets/weekly_bars.dart';

WeeklyTripBars _bars({required int recordIndex}) {
  final weeks = <IsoWeek>[const IsoWeek(2026, 19)];
  while (weeks.length < 12) {
    weeks.add(weeks.last.next);
  }
  final counts = List<int>.filled(12, 1)..[recordIndex] = 5;
  return WeeklyTripBars(
    weeks: weeks,
    counts: counts,
    average: counts.fold(0, (sum, count) => sum + count) / counts.length,
    recordIndex: recordIndex,
    recordWeek: weeks[recordIndex],
    recordCount: 5,
  );
}

Future<void> _pump(WidgetTester tester, WeeklyTripBars bars) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 380, child: WeeklyBarsChart(bars: bars)),
        ),
      ),
    );

void main() {
  testWidgets('mittig trägt der Rekord-Balken sein Label', (tester) async {
    await _pump(tester, _bars(recordIndex: 5));

    expect(find.text('KW 24 · 5'), findsOneWidget);
  });

  testWidgets('am Rand weicht das Label dem Randdatum', (tester) async {
    // Index n−3: genau der Fall aus dem Web-Durchklick — dort stand
    // „KW 30 · 5" in „diese Woche" hinein, und die alte Grenze (≤ n−3)
    // ließ ihn durch. Der Untertitel der Karte nennt den Rekord.
    await _pump(tester, _bars(recordIndex: 9));

    expect(find.text('KW 28 · 5'), findsNothing);
    expect(
      find.text('diese Woche'),
      findsWidgets,
      reason: 'das Randdatum bleibt — nur das Rekord-Label weicht',
    );
  });
}

/// chart_year_boundary_test.dart – Die Jahresgrenze im Wochen-Diagramm (#129).
///
/// Gemeldet aus der Gruppe am 27.07.2026: „Im Fahrtendiagramm fehlt eine
/// Abgrenzung zu den Jahreszahlen." Die Regel entstand am Monats-Diagramm
/// und ist am 02.08.2026 mit den Säulen in das Ersparnis-Diagramm
/// umgezogen — über Jahre hinweg sieht sonst jede Woche aus wie die vorige.
///
/// Geprüft wird am **gerenderten Bild**, nicht an der Malreihenfolge: Der
/// Test sucht senkrechte Linien und verlangt genau eine, an der richtigen
/// Stelle. Dasselbe Vorgehen wie in `mark_test.dart` — ein Test, der nur
/// `paint` mitzählt, ginge auch dann durch, wenn die Linie hinter einer
/// Säule oder außerhalb der Fläche landet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/price_series.dart';
import 'package:mitfahrbar/core/widgets/savings_chart.dart';

/// Anteil der Bildhöhe, ab dem eine x-Spalte als senkrechte Linie gilt.
/// Die Ersparnis-Kurven treffen jede Spalte nur an wenigen Punkten, die
/// Fahrten-Säulen enden bei 30 % der Zeichenfläche — nur die Jahresgrenze
/// läuft durch.
const _lineShare = 0.5;

/// Ein Diagramm über [count] Wochen ab [start], mit stetig wachsender
/// Ersparnis und bewusst OHNE Säulen (`tripCounts` = 0): Ohne Datenflächen
/// ist jede volle Spalte eine gezeichnete Linie.
SavingsChart _chart(IsoWeek start, int count) {
  final weeks = <IsoWeek>[start];
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
    tripCounts: List<int>.filled(count, 0),
  );
}

/// Die x-Positionen aller senkrechten Linien im gerenderten Diagramm,
/// gemessen als Anteil der Bildbreite (0 = links, 1 = rechts).
Future<List<double>> _verticalLines(
  WidgetTester tester,
  SavingsChart data,
) async {
  const probe = Key('chart-probe');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: probe,
            child: SizedBox(
              width: 360,
              child: SavingsTrendChart(
                chart: data,
                names: const {'anna': 'Anna'},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      tester.renderObject(find.byKey(probe)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(() => image!.toByteData());
  final data8 = bytes!.buffer.asUint8List();
  final width = image!.width;
  final height = image.height;

  // Verglichen wird gegen den Untergrund, NICHT gegen Alpha: Im Scaffold ist
  // jeder Pixel deckend, eine Alpha-Prüfung hielte also die ganze Fläche für
  // bemalt (beim Schreiben des Vorgänger-Tests genau so passiert).
  //
  // Abgetastet wird OBEN RECHTS: Oben links sitzt das oberste Achsenlabel,
  // und Testfonts rendern jedes Zeichen als gefüllten Kasten — Pixel (0,0)
  // läge mitten im Schwarz, und der ganze weiße Rest zählte als „bemalt"
  // (beim Umzug dieses Tests genau so passiert).
  int at(int x, int y, int channel) => data8[(y * width + x) * 4 + channel];
  final bgR = at(width - 1, 0, 0),
      bgG = at(width - 1, 0, 1),
      bgB = at(width - 1, 0, 2);

  bool painted(int x, int y) =>
      (at(x, y, 0) - bgR).abs() +
          (at(x, y, 1) - bgG).abs() +
          (at(x, y, 2) - bgB).abs() >
      24;

  final columns = <int>[];
  for (var x = 0; x < width; x++) {
    var hits = 0;
    for (var y = 0; y < height; y++) {
      if (painted(x, y)) hits++;
    }
    if (hits > height * _lineShare) columns.add(x);
  }

  // Eine haarfeine Linie liegt selten genau auf einem Gerätepixel — die
  // Kantenglättung färbt zwei Nachbarspalten. Benachbarte Treffer sind
  // deshalb EINE Linie, sonst zählte der Test Kanten statt Grenzen.
  final lines = <double>[];
  for (final x in columns) {
    if (lines.isNotEmpty && x - (lines.last * width) <= 1.5) continue;
    lines.add(x / width);
  }
  return lines;
}

void main() {
  testWidgets('ein Jahreswechsel bekommt genau eine Trennlinie', (
    tester,
  ) async {
    // 2025-W49 bis 2026-W04 — die Grenze liegt in der Mitte des Fensters.
    final lines = await _verticalLines(
      tester,
      _chart(const IsoWeek(2025, 49), 8),
    );

    expect(
      lines,
      hasLength(1),
      reason:
          'Genau eine Grenze bei einem Jahreswechsel — mehr hieße, die Linie '
          'steht auch zwischen gewöhnlichen Wochen.',
    );
    // Die Fläche beginnt rechts der Wertachse, die Grenze liegt daher etwas
    // rechts der Bildmitte. Grob geprüft: Sie darf weder am Rand kleben noch
    // in der falschen Hälfte stehen.
    expect(lines.single, greaterThan(0.35));
    expect(lines.single, lessThan(0.75));
  });

  testWidgets('innerhalb eines Jahres bleibt das Diagramm ohne Trennlinie', (
    tester,
  ) async {
    final lines = await _verticalLines(
      tester,
      _chart(const IsoWeek(2026, 10), 8),
    );

    expect(
      lines,
      isEmpty,
      reason:
          'Ohne Jahreswechsel gibt es nichts abzugrenzen. Stünde hier eine '
          'Linie, wäre sie an jeder Wochenkante — und damit wertlos.',
    );
  });

  testWidgets('zwei Jahreswechsel ergeben zwei Trennlinien', (tester) async {
    // 2024-W50 bis 2026-W05 — über zwei Silvester hinweg. Nicht länger:
    // 2026 hat 53 Wochen, ein zu großzügiges Fenster erwischte still den
    // dritten Wechsel (beim Schreiben dieses Tests genau so passiert —
    // die dritte Linie im Bild war korrekt, die Erwartung war es nicht).
    final lines = await _verticalLines(
      tester,
      _chart(const IsoWeek(2024, 50), 60),
    );

    expect(lines, hasLength(2));
  });

  testWidgets('die erste Woche bekommt nie eine Linie', (tester) async {
    // Beginnt die Reihe in Woche 1, wäre eine Linie ganz links eine Kante
    // ohne Gegenüber — sie trennte nichts.
    final lines = await _verticalLines(
      tester,
      _chart(const IsoWeek(2026, 1), 8),
    );

    expect(lines, isEmpty);
  });
}

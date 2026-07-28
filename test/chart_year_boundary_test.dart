/// chart_year_boundary_test.dart – Die Jahresgrenze im Monats-Diagramm (#129).
///
/// Gemeldet aus der Gruppe am 27.07.2026: „Im Fahrtendiagramm fehlt eine
/// Abgrenzung zu den Jahreszahlen." Seit das Diagramm die ganze Historie
/// zeigt (#124), folgt auf „Dez" ein „Jan", das genauso aussieht wie das
/// vorige — ohne Marke ist nicht zu sehen, wo ein Jahr endet.
///
/// Geprüft wird am **gerenderten Bild**, nicht an der Malreihenfolge: Der
/// Test sucht senkrechte Linien und verlangt genau eine, an der richtigen
/// Stelle. Dasselbe Vorgehen wie in `mark_test.dart` — ein Test, der nur
/// `paint` mitzählt, ginge auch dann durch, wenn die Linie hinter einem
/// Balken oder außerhalb der Fläche landet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mitfahrbar/core/chart_data.dart';
import 'package:mitfahrbar/core/widgets/charts.dart';

/// Anteil der Bildhöhe, ab dem eine x-Spalte als senkrechte Linie gilt.
/// Waagerechte Hilfslinien treffen jede Spalte nur an wenigen Punkten.
const _lineShare = 0.5;

/// Die x-Positionen aller senkrechten Linien im gerenderten Diagramm,
/// gemessen als Anteil der Bildbreite (0 = links, 1 = rechts).
///
/// Alle Monate tragen bewusst **null** Fahrten: Ohne Säulen ist jede volle
/// Spalte eine gezeichnete Linie und keine Datenfläche.
Future<List<double>> _verticalLines(
  WidgetTester tester,
  List<MonthBucket> data,
) async {
  const probe = Key('chart-probe');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: probe,
            child: SizedBox(width: 360, child: MonthlyTripsChart(data: data)),
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
  // bemalt (beim Schreiben dieses Tests genau so passiert).
  int at(int x, int y, int channel) => data8[(y * width + x) * 4 + channel];
  final bgR = at(0, 0, 0), bgG = at(0, 0, 1), bgB = at(0, 0, 2);

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

List<MonthBucket> _months(List<(int, int)> yearMonth) => [
  for (final (y, m) in yearMonth) MonthBucket(year: y, month: m, trips: 0),
];

void main() {
  setUpAll(() => initializeDateFormatting('de'));

  testWidgets('ein Jahreswechsel bekommt genau eine Trennlinie', (
    tester,
  ) async {
    // Nov, Dez | Jan, Feb — die Grenze liegt zwischen dem zweiten und dem
    // dritten Monat, also auf der linken Kante des Januar-Slots.
    final lines = await _verticalLines(
      tester,
      _months([(2025, 11), (2025, 12), (2026, 1), (2026, 2)]),
    );

    expect(
      lines,
      hasLength(1),
      reason:
          'Genau eine Grenze bei einem Jahreswechsel — mehr hieße, die Linie '
          'steht auch zwischen gewöhnlichen Monaten.',
    );
    // Die Fläche beginnt rechts der Wertachse, die Grenze liegt daher etwas
    // rechts der Bildmitte. Grob geprüft: Sie darf weder am Rand kleben noch
    // in der falschen Hälfte stehen.
    expect(lines.single, greaterThan(0.45));
    expect(lines.single, lessThan(0.75));
  });

  testWidgets('innerhalb eines Jahres bleibt das Diagramm ohne Trennlinie', (
    tester,
  ) async {
    final lines = await _verticalLines(
      tester,
      _months([(2026, 3), (2026, 4), (2026, 5), (2026, 6)]),
    );

    expect(
      lines,
      isEmpty,
      reason:
          'Ohne Jahreswechsel gibt es nichts abzugrenzen. Stünde hier eine '
          'Linie, wäre sie an jeder Monatskante — und damit wertlos.',
    );
  });

  testWidgets('zwei Jahreswechsel ergeben zwei Trennlinien', (tester) async {
    final lines = await _verticalLines(tester, [
      ..._months([(2024, 12), (2025, 1), (2025, 12), (2026, 1)]),
    ]);

    expect(lines, hasLength(2));
  });

  testWidgets('der erste Monat bekommt nie eine Linie', (tester) async {
    // Beginnt die Reihe im Januar, wäre eine Linie ganz links eine Kante
    // ohne Gegenüber — sie trennte nichts.
    final lines = await _verticalLines(
      tester,
      _months([(2026, 1), (2026, 2), (2026, 3)]),
    );

    expect(lines, isEmpty);
  });
}

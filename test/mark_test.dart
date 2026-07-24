/// mark_test.dart – Die Bildmarke muss auf beiden Themes lesbar sein.
///
/// Gemeldet 25.07.2026: Im dunklen Theme versank der Reifen (#1A1030 aus
/// der Vorlage) im Hintergrund (#06171C) — sichtbar blieb nur die helle
/// Nabe. Der Test prüft das gerenderte Bild, nicht die Palette: Er tastet
/// den Reifen-Pixel ab und verlangt Abstand zum dunklen Grund. Im hellen
/// Theme muss der Reifen exakt der Vorlagenton bleiben — `mark.svg` ist
/// die einzige Quelle der Bildmarke, die App weicht NUR im Dunkeln ab.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/theme.dart';
import 'package:mitfahrbar/core/tokens.dart';
import 'package:mitfahrbar/core/widgets/mitfahrbar_mark.dart';

/// Rendert die Marke (120 × 100) im gegebenen Theme und liest den Pixel
/// auf dem Reifen des vorderen Rads: Radmitte liegt im Entwurfsraster bei
/// (26, 80), der Ring zwischen Nabe (r = 5) und Radrand (r = 12) — (26, 88)
/// trifft ihn mittig, weit weg von jeder Kantenglättung.
Future<Color> _tirePixel(WidgetTester tester, ThemeData theme) async {
  const probe = Key('mark-probe');
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: const Center(
        child: RepaintBoundary(key: probe, child: MitFahrBarMark(size: 120)),
      ),
    ),
  );
  final boundary =
      tester.renderObject(find.byKey(probe)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(() => image!.toByteData());
  const x = 26, y = 88;
  final offset = (y * image!.width + x) * 4;
  return Color.fromARGB(
    bytes!.getUint8(offset + 3),
    bytes.getUint8(offset),
    bytes.getUint8(offset + 1),
    bytes.getUint8(offset + 2),
  );
}

/// Summe der Kanalabstände — grob, aber ehrlich: Unter ~30 verschwimmen
/// zwei dunkle Töne auf einem Bildschirm ineinander.
int _distance(Color a, Color b) {
  final x = a.toARGB32(), y = b.toARGB32();
  var sum = 0;
  for (final shift in [0, 8, 16]) {
    sum += (((x >> shift) & 0xFF) - ((y >> shift) & 0xFF)).abs();
  }
  return sum;
}

void main() {
  testWidgets('Reifen hebt sich im dunklen Theme vom Grund ab', (tester) async {
    final tire = await _tirePixel(tester, darkTheme());
    expect(
      _distance(tire, AppColors.darkBackground),
      greaterThan(60),
      reason:
          'Der Reifen muss sich vom dunklen Hintergrund abheben — '
          'sonst „schwebt" die Nabe wieder frei (25.07.2026).',
    );
    expect(
      _distance(tire, AppColors.darkSurface),
      greaterThan(60),
      reason: 'Auch auf dunklen Flächen (Karten) muss der Reifen lesbar sein.',
    );
  });

  testWidgets('Im hellen Theme bleibt der Reifen der Vorlagenton', (
    tester,
  ) async {
    final tire = await _tirePixel(tester, lightTheme());
    expect(
      tire.toARGB32(),
      const Color(0xFF1A1030).toARGB32(),
      reason:
          'Hell ist die Referenz: exakt der Reifenton aus mark.svg. '
          'Wer hier abweicht, trennt App und Icons in zwei Wahrheiten.',
    );
  });
}

/// ring_chart_test.dart – Die Ringe der Statistik-Seite, am gerenderten Bild.
///
/// Dasselbe Vorgehen wie `chart_year_boundary_test.dart`: geprüft wird, was
/// wirklich auf dem Bildschirm steht, nicht die Malreihenfolge. Ein Test,
/// der nur `paint` mitzählt, ginge auch durch, wenn der Ring gefüllt statt
/// hohl wäre oder beide Segmente dieselbe Farbe trügen.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/widgets/ring_chart.dart';

const _size = 120.0;
const _thickness = 26.0;

/// Radius der Bogen-Mittellinie: dort ist der Strich voll deckend.
const _radius = (_size - _thickness) / 2;

Future<({Uint8List pixels, int width, double scale})> _render(
  WidgetTester tester,
  Widget ring,
) async {
  const probe = Key('ring-probe');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(key: probe, child: ring),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary =
      tester.renderObject(find.byKey(probe)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage());
  final bytes = await tester.runAsync(() => image!.toByteData());
  return (
    pixels: bytes!.buffer.asUint8List(),
    width: image!.width,
    scale: image.width / _size,
  );
}

Color _colorAt(
  ({Uint8List pixels, int width, double scale}) shot,
  double x,
  double y,
) {
  final px = (x * shot.scale).round();
  final py = (y * shot.scale).round();
  final offset = (py * shot.width + px) * 4;
  return Color.fromARGB(
    255,
    shot.pixels[offset],
    shot.pixels[offset + 1],
    shot.pixels[offset + 2],
  );
}

bool _near(Color a, Color b) =>
    ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255 < 40;

const _red = Color(0xFFFF0000);
const _blue = Color(0xFF0000FF);
const _track = Color(0xFFDDDDDD);

void main() {
  testWidgets('der Segment-Ring ist hohl und trennt seine Segmente', (
    tester,
  ) async {
    final shot = await _render(
      tester,
      const SegmentRing(
        segments: [(value: 1.0, color: _red), (value: 1.0, color: _blue)],
        size: _size,
        thickness: _thickness,
      ),
    );

    final background = _colorAt(shot, 2, 2);
    expect(
      _near(_colorAt(shot, _size / 2, _size / 2), background),
      isTrue,
      reason:
          'die Mitte muss frei bleiben — dort sitzt die Summe als Widget, '
          'ein gefüllter Kreis übermalte sie',
    );
    // Zwei gleiche Segmente ab zwölf Uhr: rechts das erste, links das zweite.
    expect(
      _near(_colorAt(shot, _size / 2 + _radius, _size / 2), _red),
      isTrue,
      reason: 'rechts der Mitte muss das erste Segment liegen',
    );
    expect(
      _near(_colorAt(shot, _size / 2 - _radius, _size / 2), _blue),
      isTrue,
      reason: 'links der Mitte muss das zweite Segment liegen',
    );
  });

  testWidgets('der Fortschritts-Ring füllt genau seinen Anteil', (
    tester,
  ) async {
    final shot = await _render(
      tester,
      const ProgressRing(
        progress: 0.5,
        color: _red,
        trackColor: _track,
        size: _size,
        thickness: _thickness,
      ),
    );

    // Halber Fortschritt läuft von zwölf nach sechs Uhr über rechts: Der
    // Punkt auf der 45°-Diagonale unten rechts ist gefüllt …
    final diagonal = _radius * 0.7071;
    expect(
      _near(_colorAt(shot, _size / 2 + diagonal, _size / 2 + diagonal), _red),
      isTrue,
      reason: 'unten rechts liegt der gefüllte Teil des Halbrings',
    );
    // … der oben links zeigt nur die Spur.
    expect(
      _near(_colorAt(shot, _size / 2 - diagonal, _size / 2 - diagonal), _track),
      isTrue,
      reason:
          'oben links darf bei 50 % nichts gefüllt sein — sonst zeigt der '
          'Ring mehr Fortschritt, als es gibt',
    );
  });
}

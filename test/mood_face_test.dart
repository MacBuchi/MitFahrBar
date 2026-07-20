/// mood_face_test.dart – Die gezeichneten Gesichter.
///
/// Gemalte Grafik lässt sich nicht sinnvoll auf Pixel prüfen, ohne Goldens
/// zu pflegen. Geprüft wird deshalb das, was schiefgehen kann, ohne dass es
/// jemand merkt: dass jede Stufe überhaupt zeichnet (ein fehlender
/// switch-Zweig fiele sonst erst im Betrieb auf), dass der Vorlesetext
/// ankommt und dass ein Wechsel der Stimmung neu gezeichnet wird.
library;

import 'package:fahrgemeinschaft/core/mood.dart';
import 'package:fahrgemeinschaft/core/widgets/mood_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('jede Stimmung zeichnet ohne Ausnahme', (tester) async {
    for (final mood in Mood.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: MoodFace(mood: mood, size: 48)),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'Stimmung: $mood');
      expect(find.byType(MoodFace), findsOneWidget);
    }
  });

  testWidgets('die Größe bestimmt die Kantenlänge', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: MoodFace(mood: Mood.happy, size: 32)),
      ),
    );
    expect(tester.getSize(find.byType(MoodFace)), const Size(32, 32));
  });

  testWidgets('ohne Beschriftung entsteht kein leerer Semantics-Knoten', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: MoodFace(mood: Mood.good)),
      ),
    );
    expect(find.byType(Semantics), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('die Beschriftung erreicht den Screenreader', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: MoodFace(mood: Mood.angry, semanticLabel: 'fährt viel'),
        ),
      ),
    );
    expect(find.bySemanticsLabel('fährt viel'), findsOneWidget);
  });
}

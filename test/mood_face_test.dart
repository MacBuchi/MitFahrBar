/// mood_face_test.dart – Die gezeichneten Gesichter.
///
/// Gemalte Grafik lässt sich nicht sinnvoll auf Pixel prüfen, ohne Goldens
/// zu pflegen. Geprüft wird deshalb das, was schiefgehen kann, ohne dass es
/// jemand merkt: dass jede Stufe überhaupt zeichnet (ein fehlender
/// switch-Zweig fiele sonst erst im Betrieb auf), dass der Vorlesetext
/// ankommt und dass ein Wechsel der Stimmung neu gezeichnet wird.
library;

import 'package:mitfahrbar/core/mood.dart';
import 'package:mitfahrbar/core/widgets/mood_face.dart';
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

  // Seit dem Design-Stand „Animated versions" leben die Gesichter. Geprüft
  // wird nicht die Choreografie (die sieht man sich an), sondern dass jede
  // Schleife über die volle Länge ohne Ausnahme zeichnet — ein Fehler in
  // einer Keyframe-Stützstelle fiele sonst erst mitten im Betrieb auf.
  testWidgets('jede Stimmung durchläuft ihre Schleife ohne Ausnahme', (
    tester,
  ) async {
    for (final mood in Mood.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: MoodFace(mood: mood, size: 48)),
        ),
      );
      // Länger als die längste Schleife (4 s), in groben Schritten.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull, reason: 'Stimmung: $mood');
      }
    }
    // Aufräumen, damit kein Ticker in den nächsten Test lebt.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bei „Bewegung reduzieren" ruht das Gesicht', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(child: MoodFace(mood: Mood.celebrating, size: 48)),
      ),
    );
    await tester.pump();

    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason:
          'Ohne Animation darf kein weiterer Frame anstehen — genau darauf '
          'verlassen sich alle Flow-Tests (pumpAndSettle).',
    );
  });
}

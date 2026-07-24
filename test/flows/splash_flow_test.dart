/// splash_flow_test.dart – Der Startbildschirm mit der Anfahrt.
///
/// Nicht die Choreografie wird geprüft (die sieht man sich an), sondern die
/// Zusagen drumherum: Der Splash kommt nur, wenn er soll, er geht von
/// allein wieder, und ein Tipp beendet ihn sofort — niemand soll auf die
/// App warten müssen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/widgets/mitfahrbar_mark.dart';
import 'package:mitfahrbar/features/splash/splash_overlay.dart';

import '../fakes/fake_backend.dart';
import '../fakes/test_app.dart';

FakeBackend _backend() {
  final backend = FakeBackend();
  backend.addGroup(
    handle: 'daciaracing',
    password: 'geheim123',
    name: 'Dacia Racing',
  );
  return backend;
}

void main() {
  testWidgets('der Splash liegt beim Start über allem und endet von allein', (
    tester,
  ) async {
    await pumpApp(tester, _backend(), splash: true);

    expect(find.byType(SplashOverlay), findsOneWidget);
    // Denselben Claim trägt auch der Login darunter — deshalb gezielt im
    // Overlay suchen.
    expect(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.text('Die faire App für eure Fahrgemeinschaft'),
      ),
      findsOneWidget,
      reason: 'Der Schriftzug gehört zum Auftritt.',
    );

    // Der Splash liegt im MaterialApp-builder ÜBER dem Navigator — ohne
    // eigenen Material-Wrapper zeichnete Flutter den Schriftzug mit dem
    // Notfall-Stil: der gelben Doppellinie, die bis v0.34.0 wie ein
    // Design-Element aussah. Wer den Wrapper „aufräumt", holt sie zurück.
    expect(
      find.ancestor(
        of: find.byType(MitFahrBarWordmark),
        matching: find.byType(Material),
      ),
      findsWidgets,
      reason: 'Ohne Material-Vorfahr malt Flutter die gelbe Doppellinie.',
    );

    // Die Straße unter den Rädern (Entwurf 25.07.2026) gehört zum Auftritt.
    expect(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.byType(RoadLine),
      ),
      findsOneWidget,
      reason: 'Das Auto steht auf der Straße, nicht in der Luft.',
    );

    // Animation (2,6 s) plus Ausblenden abwarten.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(
      find.byType(SplashOverlay),
      findsNothing,
      reason: 'Nach dem Auftritt gehört der Bildschirm der App.',
    );
  });

  testWidgets('ein Tipp überspringt die Anfahrt sofort', (tester) async {
    await pumpApp(tester, _backend(), splash: true);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(SplashOverlay));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(SplashOverlay), findsNothing);
  });

  testWidgets('ohne Einladung erscheint kein Splash', (tester) async {
    await pumpApp(tester, _backend());

    expect(
      find.byType(SplashOverlay),
      findsNothing,
      reason: 'Flow-Tests und reduzierte Bewegung starten direkt in der App.',
    );
  });
}

/// drive_mood_test.dart – Schwellen der Fahranteil-Gesichter.
///
/// Der Kern ist, dass die Bewertung *relativ* ist: Dieselben 20 % sind in
/// einer Fünfergruppe genau der eigene Teil und in einer Zweiergruppe
/// auffällig wenig. Feste Prozentgrenzen würden die Gruppengröße messen.
library;

import 'package:fahrgemeinschaft/core/drive_mood.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driveMoodOf', () {
    test('wer seinen Teil fährt, bekommt ein neutrales Gesicht', () {
      expect(driveMoodOf(0.25, 0.25), DriveMood.neutral);
      expect(driveMoodOf(0.20, 0.20), DriveMood.neutral);
    });

    test('dieselben 20 % je nach Gruppe zufrieden oder nicht', () {
      // Fünfergruppe: 20 % ist der eigene Teil.
      expect(driveMoodOf(0.20, 0.20), DriveMood.neutral);
      // Zweiergruppe: bei 50 % Schnitt sind 20 % auffällig wenig.
      expect(driveMoodOf(0.20, 0.50), DriveMood.veryHappy);
    });

    test('deutlich seltener als der Schnitt = strahlend', () {
      expect(driveMoodOf(0.10, 0.25), DriveMood.veryHappy);
    });

    test('etwas seltener = zufrieden', () {
      expect(driveMoodOf(0.20, 0.25), DriveMood.happy);
    });

    test('etwas öfter = unzufrieden', () {
      expect(driveMoodOf(0.32, 0.25), DriveMood.unhappy);
    });

    test('deutlich öfter als der Schnitt = sehr unzufrieden', () {
      expect(driveMoodOf(0.50, 0.25), DriveMood.veryUnhappy);
    });

    test('ohne gefahrene Tage urteilt niemand', () {
      // 0 ÷ 0 darf kein Gesicht erzeugen — am Anfang hat noch keiner
      // etwas verdient oder verbockt.
      expect(driveMoodOf(0, 0), DriveMood.neutral);
    });
  });

  group('averageDriveShare', () {
    test('Schnitt über die übergebenen Anteile', () {
      expect(averageDriveShare([0.1, 0.2, 0.3]), closeTo(0.2, 1e-9));
    });

    test('leere Liste ergibt 0 und damit lauter neutrale Gesichter', () {
      expect(averageDriveShare(const []), 0);
      expect(driveMoodOf(0.5, averageDriveShare(const [])), DriveMood.neutral);
    });
  });

  group('driveMoodLabel', () {
    test('nennt den Prozentwert, der aus der Ansicht verschwunden ist', () {
      expect(driveMoodLabel(DriveMood.veryHappy, 0.12), contains('12 %'));
      expect(
        driveMoodLabel(DriveMood.veryUnhappy, 0.5),
        contains('viel öfter'),
      );
    });
  });
}

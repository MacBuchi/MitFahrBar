/// drive_mood_test.dart – Schwellen der Fahranteil-Gesichter.
///
/// Der Kern ist, dass die Bewertung *relativ* ist: Dieselben 20 % sind in
/// einer Fünfergruppe genau der eigene Teil und in einer Zweiergruppe
/// auffällig wenig. Feste Prozentgrenzen würden die Gruppengröße messen.
library;

import 'package:fahrgemeinschaft/core/drive_mood.dart';
import 'package:fahrgemeinschaft/core/mood.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driveMoodOf', () {
    test('wer seinen Teil fährt, bekommt ein neutrales Gesicht', () {
      expect(driveMoodOf(0.25, 0.25), Mood.neutral);
      expect(driveMoodOf(0.20, 0.20), Mood.neutral);
    });

    test('dieselben 20 % je nach Gruppe zufrieden oder nicht', () {
      // Fünfergruppe: 20 % ist der eigene Teil.
      expect(driveMoodOf(0.20, 0.20), Mood.neutral);
      // Zweiergruppe: bei 50 % Schnitt sind 20 % auffällig wenig.
      expect(driveMoodOf(0.20, 0.50), Mood.ecstatic);
    });

    test('die Skala läuft über alle sieben Stufen', () {
      // Von „fährt fast nie" bis „fährt fast alles" — ein Durchlauf, damit
      // keine Stufe unerreichbar wird, wenn jemand an den Schwellen dreht.
      const avg = 0.25;
      expect(driveMoodOf(0.05, avg), Mood.ecstatic);
      expect(driveMoodOf(0.15, avg), Mood.happy);
      expect(driveMoodOf(0.21, avg), Mood.good);
      expect(driveMoodOf(0.25, avg), Mood.neutral);
      expect(driveMoodOf(0.30, avg), Mood.meh);
      expect(driveMoodOf(0.36, avg), Mood.sad);
      expect(driveMoodOf(0.50, avg), Mood.angry);
    });

    test('ohne gefahrene Tage urteilt niemand', () {
      // 0 ÷ 0 darf kein Gesicht erzeugen — am Anfang hat noch keiner
      // etwas verdient oder verbockt.
      expect(driveMoodOf(0, 0), Mood.neutral);
    });

    test('das Konfetti-Gesicht ist keine Bewertungsstufe', () {
      // Es steht für einen Erfolg und wird gezielt gesetzt; käme es aus
      // der Skala, bekäme es irgendwann jemand für einen Fahranteil.
      for (final share in [0.0, 0.1, 0.25, 0.5, 1.0, 5.0]) {
        expect(driveMoodOf(share, 0.25), isNot(Mood.celebrating));
      }
    });
  });

  group('averageDriveShare', () {
    test('Schnitt über die übergebenen Anteile', () {
      expect(averageDriveShare([0.1, 0.2, 0.3]), closeTo(0.2, 1e-9));
    });

    test('leere Liste ergibt 0 und damit lauter neutrale Gesichter', () {
      expect(averageDriveShare(const []), 0);
      expect(driveMoodOf(0.5, averageDriveShare(const [])), Mood.neutral);
    });
  });

  group('driveMoodLabel', () {
    test('nennt den Prozentwert, der aus der Ansicht verschwunden ist', () {
      expect(driveMoodLabel(Mood.ecstatic, 0.12), contains('12 %'));
      expect(driveMoodLabel(Mood.angry, 0.5), contains('viel öfter'));
    });

    test('jede Stufe hat einen eigenen Text', () {
      final labels = {
        for (final mood in Mood.values) driveMoodLabel(mood, 0.2),
      };
      // celebrating teilt sich den Text mit neutral (es wird hier nie
      // vergeben), deshalb sieben statt acht.
      expect(labels, hasLength(7));
    });
  });
}

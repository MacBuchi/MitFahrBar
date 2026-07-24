/// drive_mood_test.dart – Die Gesichter zum Fahranteil.
///
/// Der Kern ist, dass die Skala über die **Spannweite der Gruppe** läuft:
/// Dieselben 20 % sind einmal der niedrigste Wert der Runde und einmal der
/// höchste. Feste Prozentgrenzen würden die Gruppengröße messen.
library;

import 'package:mitfahrbar/core/drive_mood.dart';
import 'package:mitfahrbar/core/mood.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('driveMoodOf', () {
    test('der niedrigste Fahranteil bekommt das glücklichste Gesicht', () {
      final range = DriveShareRange.of([0.1, 0.25, 0.5]);
      expect(driveMoodOf(0.1, range), Mood.ecstatic);
    });

    test('der höchste Fahranteil bekommt das traurigste', () {
      final range = DriveShareRange.of([0.1, 0.25, 0.5]);
      expect(driveMoodOf(0.5, range), Mood.angry);
    });

    test('die Mitte landet in der Mitte', () {
      final range = DriveShareRange.of([0.0, 1.0]);
      expect(driveMoodOf(0.5, range), Mood.neutral);
    });

    test('dieselben 20 % je nach Runde oben oder unten', () {
      expect(
        driveMoodOf(0.2, DriveShareRange.of([0.2, 0.4, 0.6])),
        Mood.ecstatic,
        reason: 'hier ist 20 % der niedrigste Wert',
      );
      expect(
        driveMoodOf(0.2, DriveShareRange.of([0.05, 0.1, 0.2])),
        Mood.angry,
        reason: 'hier ist derselbe Wert der höchste',
      );
    });

    test('die Skala läuft über alle sieben Stufen', () {
      // Ein Durchlauf über die volle Spannweite, damit keine Stufe
      // unerreichbar wird, wenn jemand an der Interpolation dreht.
      final range = DriveShareRange.of([0.0, 1.0]);
      expect(
        [for (var i = 0; i <= 6; i++) driveMoodOf(i / 6, range)],
        [
          Mood.ecstatic,
          Mood.happy,
          Mood.good,
          Mood.neutral,
          Mood.meh,
          Mood.sad,
          Mood.angry,
        ],
      );
    });

    test('fahren alle gleich viel, urteilt niemand', () {
      // Ohne Abstand gibt es nichts zu interpolieren. Jemanden zum
      // Traurigsten zu erklären, weil er einen Hauch über den anderen liegt,
      // wäre eine erfundene Aussage.
      final range = DriveShareRange.of([0.3, 0.3, 0.3]);
      expect(range.isFlat, isTrue);
      expect(driveMoodOf(0.3, range), Mood.neutral);
    });

    test('eine einzelne Person ist weder oben noch unten', () {
      expect(driveMoodOf(0.8, DriveShareRange.of([0.8])), Mood.neutral);
    });

    test('ohne Werte bleibt alles neutral', () {
      expect(driveMoodOf(0.5, DriveShareRange.of(const [])), Mood.neutral);
    });

    test('zwei Personen besetzen nur die Enden', () {
      final range = DriveShareRange.of([0.2, 0.8]);
      expect(driveMoodOf(0.2, range), Mood.ecstatic);
      expect(driveMoodOf(0.8, range), Mood.angry);
    });

    test('das Konfetti-Gesicht ist keine Bewertungsstufe', () {
      // Es steht für einen Erfolg und wird gezielt gesetzt; käme es aus
      // der Skala, bekäme es irgendwann jemand für einen Fahranteil.
      final range = DriveShareRange.of([0.0, 1.0]);
      for (var i = 0; i <= 20; i++) {
        expect(driveMoodOf(i / 20, range), isNot(Mood.celebrating));
      }
    });
  });

  group('DriveShareRange', () {
    test('nimmt den kleinsten und größten Wert', () {
      final range = DriveShareRange.of([0.4, 0.1, 0.9, 0.3]);
      expect(range.lowest, 0.1);
      expect(range.highest, 0.9);
      expect(range.isFlat, isFalse);
    });
  });

  group('driveMoodLabel', () {
    test('nennt den Prozentwert, der auch in der Zeile steht', () {
      expect(driveMoodLabel(Mood.ecstatic, 0.12), contains('12 %'));
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

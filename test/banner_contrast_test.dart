/// banner_contrast_test.dart – Rechnet jedes Farbpaar der Banner-, Anmerkungs-
/// und Push-Palette nach.
///
/// Der Anlass: Bis v0.47.0 wurden Bannerfarben nach Augenmaß gewählt und nie
/// gemessen. Zwei Vorschläge, die gut aussahen, fielen bei der ersten Rechnung
/// durch — Weiß auf `#418FAF` trägt 3,64:1 (die Zeile mit den Namen braucht
/// 4,5:1), und eine Fläche stand mit 1,08:1 auf dem Untergrund und wäre
/// unsichtbar gewesen. Beides kompiliert sauber und fällt sonst erst dem
/// auf, der die App benutzt.
///
/// Die Schwellen sind die von WCAG 2.1: 4,5:1 für Text, 3,0:1 für Grafik
/// (Icons und die Kante eines Chips gegen seinen Untergrund).
///
/// **Bei einem Verlauf wird jeder Stopp geprüft, nie ein Mittelwert.** Genau
/// das ist der Fehler, der den hellen Endpunkt `#22D3EE` des Design-Sets
/// durchgelassen hätte: Über den Verlauf gemittelt sieht Weiß gut aus, am
/// hellen Ende steht es bei 1,81:1.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/theme.dart';
import 'package:mitfahrbar/core/tokens.dart';

/// Schwellwerte aus WCAG 2.1.
const _text = 4.5;
const _graphic = 3.0;

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final lumA = _luminance(a);
  final lumB = _luminance(b);
  return (math.max(lumA, lumB) + 0.05) / (math.min(lumA, lumB) + 0.05);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _expectContrast(Color front, Color back, double minimum, String what) {
  final ratio = _contrast(front, back);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason:
        '$what: ${_hex(front)} auf ${_hex(back)} trägt nur '
        '${ratio.toStringAsFixed(2)}:1, gefordert sind $minimum:1.',
  );
}

/// Alle Farben, auf denen im Banner Text stehen kann — bei einem Verlauf
/// jeder Stopp, sonst die Fläche.
List<Color> _surfacesOf(BannerTone tone) {
  final gradient = tone.gradient;
  return gradient == null ? [tone.surface] : gradient.colors;
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dunkel' : 'hell';

    group('Banner ($name)', () {
      test('Text steht auf jeder Fläche lesbar', () {
        final tones = {
          'Nächste Fahrt': AppBannerTones.nextRide(brightness),
          'Update-Hinweis': AppBannerTones.update(brightness),
          'Ruhiges Banner': AppBannerTones.quiet(brightness),
        };
        for (final entry in tones.entries) {
          for (final surface in _surfacesOf(entry.value)) {
            _expectContrast(
              entry.value.foreground,
              surface,
              _text,
              '${entry.key} ($name)',
            );
          }
        }
      });
    });

    group('Anmerkungen ($name)', () {
      test('der Akzent steht auf dem Blatt des Schirms lesbar', () {
        final theme = brightness == Brightness.dark
            ? darkTheme()
            : lightTheme();
        _expectContrast(
          AppAccents.notes(brightness),
          theme.colorScheme.surface,
          _text,
          'Anmerkungs-Akzent ($name)',
        );
      });

      test('der Absende-Knopf trägt seine eigene Beschriftung', () {
        _expectContrast(
          AppAccents.notesInk(brightness),
          AppAccents.notes(brightness),
          _text,
          'Absende-Knopf ($name)',
        );
      });
    });
  }

  group('Anmerkungs-Zähler auf dem Fahrt-Banner', () {
    // Der Zähler ist in hell wie dunkel derselbe Chip: Er sitzt in beiden
    // Fällen auf dem dunklen Ende desselben Verlaufs.
    final gradient =
        AppBannerTones.nextRide(Brightness.light).gradient! as LinearGradient;

    test('der Verlauf endet dunkel — dort sitzt der Zähler', () {
      expect(
        _luminance(gradient.colors.last),
        lessThan(_luminance(gradient.colors.first)),
        reason:
            'Das Design-Set zeichnet „Deep Teal Flow" dunkel nach hell. Im '
            'Banner läuft er gespiegelt, weil rechts der Anmerkungs-Zähler '
            'sitzt: Auf dem hellen Teal trägt der Magenta-Chip 1,61:1 und '
            'ist unsichtbar. Wer die Richtung zurückdreht, macht ihn '
            'unlesbar — die Fläche allein sieht dabei weiter gut aus.',
      );
    });

    test('der Chip trennt sich von der Fläche, auf der er sitzt', () {
      _expectContrast(
        AppAccents.notesChip,
        gradient.colors.last,
        _graphic,
        'Zähler-Chip gegen das dunkle Verlaufsende',
      );
    });

    test('die Zahl im Chip ist lesbar', () {
      _expectContrast(
        AppAccents.notesChipInk,
        AppAccents.notesChip,
        _text,
        'Zahl im Zähler',
      );
    });
  });

  group('Push', () {
    test('die Vordergrund-Meldung ist lesbar', () {
      _expectContrast(AppPush.ink, AppPush.surface, _text, 'Text der Meldung');
      _expectContrast(
        AppPush.action,
        AppPush.surface,
        _text,
        'Knopf „Woche" der Meldung',
      );
    });

    // Android färbt damit das kleine Icon und die App-Zeile im
    // Benachrichtigungs-Schatten. Der Schatten trägt die Helligkeit des
    // Systems, nicht die der App — deshalb zwei Werte, und deshalb wird
    // jeder gegen den Schatten geprüft, in dem er wirklich landet.
    test('der Android-Akzent hebt sich im Schatten ab', () {
      final accents = {
        'hell': (
          file: File('android/app/src/main/res/values/colors.xml'),
          shade: const Color(0xFFFFFFFF),
        ),
        'dunkel': (
          file: File('android/app/src/main/res/values-night/colors.xml'),
          shade: const Color(0xFF1B1B1B),
        ),
      };
      for (final entry in accents.entries) {
        expect(
          entry.value.file.existsSync(),
          isTrue,
          reason:
              '${entry.value.file.path} fehlt — ohne die Datei löst '
              '`@color/notification_accent` im Manifest nicht auf und der '
              'Android-Build bricht ab.',
        );
        final match = RegExp(
          r'name="notification_accent">\s*#([0-9A-Fa-f]{6})\s*<',
        ).firstMatch(entry.value.file.readAsStringSync());
        expect(
          match,
          isNotNull,
          reason:
              'In ${entry.value.file.path} steht keine Farbe namens '
              'notification_accent.',
        );
        _expectContrast(
          Color(0xFF000000 | int.parse(match!.group(1)!, radix: 16)),
          entry.value.shade,
          _graphic,
          'Android-Benachrichtigungs-Akzent (${entry.key})',
        );
      }
    });
  });
}

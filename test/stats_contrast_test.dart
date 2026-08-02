/// stats_contrast_test.dart – Rechnet jedes Farbpaar der Statistik-Seite nach.
///
/// Dieselbe Rechnung wie `banner_contrast_test.dart` und derselbe Anlass:
/// Zwei Banner-Vorschläge, die gut aussahen, fielen bei der ersten Messung
/// durch. Für die Statistik-Seite kamen bei der Kandidaten-Messung gleich
/// zwei weitere dazu — `outlineVariant` als Übertrag-Segment (1,53:1,
/// unsichtbar) und eine Heatmap-Spitze mit Restdeckung 0,9 (2,94:1, knapp
/// durchgefallen). Beides steht jetzt hier fest.
///
/// **Bei einem Verlauf wird jeder Stopp geprüft, nie ein Mittelwert.**
library;

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

List<Color> _surfacesOf(BannerTone tone) {
  final gradient = tone.gradient;
  return gradient == null ? [tone.surface] : gradient.colors;
}

void main() {
  for (final brightness in Brightness.values) {
    final name = brightness == Brightness.dark ? 'dunkel' : 'hell';
    final scheme = (brightness == Brightness.dark ? darkTheme() : lightTheme())
        .colorScheme;
    // Die Fläche, auf der alle Statistik-Karten stehen: M3-Card ohne
    // Farb-Override zeichnet `surfaceContainerLow`.
    final card = scheme.surfaceContainerLow;

    group('Statistik-Karten ($name)', () {
      test('die Saldo-Texte sind auf der Karte lesbar', () {
        _expectContrast(
          AppStatsColors.saldoPositive(brightness),
          card,
          _text,
          'Positiver Saldo ($name)',
        );
        _expectContrast(
          AppStatsColors.saldoNegative(brightness),
          card,
          _text,
          'Negativer Saldo ($name)',
        );
      });

      test('Balken- und Ring-Farben trennen sich von der Karte', () {
        _expectContrast(
          AppStatsColors.record(brightness),
          card,
          _graphic,
          'Rekord-Balken ($name)',
        );
        _expectContrast(
          AppStatsColors.eco(brightness),
          card,
          _graphic,
          'Eco-Grafikton ($name)',
        );
      });

      test('das Übertrag-Segment des Rings ist sichtbar', () {
        // `outlineVariant` sähe gut aus und trüge nur 1,53:1 (hell) — das
        // Segment wäre unsichtbar und der Ring summierte sichtbar falsch.
        _expectContrast(
          scheme.outline,
          card,
          _graphic,
          'Übertrag-Segment ($name)',
        );
      });

      test('die dunkelste Heatmap-Zelle trennt sich von der Karte', () {
        // Die Zellen-Skala MUSS bei voller Deckung enden: `primary` mit
        // Restdeckung 0,9 über der hellen Karte trägt nur 2,94:1.
        _expectContrast(
          scheme.primary,
          card,
          _graphic,
          'Heatmap-Maximum ($name)',
        );
      });
    });
  }

  group('Insight-Karten', () {
    test('die Schrift steht auf JEDEM Verlaufs-Stopp lesbar', () {
      final tones = {
        'Bright (dunkle Tinte auf hellem Teal)': AppInsightTones.bright,
        'Deep (Weiß auf dunklem Teal)': AppInsightTones.deep,
      };
      for (final entry in tones.entries) {
        for (final surface in _surfacesOf(entry.value)) {
          _expectContrast(
            entry.value.foreground,
            surface,
            _text,
            entry.key,
          );
        }
      }
    });

    test('der schlechteste Stopp ist als surface hinterlegt', () {
      // `BannerTone.surface` ist der Ton, gegen den gemessen wird, wenn
      // jemand nur die Fläche liest — er muss der schwächste Stopp sein.
      for (final tone in [AppInsightTones.bright, AppInsightTones.deep]) {
        final worst = _surfacesOf(tone).reduce(
          (a, b) =>
              _contrast(tone.foreground, a) <= _contrast(tone.foreground, b)
              ? a
              : b,
        );
        expect(
          tone.surface,
          worst,
          reason: 'sonst rechnete ein späterer Test gegen den falschen Stopp',
        );
      }
    });
  });
}

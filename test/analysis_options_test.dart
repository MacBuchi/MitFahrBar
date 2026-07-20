/// analysis_options_test.dart – Schützt die Regeln, die CLAUDE.md fordert.
///
/// Dieselbe Falle wie beim Android-Manifest: Wird hier eine Regel entfernt,
/// bleibt `flutter analyze` grün und die Leitplanke verschwindet lautlos. Erst
/// der nächste `print` in `lib/` oder das nächste vergessene `mounted` fällt
/// auf — dann aber niemandem.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final options = File('analysis_options.yaml');
  final raw = options.existsSync() ? options.readAsStringSync() : '';

  // Ohne Kommentare prüfen: Die Datei *warnt* vor `require_trailing_commas`,
  // und eine Warnung davor ist das Gegenteil eines Eintrags.
  final content = raw
      .split('\n')
      .map((line) => line.split('#').first)
      .join('\n');

  test('analysis_options.yaml existiert', () {
    expect(options.existsSync(), isTrue);
  });

  group('Leitplanken aus CLAUDE.md', () {
    test('kein print in lib/ ist ein Fehler, keine Anregung', () {
      expect(
        content,
        contains('avoid_print: error'),
        reason:
            'CLAUDE.md verbietet print in lib/ — die Regel gehört auf error, '
            'damit das im Editor als Verstoß und nicht als Vorschlag steht.',
      );
    });

    test('BuildContext nach await ist ein Fehler', () {
      expect(
        content,
        contains('use_build_context_synchronously: error'),
        reason:
            'Ein BuildContext nach await ist die Ursache echter Abstürze — '
            'siehe die Provider-Invalidierung aus v0.5.0.',
      );
    });

    test('vergessene Futures werden gemeldet', () {
      expect(
        content,
        contains('unawaited_futures'),
        reason:
            'Ein vergessenes await auf einem Repository-Aufruf schlägt still '
            'fehl: Der Fehler landet im Nichts, die UI meldet Erfolg.',
      );
    });
  });

  // Der Vorschlag aus Issue #21 enthielt diese Regel; sie wurde nach Dart 3.7
  // entfernt, weil der Formatter die Kommas selbst setzt. Eingetragen erzeugt
  // sie eine „undefined lint rule" — und die macht die CI rot, ohne dass am
  // Code etwas falsch wäre.
  test('require_trailing_commas steht nicht drin', () {
    expect(
      content,
      isNot(contains('require_trailing_commas')),
      reason:
          'Die Regel existiert seit Dart 3.7 nicht mehr; ein Eintrag macht '
          'die CI rot.',
    );
  });
}

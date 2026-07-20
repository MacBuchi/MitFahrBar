/// licenses_test.dart – Hält die Schrift-Lizenzen bei den Schriften.
library;

import 'dart:io';

import 'package:fahrgemeinschaft/core/licenses.dart';
import 'package:flutter_test/flutter_test.dart';

// Die SIL OFL verlangt, dass ihr Text mit den Schriften ausgeliefert wird.
// Die Registrierung in `core/licenses.dart` lädt ihn über `rootBundle` — geht
// eine der Dateien verloren oder wird sie umbenannt, kompiliert das sauber
// durch und fällt erst zur Laufzeit auf, im Lizenz-Dialog, den kaum jemand
// öffnet. Dieser Test macht den Bruch beim Build sichtbar.
void main() {
  group('Schrift-Lizenzen', () {
    test('für jede gebündelte Schrift ist eine Lizenz registriert', () {
      expect(
        fontLicenses.keys,
        containsAll(<String>['Space Grotesk', 'Manrope']),
        reason:
            'Beide Schriften stehen unter der SIL OFL und brauchen einen '
            'Eintrag, sonst fehlt ihr Lizenztext in der App.',
      );
    });

    for (final entry in fontLicenses.entries) {
      test('${entry.key}: der Lizenztext liegt beim Font', () {
        final file = File(entry.value);
        expect(
          file.existsSync(),
          isTrue,
          reason:
              '${entry.value} fehlt. Der Pfad wird in core/licenses.dart per '
              'rootBundle geladen — ohne die Datei bleibt der Dialog leer.',
        );

        final text = file.readAsStringSync();
        expect(
          text,
          contains('SIL OPEN FONT LICENSE Version 1.1'),
          reason:
              '${entry.value} enthält nicht den vollständigen OFL-Text. Die '
              'Lizenz verlangt die Weitergabe im Wortlaut, nicht nur einen '
              'Verweis.',
        );
        expect(
          text,
          contains('Copyright'),
          reason:
              'Der Copyright-Vermerk der Schrift muss erhalten bleiben — die '
              'OFL nennt ihn ausdrücklich als Bedingung.',
        );
      });
    }

    test('die Lizenz-Assets werden mit ausgeliefert', () {
      // Ohne den Asset-Eintrag landen die Dateien nicht im Bundle und
      // rootBundle.loadString wirft zur Laufzeit.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('- assets/fonts/'),
        reason:
            'assets/fonts/ muss in pubspec.yaml als Asset stehen, sonst sind '
            'die OFL-Texte im Release nicht ladbar.',
      );
    });
  });
}

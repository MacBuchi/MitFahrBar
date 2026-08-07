/// licenses_test.dart – Hält die Schrift-Lizenzen bei den Schriften.
library;

import 'dart:io';

import 'package:mitfahrbar/core/licenses.dart';
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

    // Der bisherige Test prüft die Schriften, die wir KENNEN. Die
    // Gegenrichtung fehlte: Wer eine dritte Schrift oder ein neues
    // Asset-Verzeichnis bündelt, tut das bisher unbemerkt — und genau
    // dieser Fall ist in pilzbuddy eingetreten (Kartenglyphen aus Noto
    // Sans ausgeliefert, ihr OFL-Text nicht einmal im Bundle). Gebaut wie
    // dortiges `test/privacy_policy_test.dart`: Nicht die Lizenzseite auf
    // Vollständigkeit prüfen (das kann kein Test), sondern das
    // Ausgelieferte aufzählen und alles Unklassifizierte melden.

    /// Mitgelieferte Fremdinhalte und der Grund, warum ihre Lizenz
    /// abgehandelt ist. Wer hier einträgt, hat entschieden.
    const attributedAssets = <String, String>{
      // Die beiden Schriften plus ihre OFL-Texte, registriert über
      // `fontLicenses` in lib/core/licenses.dart.
      'assets/fonts/': 'SIL OFL, registriert in core/licenses.dart',
    };

    /// Eigenerzeugnis — keine fremde Lizenz, nichts zu attribuieren.
    const ownWorkAssets = <String>{};

    List<String> declaredAssets() {
      final lines = File('pubspec.yaml').readAsLinesSync();
      final start = lines.indexWhere((l) => l.trimRight() == '  assets:');
      expect(start, isNot(-1), reason: 'assets:-Block fehlt in pubspec.yaml');
      final assets = <String>[];
      for (final line in lines.skip(start + 1)) {
        if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
        final match = RegExp(r'^\s+- (.+)$').firstMatch(line);
        // Erste Zeile, die kein Listeneintrag mehr ist, beendet den Block.
        if (match == null) break;
        assets.add(match.group(1)!.trim());
      }
      expect(
        assets,
        isNotEmpty,
        reason: 'Keine Assets gelesen — Regex kaputt?',
      );
      return assets;
    }

    test('kein mitgeliefertes Asset ohne Lizenz-Entscheidung', () {
      final unknown = declaredAssets().where(
        (a) => !attributedAssets.containsKey(a) && !ownWorkAssets.contains(a),
      );
      expect(
        unknown,
        isEmpty,
        reason:
            'Neues Asset in pubspec.yaml: ${unknown.join(", ")}. Entscheide, '
            'ob es Eigenerzeugnis ist — dann in ownWorkAssets eintragen — '
            'oder fremdes Material: dann gehört seine Lizenz mitgeliefert '
            'und registriert, und der Grund hier in attributedAssets.',
      );
    });

    test('jede deklarierte Schrift hat einen Lizenz-Eintrag', () {
      // `fonts:` ist die Liste, die wirklich ins Binary geht. Eine dritte
      // Familie dort ohne Eintrag in `fontLicenses` liefert die Schrift
      // aus und ihren Lizenztext nicht — bei der OFL ist das genau die
      // Bedingung, unter der wir sie überhaupt verwenden dürfen.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final families = RegExp(
        r'^\s+- family:\s*(.+)$',
        multiLine: true,
      ).allMatches(pubspec).map((m) => m.group(1)!.trim()).toList();
      expect(families, isNotEmpty, reason: 'fonts:-Block nicht gelesen');

      // Die Familie heißt in pubspec.yaml ohne Leerzeichen („SpaceGrotesk"),
      // im Lizenz-Eintrag mit („Space Grotesk") — verglichen wird deshalb
      // normalisiert statt wörtlich.
      String squash(String s) => s.replaceAll(' ', '').toLowerCase();
      final registered = fontLicenses.keys.map(squash).toSet();

      for (final family in families) {
        expect(
          registered,
          contains(squash(family)),
          reason:
              'Die Schrift „$family" wird ausgeliefert, hat aber keinen '
              'Eintrag in fontLicenses (lib/core/licenses.dart). Ohne den '
              'erreicht ihr Lizenztext niemanden.',
        );
      }
    });

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

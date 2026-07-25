/// release_workflow_test.dart – Release-only-Fallen im Release-Workflow.
///
/// Der v0.34.1-Lauf starb NACH dem Taggen (25.07.2026): `cp` erzeugte
/// `mitfahrbar-*.apk`, `upload-artifact` suchte noch `fahrgemeinschaft-*.apk`
/// — sauber kompiliert, grün in jeder PR-CI, gescheitert erst im echten
/// Release. Zurück blieb ein Tag ohne Release, den die Tag-Entscheidung
/// fortan als „schon veröffentlicht" wertete: Ohne Handeingriff (Tag
/// löschen) wäre die Version nie erschienen. Dieselbe Linie wie
/// `android_manifest_test.dart`: Solche Fehler fängt nur ein
/// Konfigurations-Regressionstest.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('alle APK-Namen in release.yml tragen denselben Stamm', () {
    // `${{ … }}`-Ausdrücke enthalten Leerzeichen und zerrissen sonst das
    // Token — sie stehen hier stellvertretend als TAG.
    final yml = File(
      '.github/workflows/release.yml',
    ).readAsStringSync().replaceAll(RegExp(r'\$\{\{[^}]*\}\}'), 'TAG');
    final refs = RegExp(
      r'[^\s"]*\.apk',
    ).allMatches(yml).map((m) => m.group(0)!).toList();

    // cp-Ziel, upload-artifact-Pfad und die Release-Dateiliste — weniger
    // hieße, eine der drei Stellen ist verschwunden oder umgebaut.
    final assets = refs.where((r) => !r.endsWith('app-release.apk')).toList();
    expect(
      assets.length,
      greaterThanOrEqualTo(3),
      reason:
          'cp-Ziel, upload-Pfad und Release-Dateiliste müssen die APK '
          'benennen — fehlt eine Stelle, bitte diesen Test mitziehen.',
    );
    for (final ref in assets) {
      expect(
        ref.split('/').last,
        startsWith('mitfahrbar-'),
        reason:
            '„$ref" fällt aus der Reihe. Alle drei Stellen (cp, upload, '
            'release-files) müssen denselben Stamm tragen, sonst reißt der '
            'Release-Lauf nach dem Taggen ab wie bei v0.34.1.',
      );
    }
  });
}

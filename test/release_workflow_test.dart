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
  // Zwei Kanäle seit #217: Jeder Merge veröffentlicht ein **Prerelease**,
  // die Gruppe sieht nur, was `promote.yml` freigibt. Der Riegel ist eine
  // einzige Zeile YAML — und wenn sie verlorengeht, merkt es niemand, außer
  // die Gruppe bekommt plötzlich wieder sechs Update-Hinweise am Tag.
  group('Release-Kanäle (#217)', () {
    final release = File('.github/workflows/release.yml').readAsStringSync();
    final promote = File('.github/workflows/promote.yml').readAsStringSync();

    test('jeder Merge veröffentlicht als Prerelease, nie als latest', () {
      expect(
        release,
        contains('prerelease: true'),
        reason:
            'Ohne die Markierung erscheint jeder Merge in `/releases/latest` '
            '— genau der Zustand, den #217 abgestellt hat.',
      );
      expect(
        release,
        contains('make_latest: false'),
        reason:
            'GitHub setzt das neueste Release sonst TROTZ Prerelease-Flag '
            'als „latest". Beide Zeilen gehören zusammen; eine allein '
            'genügt nicht.',
      );
    });

    test('release.yml deployt kein Pages — das tut nur die Beförderung', () {
      expect(
        release,
        isNot(contains('actions-gh-pages')),
        reason:
            'Das Web hängt an EINER URL. Deployte jeder Merge, bekäme die '
            'PWA jede Zwischenversion und die Trennung gälte nur für '
            'Android.',
      );
      expect(promote, contains('actions-gh-pages'));
      expect(
        promote,
        contains(r'git checkout "${{ steps.pick.outputs.tag }}"'),
        reason:
            'Pages muss aus dem BEFÖRDERTEN Tag gebaut werden. Aus main '
            'gebaut läge auf der Web-Adresse der Entwicklungsstand, während '
            'Android auf stabil zeigt.',
      );
    });

    test('die Beförderung schaltet stabil UND sammelt die Notizen', () {
      expect(promote, contains('--prerelease=false'));
      expect(promote, contains('--latest'));
      expect(
        promote,
        contains('--notes-file release-body.md'),
        reason: 'Sonst bliebe der Prerelease-Text des einen Merges stehen.',
      );
      // Die Sammel-Grenze ist der Kern: Ohne sie stünde unter „Was ist neu"
      // nur der Abschnitt der beförderten Version, und alles dazwischen
      // fehlte der Gruppe.
      expect(
        promote,
        contains(r'$0 ~ "^## \\[" prev "\\]" { exit }'),
        reason:
            'Die Notizen müssen bis zum letzten STABILEN Abschnitt laufen, '
            'nicht bis zum nächsten überhaupt.',
      );
    });
  });

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

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

    // Am 11.08.2026 riss die Beförderung genau zwischen diesen beiden
    // Schritten ab: `gh release view --json … isLatest` kennt neuere
    // gh-Fassungen nicht mehr, der Schritt scheiterte NACH dem Umschalten
    // und VOR dem Pages-Deploy. Ergebnis war ein halber Stand — Android auf
    // v0.80.0, das Web weiter auf v0.76.0. Dieselbe Klasse wie der
    // v0.34.1-Lauf, der nach dem Taggen starb: Der Workflow läuft selten,
    // von Hand, und ein Fehler darin fällt erst beim nächsten Mal auf.
    test('die Beförderung prüft ihr Ergebnis dort, wo die App nachsieht', () {
      expect(
        promote,
        contains('releases/latest'),
        reason:
            'Die Gegenprüfung muss den Endpunkt abfragen, an dem auch '
            '`core/update_check.dart` hängt — eine Prüfung woanders kann '
            'grün sein, während die Gruppe nichts angeboten bekommt.',
      );
      // Ohne Kommentare prüfen — dieselbe Lehre wie bei `sqlOnly` in
      // `schema_test.dart`: Ein File, das seine eigene Entscheidung
      // begründet, nennt den verbotenen Namen zwangsläufig.
      final yamlOnly = promote
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        yamlOnly,
        isNot(contains('isLatest')),
        reason:
            'Das Feld gibt es in neueren gh-Fassungen nicht mehr. Es hat den '
            'Lauf zwischen „stabil geschaltet" und „Pages deployt" '
            'abreißen lassen — der teuerste Moment dafür.',
      );
    });

    // Zweite Hälfte desselben Vorfalls: Der Reparaturlauf lief durch, aber
    // unter „Was ist neu" stand nur der Fallback-Link. Der erste Durchgang
    // hatte das Release bereits stabil geschaltet — der zweite fand als
    // „letzten stabilen Stand" also sich selbst und sammelte zwischen einer
    // Version und derselben, mithin nichts. Fünf Versionen Text fielen weg,
    // und gemerkt hätte es nur, wer die Release-Seite ansieht.
    test('der beförderte Stand zählt nicht als sein eigener Vorgänger', () {
      expect(
        promote,
        contains(r'select(.tagName != $tag)'),
        reason:
            'Ohne diesen Ausschluss liefert jeder WIEDERHOLTE Lauf leere '
            'Notizen — und wiederholt wird genau dann, wenn der erste Lauf '
            'auf halber Strecke gescheitert ist.',
      );
    });

    test('Pages wird nach dem Umschalten deployt, nicht davor', () {
      final stable = promote.indexOf('--prerelease=false');
      final pages = promote.indexOf('actions-gh-pages');
      expect(stable, isNonNegative);
      expect(pages, greaterThan(stable));
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

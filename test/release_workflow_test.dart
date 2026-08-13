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
        contains(r'!= "$TAG"'),
        reason:
            'Ohne diesen Ausschluss liefert jeder WIEDERHOLTE Lauf leere '
            'Notizen — und wiederholt wird genau dann, wenn der erste Lauf '
            'auf halber Strecke gescheitert ist.',
      );
    });

    // Der Ausschluss stand zuerst als jq-Variable da (`--jq --arg tag …`) und
    // riss den ersten Lauf ab, der ihn benutzte: `gh --jq` nimmt genau EINEN
    // Ausdruck und kennt jq's `--arg` nicht — gh las das Wort danach als
    // Befehl und meldete `unknown command "tag"`. Gescheitert ist es an der
    // harmlosen Stelle (vor dem Umschalten), aber gefunden hat es niemand
    // vorher, weil dieser Workflow nur von Hand läuft.
    test('gh bekommt keine jq-Variablen untergeschoben', () {
      final yamlOnly = promote
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        yamlOnly,
        isNot(contains('--arg')),
        reason:
            '`gh --jq` unterstützt keine jq-Argumente. Werte gehören in die '
            'Shell, nicht in den jq-Ausdruck.',
      );
    });

    test('Pages wird nach dem Umschalten deployt, nicht davor', () {
      final stable = promote.indexOf('--prerelease=false');
      final pages = promote.indexOf('actions-gh-pages');
      expect(stable, isNonNegative);
      expect(pages, greaterThan(stable));
    });
  });

  test('alle Artefakt-Namen in release.yml tragen denselben Stamm', () {
    // `${{ … }}`-Ausdrücke enthalten Leerzeichen und zerrissen sonst das
    // Token — sie stehen hier stellvertretend als TAG. Und ohne Kommentare
    // (die sqlOnly-Lehre): Ein Kommentar, der erklärt, warum das AAB nicht
    // ans Release gehört, nennt „.aab" zwangsläufig selbst.
    final yml = File('.github/workflows/release.yml')
        .readAsStringSync()
        .replaceAll(RegExp(r'\$\{\{[^}]*\}\}'), 'TAG')
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    final refs = RegExp(
      r'[^\s"]*\.(?:apk|aab)',
    ).allMatches(yml).map((m) => m.group(0)!).toList();

    // Die Build-Ausgaben tragen seit den Flavors deren Namen — sie sind
    // die QUELLEN der cp-Schritte, nicht die veröffentlichten Artefakte.
    final assets = refs
        .where((r) => !r.split('/').last.startsWith('app-'))
        .toList();
    // cp-Ziel + upload-Pfad für APK und AAB, dazu die Release-Dateiliste —
    // weniger hieße, eine der Stellen ist verschwunden oder umgebaut.
    expect(
      assets.length,
      greaterThanOrEqualTo(5),
      reason:
          'cp-Ziele, upload-Pfade (APK und AAB) und die Release-Dateiliste '
          'müssen die Artefakte benennen — fehlt eine Stelle, bitte diesen '
          'Test mitziehen.',
    );
    for (final ref in assets) {
      expect(
        ref.split('/').last,
        startsWith('mitfahrbar-'),
        reason:
            '„$ref" fällt aus der Reihe. Alle Stellen (cp, upload, '
            'release-files) müssen denselben Stamm tragen, sonst reißt der '
            'Release-Lauf nach dem Taggen ab wie bei v0.34.1.',
      );
    }
  });

  // Zwei Vertriebswege seit dem Play-Umbau: Der Flavor entscheidet, ob
  // REQUEST_INSTALL_PACKAGES im Artefakt steht — `github` braucht sie fürs
  // Selbst-Update, `play` darf sie nicht tragen. Und der Flavor steht im
  // Ausgabepfad: Ein cp auf den alten, flavorlosen Namen bricht erst NACH
  // dem Taggen ab (die v0.34.1-Klasse, in PilzBuddy beim selben Umbau
  // beinahe wiederholt).
  group('Vertriebswege (Flavors)', () {
    final release = File('.github/workflows/release.yml').readAsStringSync();
    final ci = File('.github/workflows/ci.yml').readAsStringSync();

    test('die veröffentlichte APK kommt aus dem github-Flavor', () {
      expect(release, contains('flutter build apk --release --flavor github'));
      expect(
        release,
        contains('flutter-apk/app-github-release.apk'),
        reason:
            'Mit Flavor heißt die Datei app-<flavor>-release.apk — der '
            'alte Pfad existiert nicht mehr, das cp bräche nach dem Taggen.',
      );
    });

    test(
      'das AAB kommt aus dem play-Flavor MIT abgeschaltetem Update-Pfad',
      () {
        expect(
          release,
          contains(
            'flutter build appbundle --release --flavor play '
            '--dart-define=PLAY_BUILD=true',
          ),
          reason:
              'Flavor und PLAY_BUILD sind zwei Hälften derselben Entscheidung: '
              'der Flavor nimmt die Berechtigung, das Flag den Dart-Pfad. Wer '
              'nur eine setzt, liefert eine halb abgeschaltete Funktion aus.',
        );
        expect(
          release,
          contains('bundle/playRelease/app-play-release.aab'),
          reason: 'Mit Flavor liegt das Bundle in bundle/<flavor>Release/.',
        );
        // Das AAB gehört NICHT an das GitHub-Release: Es lässt sich nicht
        // installieren und würde neben der APK nur verwirren. Es bleibt
        // Workflow-Artefakt für den Upload in die Play Console.
        final filesLine = RegExp(r'files:\s*\S+').firstMatch(release)?.group(0);
        expect(filesLine, isNotNull);
        expect(
          filesLine,
          isNot(contains('.aab')),
          reason: 'Ein AAB am GitHub-Release lässt sich nicht installieren.',
        );
      },
    );

    test('die GitHub-APK wird nie mit PLAY_BUILD gebaut', () {
      final apkCommand = RegExp(
        r'flutter build apk[^\n]*',
      ).allMatches(release).map((m) => m.group(0)!);
      for (final command in apkCommand) {
        expect(
          command,
          isNot(contains('PLAY_BUILD')),
          reason:
              'Die GitHub-APK MUSS ihren Update-Hinweis behalten — sonst '
              'aktualisiert sie niemand mehr, und es gibt dort keinen Store, '
              'der es übernähme.',
        );
      }
    });

    test(
      'die CI baut den play-Flavor, damit der Manifest-Merge dort bricht',
      () {
        expect(
          ci,
          contains('flutter build apk --release --flavor play'),
          reason:
              'github baut aus src/main wie eh und je; das einzig Neue ist das '
              'Zusammenführen von src/play/AndroidManifest.xml — und das soll '
              'in der PR-CI auffallen, nicht in release.yml nach dem Taggen.',
        );
      },
    );
  });
}

/// web_build_workflow_test.dart – Der Offline-Start hängt an zwei Zeilen je
/// Build-Stelle, und beide fallen nur im ausgelieferten Web auf (#232).
///
/// Dieselbe Klasse wie `release_workflow_test.dart`: Ein Web-Build ohne das
/// Injektionsskript liefert einen Worker mit leerem Manifest aus — er
/// installiert sich, cacht nichts und die PWA ist wieder eine Online-App.
/// Einer ohne `--no-web-resources-cdn` holt CanvasKit von gstatic; die Seite
/// wird dann zwar ausgeliefert, bleibt ohne Netz aber weiß. Beides ist grün
/// in jeder PR-CI und erst auf dem Gerät zu sehen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final ci = File('.github/workflows/ci.yml').readAsStringSync();
  final promote = File('.github/workflows/promote.yml').readAsStringSync();
  final e2e = File('tool/browser_e2e.sh').readAsStringSync();

  const injector = 'tool/inject_sw_manifest.py';

  group('Der Renderer kommt aus dem Build, nicht vom CDN (#232)', () {
    test('jeder Web-Build trägt --no-web-resources-cdn', () {
      for (final (name, source) in [
        ('ci.yml', ci),
        ('promote.yml', promote),
        ('browser_e2e.sh', e2e),
      ]) {
        expect(
          source,
          contains('--no-web-resources-cdn'),
          reason:
              'In $name lädt der Build sonst CanvasKit von '
              'www.gstatic.com nach. Der Service Worker kann nur '
              'vorhalten, was im Build liegt — ohne das Flag startet die '
              'PWA ohne Empfang zwar, zeigt aber eine weiße Seite.',
        );
      }
    });
  });

  group('Das Precache-Manifest wird zur Bauzeit eingesetzt (#232)', () {
    test('der Injektor existiert und ist ausführbar dokumentiert', () {
      expect(File(injector).existsSync(), isTrue);
    });

    test('jede ausgelieferte Build-Stelle ruft ihn auf', () {
      for (final (name, source) in [
        ('ci.yml', ci),
        ('promote.yml', promote),
        ('browser_e2e.sh', e2e),
      ]) {
        expect(
          source,
          contains(injector),
          reason:
              'Ohne den Aufruf in $name behält `sw.js` sein leeres '
              'Manifest. Er installiert sich dann, cacht nichts, und der '
              'Offline-Start fehlt — ohne dass irgendetwas rot wird.',
        );
      }
    });

    // Positionsvergleich statt bloßer Anwesenheit, dieselbe Bauart wie der
    // Reihenfolge-Test in `schema_test.dart`. Die Anwesenheit allein beweist
    // nichts: Steht die Injektion HINTER dem Pages-Deploy, wird das Manifest
    // in ein Verzeichnis geschrieben, das niemand mehr ausliefert — der Lauf
    // bleibt grün, und auf der Live-Adresse liegt ein Worker mit leerem
    // Manifest.
    test('in promote.yml steht sie zwischen Build und Deploy', () {
      final build = promote.indexOf('flutter build web');
      final inject = promote.indexOf(injector);
      final deploy = promote.indexOf('actions-gh-pages');

      expect(build, isNonNegative);
      expect(inject, isNonNegative);
      expect(deploy, isNonNegative);
      expect(
        inject,
        greaterThan(build),
        reason: 'Vor dem Build gäbe es kein build/web, das zu hashen wäre.',
      );
      expect(
        inject,
        lessThan(deploy),
        reason:
            'promote.yml ist die einzige Stelle, die wirklich ausliefert. '
            'Was danach passiert, sieht die Gruppe nie.',
      );
    });
  });
}

/// web_offline_test.dart – Die zwei Zeilen, ohne die die PWA ohne Empfang
/// nicht startet (#232).
///
/// Dieselbe Klasse wie `android_manifest_test.dart` und
/// `release_workflow_test.dart`: Konfiguration, die sauber kompiliert und
/// erst auf dem Gerät ausfällt — hier sogar erst ohne Netz, also genau dann,
/// wenn niemand nachsehen kann.
///
/// **Der gemessene Ausgangszustand** (Browser-E2E gegen einen echten Stack,
/// 10.08.2026): Im ausgelieferten Bau stand im Geltungsbereich `/` nur der
/// Push-Worker von Firebase, die Cache-Ablage war leer, ein Neuladen ohne
/// Netz endete in `ERR_INTERNET_DISCONNECTED`. Die Gegenprobe ohne Firebase
/// zeigte **gar keinen** Worker: Flutters eigener Ladeweg registriert in
/// 3.44 nichts mehr, `flutter_bootstrap.js` führt ihn selbst als deprecated.
///
/// **Beide Hälften gehören zusammen, und das ist der Grund für diese Datei.**
/// Ein Worker ohne lokales CanvasKit liefert die Seite aus, die dann weiß
/// bleibt — der Renderer käme von gstatic, und eine fremde Adresse hält kein
/// Service Worker vor. Wer eine der beiden Zeilen „aufräumt", bekommt keinen
/// Fehler, sondern eine App, die ohne Empfang nicht mehr hochkommt.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('index.html registriert den App-Worker selbst', () {
    final html = File('web/index.html').readAsStringSync();

    expect(
      html,
      contains("navigator.serviceWorker.register('flutter_service_worker.js')"),
      reason:
          'ohne eigene Registrierung steht im Geltungsbereich gar kein '
          'App-Worker — Flutters Bootstrap-Weg tut es in 3.44 nicht mehr',
    );
    // Relativ, nicht absolut: Der Pfad löst gegen das <base href> auf, das
    // Flutter aus `--base-href` schreibt (auf Pages „/MitFahrBar/"). Ein
    // absoluter Pfad wäre eine zweite Stelle, die mit release.yml synchron
    // bleiben müsste — dieselbe Falle wie bei `webServiceWorkerPath`.
    expect(
      html,
      isNot(contains("register('/flutter_service_worker.js')")),
      reason: 'ein absoluter Pfad zeigt unter /MitFahrBar/ ins Leere',
    );
  });

  test('jeder ausgelieferte Web-Build legt CanvasKit neben die App', () {
    // Der Pages-Deploy ist der, auf den es ankommt; der Browser-E2E muss
    // dasselbe bauen, sonst misst er einen anderen Aufbau als den echten.
    final builds = {
      '.github/workflows/promote.yml': 'Pages-Deploy (was die Gruppe lädt)',
      'tool/browser_e2e.sh': 'Browser-E2E (misst den Offline-Start)',
    };
    for (final entry in builds.entries) {
      expect(
        File(entry.key).readAsStringSync(),
        contains('--no-web-resources-cdn'),
        reason:
            '${entry.value}: ohne den Schalter kommt CanvasKit von gstatic, '
            'und die Seite bleibt ohne Netz weiß — auch mit Service Worker',
      );
    }
  });
}

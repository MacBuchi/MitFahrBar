/// web_offline_test.dart – Was `flutter_service_worker.js` in 3.44 wirklich
/// ist, und warum ihn niemand registrieren darf (#232).
///
/// Die Datei sieht aus wie der Offline-Zwischenspeicher von Flutter Web und
/// ist das Gegenteil: 784 Bytes, kein Ressourcen-Manifest, und im `activate`
/// steht `self.registration.unregister()` samt Neuladen aller Clients. Sie
/// existiert nur noch, um früher installierte Worker **abzuräumen** — einen
/// App-Shell-Cache gibt es in Flutter Web nicht mehr, und genau deshalb
/// führt `flutter_bootstrap.js` seinen Ladeweg als deprecated.
///
/// **Warum das ein Test ist und keine Notiz:** Der Name lädt dazu ein, ihn
/// zu registrieren, wenn die PWA ohne Empfang nicht startet — das ist die
/// naheliegende Reparatur, sie stand am 10.08.2026 schon einmal in
/// `web/index.html` (v0.80.0-Versuch, zurückgenommen), und sie macht es
/// **schlimmer**: Der Worker meldet sich ab und lädt die Seite neu. Im
/// Browser-E2E sah man davon nichts außer einer weiterhin leeren Ablage.
///
/// Der Offline-Start der PWA braucht einen **eigenen** Service Worker plus
/// `--no-web-resources-cdn` (sonst kommt der Renderer von gstatic, und die
/// Seite bleibt ohne Netz weiß). Solange es den nicht gibt, ist die PWA eine
/// Online-App — auf Android ist nichts davon betroffen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('index.html registriert Flutters Selbstzerstörer-Worker nicht', () {
    expect(
      File('web/index.html').readAsStringSync(),
      isNot(contains('flutter_service_worker.js')),
      reason:
          'der Worker meldet sich im activate selbst ab und lädt alle '
          'Clients neu — registriert ist er schädlich, nicht wirkungslos',
    );
  });
}

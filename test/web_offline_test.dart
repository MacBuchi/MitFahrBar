/// web_offline_test.dart – Warum die PWA ohne Empfang startet, und woran das
/// hängt (#232).
///
/// Der Offline-Start des Webs hängt an vier Dateien, von denen keine in
/// `flutter test` je ausgeführt wird: `web/sw.js`, `web/flutter_bootstrap.js`,
/// `web/index.html` und der Injektor, der das Precache-Manifest zur Bauzeit
/// einsetzt. Fällt eine davon weg, kompiliert alles sauber, jeder Widget-Test
/// bleibt grün — und die App startet auf dem Gerät nicht mehr ohne Netz.
/// Dieselbe Fehlerklasse wie `android_manifest_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final index = File('web/index.html').readAsStringSync();

  /// Die Datei sieht aus wie der Offline-Zwischenspeicher von Flutter Web und
  /// ist das Gegenteil: 784 Bytes, kein Ressourcen-Manifest, und im `activate`
  /// steht `self.registration.unregister()` samt Neuladen aller Clients. Sie
  /// existiert nur noch, um früher installierte Worker **abzuräumen** — einen
  /// App-Shell-Cache gibt es in Flutter Web nicht mehr.
  group('Flutters Selbstzerstörer-Worker (#232)', () {
    test('index.html registriert ihn nicht', () {
      expect(
        index,
        isNot(contains('flutter_service_worker.js')),
        reason:
            'der Worker meldet sich im activate selbst ab und lädt alle '
            'Clients neu — registriert ist er schädlich, nicht wirkungslos. '
            'Der Name lädt dazu ein, ihn zu registrieren, wenn die PWA ohne '
            'Empfang nicht startet; genau so stand er am 10.08.2026 schon '
            'einmal hier (v0.80.0-Versuch, zurückgenommen).',
      );
    });

    // Der eigentliche Riegel, und der unscheinbarste: `_flutter.loader.load()`
    // registriert den Stummel selbst, sobald im Geltungsbereich **irgendeine**
    // Registrierung existiert — der Aufräumpfad, für den er gebaut ist. Mit
    // unserem eigenen Worker ist danach immer eine da. Der Stummel landete
    // also als `waiting`, aktivierte beim nächsten Start als Erstes und
    // meldete alles ab: Der Offline-Start wäre jede zweite Sitzung tot, und im
    // Browser sieht man davon nur eine leere Ablage.
    test('der eigene Bootstrap übergibt keine serviceWorkerSettings', () {
      final bootstrap = File('web/flutter_bootstrap.js');
      expect(
        bootstrap.existsSync(),
        isTrue,
        reason:
            'Ohne eigene Vorlage schreibt Flutter die Standardfassung MIT '
            '`serviceWorkerSettings` in den Build — und die registriert den '
            'Selbstzerstörer nach.',
      );
      final source = bootstrap.readAsStringSync();
      // Ohne Kommentare prüfen — dieselbe Lehre wie bei `sqlOnly` in
      // `schema_test.dart`: Ein File, das seine eigene Entscheidung
      // begründet, nennt den verbotenen Namen zwangsläufig.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        code,
        isNot(contains('serviceWorkerSettings')),
        reason:
            'Ohne das Feld kehrt `loadServiceWorker` sofort zurück '
            '(`if (!e || …) return Promise.resolve()`). Mit dem Feld '
            'registriert der Loader `flutter_service_worker.js` — auch dann, '
            'wenn index.html längst unseren eigenen Worker registriert hat.',
      );
      expect(
        source,
        stringContainsInOrder(['{{flutter_js}}', '{{flutter_build_config}}']),
        reason:
            'Die beiden Platzhalter füllt `flutter build web`. Fehlen sie, '
            'lädt die Seite die Engine nie — und zwar nur im Build, nicht '
            'hier im Quelltext.',
      );
    });
  });

  group('Eigener App-Shell-Worker (#232)', () {
    final worker = File('web/sw.js');

    test('index.html registriert ihn relativ', () {
      expect(worker.existsSync(), isTrue);
      expect(
        index,
        contains("navigator.serviceWorker.register('sw.js')"),
        reason:
            'Ohne diese Zeile gibt es beim ersten Besuch keinen Worker: '
            'flutter_bootstrap.js registriert in 3.44 von sich aus keinen, '
            'und das FCM-SDK erst beim Token-Abruf — also erst nach der '
            'Anmeldung und nur mit erteilter Berechtigung.',
      );
      expect(
        index,
        isNot(contains("register('/sw.js')")),
        reason:
            'Absolut zeigte auf den Origin-Root; die App liegt auf Pages '
            'unter /MitFahrBar/. Relativ löst der Browser gegen das '
            '<base href> auf — dieselbe Regel wie beim Push-Worker-Pfad.',
      );
    });

    test('er trägt die Platzhalter, die der Injektor füllt', () {
      final source = worker.readAsStringSync();
      expect(
        source,
        contains('const BUILD ='),
        reason:
            'Der Bauhash benennt den Cache. Ohne ihn hieße jeder Cache '
            'gleich, und ein Update ersetzte den alten Inhalt nie.',
      );
      expect(
        source,
        contains('const MANIFEST ='),
        reason:
            'Die Dateiliste kommt aus tool/inject_sw_manifest.py. Der '
            'Quelltext hier hält sie leer — ein Build ohne Injektion cacht '
            'damit nichts, statt eine halbe Shell vorzuhalten.',
      );
    });

    // Es gibt je Geltungsbereich genau EINEN Worker: Wer zuletzt registriert,
    // ersetzt den davor. Zwei Dateien nebeneinander hieße also, dass Push und
    // Offline-Start sich abwechselnd abschalten.
    test('er bringt den Push-Worker mit, statt ihn zu verdrängen', () {
      expect(
        worker.readAsStringSync(),
        contains("importScripts('firebase-messaging-sw.js')"),
        reason:
            'Sonst verdrängt die Registrierung aus index.html den '
            'FCM-Worker, und die PWA bekommt keine Benachrichtigungen mehr '
            '— sichtbar erst auf einem echten Gerät.',
      );
    });

    // Der Knopf „Neu laden" ist die einzige Stelle, an der jemand aktiv eine
    // neue Fassung anfordert. Mit einer cache-first ausgelieferten Shell holt
    // ein blankes `location.reload()` genau die alte zurück — die Klasse
    // „toter Knopf" aus 0.37.0, diesmal im Web.
    test('„Neu laden" aktiviert den wartenden Worker', () {
      final source = File('lib/core/reload_app_web.dart').readAsStringSync();
      expect(
        source,
        contains('skipWaiting'),
        reason:
            'Ohne die Nachricht bleibt der neue Worker `waiting`, bis die '
            'PWA vollständig geschlossen wird — der Knopf lieferte die alte '
            'Fassung zurück und sähe dabei aus, als hätte er gewirkt.',
      );
      expect(
        source,
        contains('controllerchange'),
        reason:
            'Erst dieses Ereignis sagt, dass der neue Worker die Seite '
            'übernommen hat. Sofort neu geladen käme wieder die alte Shell.',
      );
      // Web-Code läuft in `flutter test` (VM) nie — dieser Textabgleich ist
      // diesseits einer Beförderung die einzige Wache über die Kette.
      expect(
        source,
        contains('location.reload'),
        reason:
            'Jeder Zweig muss im Neuladen enden. Hängt die Kette am '
            'wartenden Worker fest, täte der Knopf gar nichts.',
      );
    });
  });
}

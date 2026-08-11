/// push_service_worker_test.dart – Der Web-Push hängt an einem Dateipfad,
/// der nur im ausgelieferten Build falsch sein kann.
///
/// Dieselbe Fehlerklasse wie `android_manifest_test.dart`: Es kompiliert
/// sauber, jeder Widget-Test läuft grün — und in der PWA bekommt niemand
/// je ein Token, weil das FCM-SDK den Worker an einer Stelle sucht, an der
/// er nicht liegt. Genau so lag es bis 0.39.0: Die App wird mit
/// `--base-href /MitFahrBar/` gebaut, das SDK registrierte aber ohne
/// Angabe `/firebase-messaging-sw.js` am **Origin-Root** — dort 404,
/// `getToken` scheiterte dauerhaft, und der Benachrichtigungs-Screen ließ
/// sich nicht einmal einer Person zuordnen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/push_messaging.dart';

void main() {
  test('der Worker-Pfad ist relativ, nicht absolut', () {
    expect(
      webServiceWorkerPath,
      isNot(startsWith('/')),
      reason:
          'Ein absoluter Pfad zeigte auf den Origin-Root und damit ins Leere '
          '— und ein absoluter MIT Präfix („/MitFahrBar/…") wäre eine zweite '
          'Stelle, die mit `--base-href` in release.yml synchron bleiben '
          'müsste. Relativ löst der Browser gegen das <base href> auf, das '
          'Flutter beim Build ohnehin setzt.',
    );
    expect(
      webServiceWorkerPath,
      isNot(contains('..')),
      reason:
          'Der Scope des Workers muss die App enthalten, nicht darüber '
          'hinausreichen.',
    );
  });

  test('die Datei liegt dort, wo der Pfad sie erwartet', () {
    expect(
      File('web/$webServiceWorkerPath').existsSync(),
      isTrue,
      reason:
          'Der Worker wird aus web/ mit ausgeliefert. Wird er umbenannt oder '
          'verschoben, ohne diese Konstante nachzuziehen, scheitert getToken '
          'wieder still — sichtbar erst in der ausgelieferten PWA.',
    );
  });

  // Seit #232 ist es derselbe Worker, der die App-Shell vorhält: Es gibt je
  // Geltungsbereich genau EINEN, wer zuletzt registriert ersetzt den davor.
  // Registrierte das FCM-SDK hier eine eigene Datei, schaltete jeder
  // Token-Abruf den Offline-Start ab — und die Registrierung aus index.html
  // umgekehrt den Push. Deshalb zeigt der Pfad auf `sw.js`, und `sw.js` holt
  // sich die Firebase-Hälfte per importScripts dazu.
  test('Push und App-Shell teilen sich denselben Worker', () {
    expect(webServiceWorkerPath, 'sw.js');
    expect(
      File('web/sw.js').readAsStringSync(),
      contains("importScripts('firebase-messaging-sw.js')"),
      reason:
          'Ohne den Import wäre der registrierte Worker zwar da, aber ohne '
          'Firebase — die PWA bekäme kein Token und keine Meldung.',
    );
  });

  test('der Worker meldet sich bei Firebase an', () {
    // Bewusst die Firebase-Datei, nicht die registrierte: Dort steht die
    // SDK-Fassung, die `android_manifest_test.dart` gegen das Paket prüft.
    final worker = File('web/firebase-messaging-sw.js').readAsStringSync();
    expect(worker, contains('firebase.initializeApp'));
    expect(
      worker,
      contains('firebase.messaging()'),
      reason:
          'Ohne diesen Aufruf zeigt der Worker keine Hintergrund-Nachricht '
          'an. Ein eigener onBackgroundMessage-Handler gehört bewusst NICHT '
          'dazu — der erzeugte eine zweite Benachrichtigung.',
    );
  });
}

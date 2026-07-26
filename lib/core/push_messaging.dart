/// push_messaging.dart – Die Plattform-Seite der Benachrichtigungen (#101).
///
/// Alles, was hier drin steht, gibt es im Widget-Test nicht: kein FCM, keine
/// Berechtigungsdialoge, keinen Service Worker. Deshalb wird die einzige
/// Funktion daraus über `pushTokenProvider` gereicht — Tests ersetzen sie,
/// wie sie es beim Datei-Export und beim Teilen schon tun.
///
/// Jeder Fehlerpfad endet in `null` = kein Token = keine Registrierung. Das
/// ist dieselbe Linie wie beim Update-Check: Ein Nebenfeature darf die App
/// nie am Starten oder Bedienen hindern.
library;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'log.dart';
import 'push_config.dart';

/// Auf welchen Plattformen es Benachrichtigungen gibt — die beiden Werte,
/// die auch der CHECK-Constraint von `push_devices` erlaubt.
String? get pushPlatform {
  if (kIsWeb) return 'web';
  if (defaultTargetPlatform == TargetPlatform.android) return 'android';
  return null;
}

bool get pushSupported => pushPlatform != null && PushConfig.isConfigured;

/// Startet Firebase, falls die App Benachrichtigungen tragen kann.
///
/// Wird aus `main.dart` heraus aufgerufen und **schluckt jeden Fehler**: Ein
/// kaputtes Firebase-Projekt darf nicht dazu führen, dass die App gar nicht
/// erst hochkommt.
Future<void> initPushMessaging() async {
  if (!pushSupported) return;
  try {
    // Auf Android hat das Google-Services-Gradle-Plugin die Standard-App
    // längst nativ aus google-services.json gestartet, bevor Dart überhaupt
    // läuft. Ein zweiter Aufruf mit Optionen quittiert das mit
    // „[core/duplicate-app]". Der Fehler wäre folgenlos — aber er stünde bei
    // JEDEM Start im Log und verdeckte dort die echten. Auf einem Pixel
    // beobachtet, 26.07.2026.
    //
    // Im Web gibt es diesen Vorlauf nicht: Dort sind die Optionen Pflicht,
    // weil es keine google-services.json gibt.
    if (Firebase.apps.isNotEmpty) return;
    await Firebase.initializeApp(options: kIsWeb ? _webOptions : null);
  } catch (error) {
    // Ohne Token, aber lauffähig.
    log.w('Firebase nicht gestartet', error: error);
  }
}

const _webOptions = FirebaseOptions(
  apiKey: PushConfig.apiKey,
  appId: PushConfig.appId,
  messagingSenderId: PushConfig.messagingSenderId,
  projectId: PushConfig.projectId,
  authDomain: PushConfig.authDomain,
  storageBucket: PushConfig.storageBucket,
);

/// Das Token dieses Geräts — `null`, wenn es keines gibt.
///
/// [ask] entscheidet über den Berechtigungsdialog: Beim Öffnen des Screens
/// wird **nicht** gefragt (`ask: false`), sondern nur nachgesehen, ob schon
/// eines da ist. Gefragt wird erst beim Einschalten. Ein Dialog, den niemand
/// angefordert hat, wird weggetippt — und Android fragt danach nie wieder.
Future<String?> pushToken({required bool ask}) async {
  if (!pushSupported) return null;
  try {
    final messaging = FirebaseMessaging.instance;
    if (ask) {
      final settings = await messaging.requestPermission();
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.denied:
        case AuthorizationStatus.notDetermined:
          return null;
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          break;
      }
    }
    // Der VAPID-Schlüssel gilt nur im Web; auf Android liefert
    // google-services.json alles Nötige. Ohne erteilte Berechtigung wirft
    // der Aufruf im Web — genau dann liefert der catch unten `null`, und der
    // Screen zeigt sich schlicht als ausgeschaltet.
    // Mit Frist: `getToken` scheitert nicht immer, es bleibt auch mal
    // stehen — etwa wenn die Registrierung bei FCM nicht durchkommt. Ohne
    // die Frist hinge der Screen an einem Ladekreis, der nie endet.
    // TimeoutException landet unten im catch und wird zu „kein Token".
    return await messaging
        .getToken(vapidKey: kIsWeb ? PushConfig.vapidKey : null)
        .timeout(const Duration(seconds: 15));
  } catch (error) {
    // Absichtlich ohne das Token im Text: Was ins Log kommt, kann über eine
    // Rückmeldung in einem öffentlichen Issue landen.
    log.w('Push-Token nicht erhalten', error: error);
    return null;
  }
}

/// Wohin ein Tipp auf eine Benachrichtigung führt.
///
/// Immer der Planer — jede Nachricht dieses Features handelt von einem Tag
/// im Wochenplan. Ein eigener Deep-Link-Intent-Filter ist dafür nicht nötig:
/// FCM öffnet die MainActivity, den Rest macht der Router.
const pushTapRoute = '/plan';

/// Ruft [onTap], wenn die App über eine Benachrichtigung geöffnet wurde —
/// sowohl aus dem Hintergrund als auch aus dem kalten Start heraus.
Future<void> listenForPushTaps(void Function() onTap) async {
  if (!pushSupported) return;
  try {
    FirebaseMessaging.onMessageOpenedApp.listen((_) => onTap());
    if (await FirebaseMessaging.instance.getInitialMessage() != null) {
      onTap();
    }
  } catch (error) {
    log.w('Push-Tap nicht verdrahtet', error: error);
  }
}

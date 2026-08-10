/// web_notifications_web.dart – Die Wahrheit des Browsers, ungefiltert.
///
/// `Notification.permission` ist im Web die **einzige** verlässliche Quelle:
/// `granted`, `denied` oder `default` (noch nie gefragt). Bewusst nicht über
/// `firebase_messaging.getNotificationSettings()` — dieselbe Begründung wie
/// auf Android in `notification_health_probe.dart`: Zwei Wege zu derselben
/// Frage sind der Anfang der zweiten Wahrheit, und der eine davon ist
/// nachweislich unzuverlässig.
///
/// Kein `requestPermission` hier: Gefragt wird ausschließlich beim Einschalten
/// über `pushToken(ask: true)`. Ein ungefragter Dialog wird weggetippt, und
/// danach fragt der Browser nie wieder.
library;

import 'package:web/web.dart' as web;

String? webNotificationPermission() {
  try {
    return web.Notification.permission;
  } catch (_) {
    // Ältere Browser ohne die Notification-API. Unbekannt ist keine Blockade.
    return null;
  }
}

String webUserAgent() {
  try {
    return web.window.navigator.userAgent;
  } catch (_) {
    return '';
  }
}

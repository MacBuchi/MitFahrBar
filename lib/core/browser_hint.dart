/// browser_hint.dart – Wo man im Browser die Benachrichtigungen zurückholt.
///
/// **Warum das eine Textwüste und kein Knopf ist:** Es gibt keine Web-API, die
/// die Seiteneinstellungen eines Browsers öffnet. Ein Knopf könnte hier also
/// nur so tun — und ein Knopf, der nichts löst, ist ein Versprechen (dieselbe
/// Entscheidung wie bei „Nicht stören" auf totaler Stille in
/// `notification_health.dart`). Bleibt der Weg, den Menschen zu führen: Schritt
/// für Schritt, in seinem Browser.
///
/// Der Anlass: Ein einmal abgelehnter Berechtigungsdialog kommt im Browser
/// **nicht von selbst zurück**. Danach tut der Schalter im Screen sichtbar gar
/// nichts, und die einzige Erklärung war bis v0.78.0 eine SnackBar-Zeile.
///
/// Reine Auswertung, kein Flutter und kein `dart:html` — damit die Zuordnung
/// gegen echte User-Agent-Zeichenketten testbar bleibt
/// (`test/browser_hint_test.dart`).
library;

/// Die Browser, für die es einen eigenen Weg zu beschreiben gibt.
///
/// Chromium-Verwandte trennen sich hier bewusst auf: Edge, Opera und Chrome
/// tragen alle „Chrome" im User-Agent, führen aber zu verschiedenen Schirmen
/// mit verschiedenen Namen. Wer sie zusammenwirft, schickt Opera-Nutzer auf
/// ein Menü, das es dort nicht gibt.
enum BrowserKind { chrome, edge, opera, firefox, safari, other }

/// Erkennt den Browser an seinem User-Agent.
///
/// **Die Reihenfolge ist der ganze Inhalt dieser Funktion.** Edge meldet
/// `Edg/…`, Opera `OPR/…` — und beide führen zusätzlich `Chrome/…`, weil sie
/// Chromium sind. Zuerst auf Chrome zu prüfen ordnete also alle drei dem
/// Chrome-Text zu. Ebenso auf iOS: `CriOS`/`EdgiOS`/`FxiOS` sind Chrome, Edge
/// und Firefox in einer Safari-Hülle, und alle drei tragen „Safari" im Namen.
BrowserKind browserFromUserAgent(String userAgent) {
  final ua = userAgent.toLowerCase();
  // Edge vor Chrome: `edg/` (Desktop, Android), `edga/` (ältere Android-
  // Fassung), `edgios/` (iOS).
  if (ua.contains('edg/') || ua.contains('edga/') || ua.contains('edgios/')) {
    return BrowserKind.edge;
  }
  // Opera vor Chrome: `opr/` überall, `opera` nur noch in alten Fassungen.
  if (ua.contains('opr/') || ua.contains('opera')) return BrowserKind.opera;
  if (ua.contains('firefox/') || ua.contains('fxios/')) {
    return BrowserKind.firefox;
  }
  if (ua.contains('chrome/') || ua.contains('crios/')) {
    return BrowserKind.chrome;
  }
  // Erst ganz zuletzt: Jeder der oberen trägt „safari" mit.
  if (ua.contains('safari/')) return BrowserKind.safari;
  return BrowserKind.other;
}

/// Der Name, den der Mensch auf seinem Bildschirm liest.
String browserLabel(BrowserKind kind) => switch (kind) {
  BrowserKind.chrome => 'Chrome',
  BrowserKind.edge => 'Edge',
  BrowserKind.opera => 'Opera',
  BrowserKind.firefox => 'Firefox',
  BrowserKind.safari => 'Safari',
  BrowserKind.other => 'Dein Browser',
};

/// Der Weg zur Berechtigung, Schritt für Schritt.
///
/// Bewusst an der **Adressleiste** entlang und nicht über das Einstellungs-
/// menü: Das Symbol links neben der Adresse führt in jedem dieser Browser zu
/// den Rechten genau dieser Seite, und es ist zu sehen, während man die
/// Anleitung liest. Der Weg über die Einstellungen verlangt zusätzlich, die
/// eigene Adresse in einer Liste wiederzufinden.
///
/// [other] bekommt bewusst denselben Aufbau statt einer Entschuldigung: Die
/// Beschreibung „das Symbol links neben der Adresse" trifft auch auf die
/// Browser zu, die hier nicht namentlich stehen.
List<String> notificationStepsFor(BrowserKind kind) => switch (kind) {
  BrowserKind.chrome => const [
    'Tippe links neben der Adresse auf das Symbol (Schloss oder Schieberegler).',
    'Wähle „Berechtigungen" bzw. „Website-Einstellungen".',
    'Stelle „Benachrichtigungen" auf „Zulassen".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
  BrowserKind.edge => const [
    'Tippe links neben der Adresse auf das Symbol (Schloss oder Schieberegler).',
    'Wähle „Berechtigungen für diese Website".',
    'Stelle „Benachrichtigungen" auf „Zulassen".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
  BrowserKind.opera => const [
    'Tippe links neben der Adresse auf das Schloss-Symbol.',
    'Wähle „Website-Einstellungen".',
    'Stelle „Benachrichtigungen" auf „Zulassen".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
  BrowserKind.firefox => const [
    'Tippe links neben der Adresse auf das Schloss-Symbol.',
    'Wähle „Verbindung sicher" bzw. „Berechtigungen".',
    'Entferne die Sperre bei „Benachrichtigungen senden".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
  BrowserKind.safari => const [
    'Öffne die Einstellungen von Safari.',
    'Gehe zu „Websites" → „Benachrichtigungen".',
    'Stelle diese Seite auf „Erlauben".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
  BrowserKind.other => const [
    'Tippe links neben der Adresse auf das Symbol (Schloss oder Schieberegler).',
    'Suche die Berechtigungen oder Website-Einstellungen.',
    'Stelle „Benachrichtigungen" auf „Zulassen".',
    'Lade die Seite neu und schalte hier wieder ein.',
  ],
};

/// Der Satz gegen die stille Blockade.
///
/// Chrome und die Chromium-Verwandten unterdrücken den Berechtigungsdialog,
/// wenn jemand ihn oft weggetippt hat („leisere Benachrichtigungen"). Dann
/// meldet der Zustand weiterhin `default` — es erscheint aber **kein** Dialog,
/// sondern nur ein durchgestrichenes Glocken-Symbol in der Adressleiste. Das
/// ist mit Code nicht zu erkennen und deshalb ein Satz und kein Zweig.
const String quietBlockHint =
    'Erscheint beim Einschalten kein Dialog, hält der Browser ihn zurück: '
    'Dann steht in der Adressleiste ein durchgestrichenes Glocken-Symbol — '
    'darüber lässt es sich freigeben.';

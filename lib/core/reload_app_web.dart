/// reload_app_web.dart – Seite neu laden, damit die neue Version greift.
///
/// Seit #232 hält ein eigener Service Worker die App-Shell vor, und damit
/// genügt ein blankes `location.reload()` nicht mehr: Es holt genau die
/// Fassung zurück, die schon läuft. Eine neue liegt zu dem Zeitpunkt als
/// `waiting` daneben und übernimmt erst, wenn die PWA vollständig geschlossen
/// war — der Knopf täte also sichtbar nichts und sähe dabei aus, als hätte er
/// gewirkt. Das ist die Klasse „toter Update-Knopf" aus 0.37.0, diesmal im
/// Browser.
///
/// Deshalb erst fragen, ob es eine neue Fassung gibt, sie aktivieren lassen
/// und dann neu laden. **Jeder Zweig endet im Neuladen**, auch der, in dem
/// nichts wartet oder etwas hängt: Ein Knopf, der auf einen Service Worker
/// wartet, wäre wieder einer, der nichts tut.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Wie lange auf den Wechsel gewartet wird, bevor ohnehin neu geladen wird.
///
/// Kurz genug, dass niemand vor einem toten Knopf steht; lang genug für den
/// Wechsel selbst, der nur eine Nachricht und eine Aktivierung ist.
const _handover = Duration(seconds: 5);

void reloadApp() {
  unawaited(_reload());
}

Future<void> _reload() async {
  try {
    await _activateWaiting().timeout(_handover);
  } catch (_) {
    // Kein Netz, kein Worker, nichts wartet, oder es dauert zu lange — in
    // allen Fällen bleibt das Neuladen unten das Richtige.
  }
  web.window.location.reload();
}

Future<void> _activateWaiting() async {
  final container = web.window.navigator.serviceWorker;
  final registration = await container.getRegistration().toDart;
  if (registration == null) return;

  // Die neue Fassung kann noch gar nicht bekannt sein — der Knopf erscheint,
  // weil GitHub ein Release meldet, nicht weil der Browser schon nachgesehen
  // hat. Ohne diese Zeile wäre der erste Tipp regelmäßig einer zu früh.
  try {
    await registration.update().toDart;
  } catch (_) {
    // Ohne Netz sagt das nichts über die wartende Fassung aus.
  }

  final waiting = registration.waiting;
  if (waiting == null) return;

  // Erst auf den Wechsel horchen, dann anstoßen: Andersherum kann das
  // Ereignis dazwischenfallen, und dann wartet hier jemand auf etwas, das
  // schon passiert ist.
  final changed = Completer<void>();
  void listener(web.Event _) {
    if (!changed.isCompleted) changed.complete();
  }

  final callback = listener.toJS;
  container.addEventListener('controllerchange', callback);
  try {
    waiting.postMessage('skipWaiting'.toJS);
    await changed.future;
  } finally {
    container.removeEventListener('controllerchange', callback);
  }
}

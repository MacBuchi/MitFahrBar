// Eigene Bootstrap-Vorlage — sie existiert wegen genau einer weggelassenen
// Zeile (#232).
//
// Die Standardfassung, die `flutter build web` sonst selbst erzeugt, ruft
// `_flutter.loader.load({ serviceWorkerSettings: { … } })`. Das sieht nach
// „lade den Offline-Cache" aus und ist in 3.44 das Gegenteil: Der Loader
// registriert dann `flutter_service_worker.js`, und der ist ein
// Selbstzerstörer — 784 Bytes, kein Ressourcen-Manifest, im `activate` steht
// `self.registration.unregister()` samt Neuladen aller Clients. Er existiert
// nur noch, um Worker früherer Flutter-Versionen abzuräumen.
//
// Die Falle ist, dass er das nicht sofort tut: Ohne bestehende Registrierung
// hält der Loader still (`getRegistration().then(r => r ? register() : …)`).
// Beim ersten Besuch passiert also nichts, und alles sieht heil aus. Sobald
// `web/index.html` unseren eigenen Worker registriert hat, greift der
// Aufräumpfad — der Stummel legt sich als `waiting` daneben, aktiviert beim
// nächsten Start als Erstes und meldet alles ab. Der Offline-Start wäre damit
// jede zweite Sitzung tot, und im Browser sähe man davon nur eine leere
// Cache-Ablage.
//
// Ohne das Feld kehrt `loadServiceWorker` sofort zurück; registriert wird
// dann ausschließlich, was in `index.html` steht. `test/web_offline_test.dart`
// hält die Auslassung fest — sie ist eine Nicht-Zeile und deshalb genau die
// Art Änderung, die beim Aufräumen niemandem auffällt.
//
// `--pwa-strategy=none` täte dasselbe, ist aber selbst deprecated und müsste
// an JEDER Build-Stelle stehen; diese Datei gilt für alle zugleich.
{{flutter_js}}
{{flutter_build_config}}
_flutter.loader.load();

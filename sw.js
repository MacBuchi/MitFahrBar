// sw.js – Der Service Worker der PWA: hält die App-Shell vor und bringt den
// Push-Worker mit (#232).
//
// Warum es ihn gibt: Flutter Web hat seit 3.44 keinen eigenen Cache mehr —
// `flutter_service_worker.js` ist ein Aufräum-Stummel, der sich selbst
// abmeldet (flutter/flutter#156910). Ohne Ersatz liefert der Browser ohne
// Empfang nicht einmal die Seite aus; der Zwischenspeicher der App (Zeilen
// aus Supabase, `data/offline_cache.dart`) liegt dann hinter einer Tür, die
// sich gar nicht öffnet. Gemessen am 10.08.2026: Ablage leer, Neuladen ohne
// Netz endet in ERR_INTERNET_DISCONNECTED.
//
// **Der Worker cacht ausschließlich die App-Shell — nie eine Antwort von
// Supabase, GitHub oder gstatic.** Was offline gezeigt wird, entscheidet
// allein der Zwischenspeicher der App; ein zweiter Speicher im Worker wäre
// eine zweite Wahrheit über denselben Tag, mit eigener Verfallsregel und
// ohne die Leiste, die den Stand nennt. Fremde Anfragen laufen deshalb hier
// ohne `respondWith` durch — der Worker sieht sie und rührt sie nicht an.
//
// Es gibt je Geltungsbereich genau EINEN Worker: Wer zuletzt registriert,
// ersetzt den davor. Deshalb holt sich diese Datei die Firebase-Hälfte per
// `importScripts` dazu, statt neben ihr zu stehen — sonst schalteten sich
// Push und Offline-Start abwechselnd gegenseitig ab.

// Vom Injektor (`tool/inject_sw_manifest.py`) beim Bauen ersetzt. Im
// Quelltext bleibt die Liste leer: Ein Build ohne Injektion cacht damit
// nichts, statt eine halbe Shell vorzuhalten, die niemand geprüft hat.
const BUILD = "2a41d81380617717";
const MANIFEST = [{"url":".last_build_id","sha256":"f8541d097a5598ddd2c59cb9815dcb8e08197fec5f70f1011f32bc2ce86e34ab"},{"url":"assets/AssetManifest.bin","sha256":"dd1800be5f399dee18fbc4264f1b6c6e7c1635ea4709d64dd20a67351593fa48"},{"url":"assets/AssetManifest.bin.json","sha256":"6f942e4936269a873c1e7f353eb6cff72852776fc8b040441aefadfcf2b6a7ed"},{"url":"assets/FontManifest.json","sha256":"bb2194352e6f618900626693355872d3e8771ba4bb024a6a6372484403a428f8"},{"url":"assets/NOTICES","sha256":"bf94b79c87341fa119e451a766f98a48afe4f1cc529ed0a4a42a39d8a9a90984"},{"url":"assets/assets/fonts/Manrope-OFL.txt","sha256":"e01b637272e0cbdfb240184dd98ea5cc671556d9894dae2668d92ab2c906787c"},{"url":"assets/assets/fonts/Manrope.ttf","sha256":"d0639be45d0af36e798172419d7bd173c4bd4f29e2b76cbb69db1d11bf8b0a40"},{"url":"assets/assets/fonts/SpaceGrotesk-OFL.txt","sha256":"564ce565c371c5e5bbf286006565a7c9aa55a9f56e7ca58d56e05d649dd61a72"},{"url":"assets/assets/fonts/SpaceGrotesk.ttf","sha256":"acad6de1fc93436f5c0f1f4137751ef04f1aea3063e7036535970ffcfbd79f72"},{"url":"assets/fonts/MaterialIcons-Regular.otf","sha256":"a89331f0c5b53e9b507550a915593655f903880aa1a7c71e44fdf5446daa54a9"},{"url":"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf","sha256":"3d90c370aa4cf00dc57ee2b902f6652147c0f81e03e483df584a9c08b1687c9d"},{"url":"assets/packages/material_ui/shaders/ink_sparkle.frag","sha256":"2dca5ab93d4ec29e963f996f3916320ba60825e9537dfb149a68008c7a16b026"},{"url":"assets/shaders/ink_sparkle.frag","sha256":"2dca5ab93d4ec29e963f996f3916320ba60825e9537dfb149a68008c7a16b026"},{"url":"assets/shaders/stretch_effect.frag","sha256":"ab412f07a5b9b50b67a885b24dbe16929738ae28630407d6490c924caf0a3220"},{"url":"canvaskit/canvaskit.js","sha256":"7361b744487f98262f77ac507006b3eae37830430048ab7811a626b79f34a52c"},{"url":"canvaskit/canvaskit.wasm","sha256":"6bdfaa51c76845c02ea90153d44f56f99da51de44a7ee0ea15ccaeb33ed8f476"},{"url":"canvaskit/chromium/canvaskit.js","sha256":"d2aceb0e24ead163ab289a165ca0e26a36fa26d7118f5a295b8854d59d892896"},{"url":"canvaskit/chromium/canvaskit.wasm","sha256":"c2fc2864763540922c71d464e983bebf97b3a5312fd01c6a8988969747d13314"},{"url":"datenschutz.html","sha256":"f6b2cc4ac09e390a586a063effd6f707a8b14806813e5d1b150a2e70a8d7db80"},{"url":"favicon.png","sha256":"94520ccb8a810caaeb7e34aaa74a6af61590c05f015de6ec5e38c18aaecc174c"},{"url":"firebase-messaging-sw.js","sha256":"95ee18f0662cf28f74d060962078c0a2f34daef7816446e2f1f7d6588a8dc8bf"},{"url":"flutter.js","sha256":"a483fd28f51ed2fadd0da3fade5b672eba56310d549d736ce62eabf624a6a578"},{"url":"flutter_bootstrap.js","sha256":"b5472a53b3b329b3eb0fc78ae790eae72c165f41612d25064f4e405dad823332"},{"url":"icons/Icon-192.png","sha256":"f39340085669af6ededc32399f9a625918cff5d6fca570dd711473a35a3d4b1e"},{"url":"icons/Icon-512.png","sha256":"64f5bc7d31c8e33f7bb2f80b3aebde5eb673197568aec6b56bea6da1d9ad7523"},{"url":"icons/Icon-maskable-192.png","sha256":"6301b6c087ff29a319c11dd82990f516d4d51df34bbc659f451302932e0c51e2"},{"url":"icons/Icon-maskable-512.png","sha256":"1576a4efc1876704788ba4a3696f5ad905314b393252cac9d1c8ec019cb2aeec"},{"url":"index.html","sha256":"59bad72e8dc8a279f2f74547d6bc6b4a909ba71081c534f305ff8c9b8c982bb1"},{"url":"konto-loeschen.html","sha256":"ac8ac0832a20c37b55af78874f213977830707383b99f3e2ac024a23d88495f1"},{"url":"main.dart.js","sha256":"ca575b0b270ae2dd4800bbff7ec745af117a0ed5a4f6d2e59ad0de361efa729e"},{"url":"manifest.json","sha256":"349b6cb779766dba513993d72bd34a43f88d6092ca1bcb03419b4683c1d89229"},{"url":"version.json","sha256":"01c5b52c06f1ebc9f9fd86b606d42857cefb2874626639254e856d03acf7e167"}];

const CACHE_PREFIX = 'mitfahrbar-shell-';
const CACHE_NAME = CACHE_PREFIX + BUILD;

// Die Einträge stehen relativ zum Worker, damit dieselbe Datei unter `/`
// (Testaufbau) und unter `/MitFahrBar/` (GitHub Pages) stimmt — dieselbe
// Regel wie beim Push-Worker-Pfad in `core/push_messaging.dart`.
const SHELL = new Map(
  MANIFEST.map((entry) => {
    const url = new URL(entry.url, self.location);
    return [url.pathname, { url: url.href, sha256: entry.sha256 }];
  }),
);
const INDEX = new URL('index.html', self.location).pathname;

// Beim Installieren wird gegen den Hash geprüft, nicht bloß heruntergeladen.
// GitHub Pages liefert über einen Cache mit zehn Minuten Frist aus: Kurz
// nach einer Beförderung kann ein Abruf die neue `sw.js` und dazu eine alte
// `main.dart.js` von der Kante liefern. Ohne Prüfung stünde diese Mischung
// dauerhaft als „die neue Fassung" im Cache. `cache: 'reload'` hält den
// Browser-Cache heraus, der Hash die Kante.
async function fetchVerified(entry) {
  const response = await fetch(entry.url, {
    cache: 'reload',
    credentials: 'same-origin',
  });
  if (!response.ok) {
    throw new Error(`${entry.url}: HTTP ${response.status}`);
  }
  const body = await response.arrayBuffer();
  const digest = await crypto.subtle.digest('SHA-256', body);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
  if (hex !== entry.sha256) {
    throw new Error(`${entry.url}: Inhalt passt nicht zum Manifest`);
  }
  // NUR der Inhaltstyp wird übernommen, nicht der ganze Kopf. `arrayBuffer()`
  // liefert die **entpackten** Bytes, während `content-encoding` und
  // `content-length` noch die gepackte Antwort beschreiben — GitHub Pages
  // liefert komprimiert aus, ein lokaler `http.server` nicht. Mitgenommen
  // wären es zwei Angaben, die zum Rumpf nicht passen; der Fehler zeigte
  // sich also erst auf der Live-Adresse. Der Typ selbst muss bleiben:
  // `application/wasm` ist die Bedingung dafür, dass der Browser CanvasKit
  // im Strom übersetzt.
  const type = response.headers.get('content-type');
  return new Response(body, {
    status: 200,
    headers: type ? { 'Content-Type': type } : {},
  });
}

async function precache() {
  const cache = await caches.open(CACHE_NAME);
  const entries = Array.from(SHELL.values());
  // In Schüben statt alle auf einmal: Es sind rund 60 Dateien und ~18 MB,
  // und ein Browser bricht bei zu vielen offenen Verbindungen ab.
  const width = 6;
  for (let i = 0; i < entries.length; i += width) {
    const batch = entries.slice(i, i + width);
    const responses = await Promise.all(batch.map(fetchVerified));
    await Promise.all(
      batch.map((entry, n) => cache.put(entry.url, responses[n])),
    );
  }
}

self.addEventListener('install', (event) => {
  if (SHELL.size === 0) return;
  // Kein `skipWaiting()` hier: Eine neue Fassung übernimmt erst, wenn die
  // Gruppe „Neu laden" tippt (siehe `core/reload_app_web.dart`) oder die App
  // ohnehin geschlossen war. Sonst wechselte die Shell mitten im Betrieb
  // unter einem laufenden Dart-Programm.
  //
  // Scheitert auch nur eine Datei, scheitert die Installation ganz: Der
  // bisherige Worker liefert dann weiter einen in sich stimmigen Stand, und
  // der nächste Besuch versucht es erneut. Eine halb gefüllte Ablage wäre
  // schlimmer als keine.
  event.waitUntil(precache());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((name) => name.startsWith(CACHE_PREFIX) && name !== CACHE_NAME)
          .map((name) => caches.delete(name)),
      );
      // Übernimmt die schon offene Seite. Ohne das liefe der erste Besuch
      // komplett ohne Worker — und wer danach das Netz verliert, ohne die
      // Seite neu zu laden, hätte trotz gefüllter Ablage nichts davon.
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  if (SHELL.size === 0) return;
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Fremde Adressen (Supabase, GitHub-API, gstatic) NIE anfassen — siehe
  // Kopf. Ohne `respondWith` bleibt es der normale Netzweg der Seite, und
  // damit greifen auch die Werkzeuge, die den Netzausfall im Test
  // nachstellen: Ein `fetch` aus dem Worker heraus liefe an ihnen vorbei.
  if (url.origin !== self.location.origin) return;

  // Jeder Einstieg zeigt dieselbe Shell — auch ein Deep-Link, für den der
  // Server sonst 404.html ausliefert.
  //
  // ABER nicht, wenn unter dem Pfad eine echte Datei liegt: `datenschutz.html`
  // und `konto-loeschen.html` sind eigenständige Seiten, keine App-Routen.
  // Ohne die zweite Bedingung bekäme jeder, der die Web-App schon einmal
  // geöffnet hat, dort die App zu sehen. Beide Adressen sind Play-Pflicht und
  // werden von der Konsole geprüft; beim ersten Besuch — und damit bei
  // Googles Abruf — fällt es nicht auf, weil dann noch kein Worker läuft.
  if (request.mode === 'navigate' && !SHELL.has(url.pathname)) {
    event.respondWith(shellResponse(INDEX, request));
    return;
  }

  // Der Abgleich läuft über den Pfad, ohne Abfrageteil: `package_info_plus`
  // holt `version.json` mit einem Zwischenspeicher-Brecher (`?v=…`). Würde
  // der die Zuordnung verfehlen, meldete die App ohne Netz die Version
  // 0.0.0 — und „Über MitFahrBar" behauptete etwas anderes als die Shell,
  // die gerade läuft.
  if (!SHELL.has(url.pathname)) return;
  event.respondWith(shellResponse(url.pathname, request));
});

async function shellResponse(pathname, request) {
  const entry = SHELL.get(pathname);
  const cache = await caches.open(CACHE_NAME);
  const hit = entry && (await cache.match(entry.url));
  if (hit) return hit;
  // Totes Sicherheitsnetz: Steht die Datei im Manifest, liegt sie nach einer
  // erfolgreichen Installation auch im Cache. Ohne Netz scheitert das hier
  // ehrlich, statt eine leere Antwort zu erfinden.
  return fetch(request);
}

self.addEventListener('message', (event) => {
  // Der Gegenpart zum Knopf „Neu laden": Erst diese Nachricht macht die
  // wartende Fassung zur laufenden. Ohne sie bliebe sie warten, bis die PWA
  // vollständig geschlossen wird — und der Knopf lieferte die alte Shell
  // zurück, ohne dass man ihm etwas ansieht.
  if (event.data === 'skipWaiting') self.skipWaiting();
});

// Zum Schluss und in try/catch: Der Import zieht die Firebase-Fassungen von
// gstatic nach. Scheitert das (etwa beim allerersten Besuch mit blockiertem
// Fremd-Origin), soll die App-Shell trotzdem stehen — sonst kostete eine
// Störung bei Firebase auch noch den Offline-Start. Der Push fehlt dann so,
// wie er vorher auch gefehlt hätte.
try {
  importScripts('firebase-messaging-sw.js');
} catch (error) {
  // Kein console.error mit Inhalt: Was hier steht, landet in fremden
  // Konsolen. Die Ursache steht ohnehin in der Netzwerk-Ansicht.
  console.warn('Push-Teil des Workers nicht geladen');
}

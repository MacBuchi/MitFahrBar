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
const BUILD = 'dev';
const MANIFEST = [];

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

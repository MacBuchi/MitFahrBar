// offline.mjs – Browser-E2E: Startverhalten MIT und OHNE Netz (#169, #232).
//
// Die Lücke, die dieser Flow schließt: Der Zwischenspeicher ist in Flow-Tests
// dicht abgedeckt — aber dort wird das „Netz" an der Repository-Naht
// abgeschaltet, mit einer geworfenen Exception. Nie am Socket. Damit läuft
// genau das nicht mit, worauf sich die Meldungen bezogen:
//
//  * die ECHTE Ablage (`PrefsOfflineCache` im localStorage des Browsers),
//  * der ECHTE Fehler des Supabase-Clients (die Flow-Tests prüfen
//    `looksOffline` gegen einen selbst gebauten String),
//  * und die Frage, ob die PWA ohne Netz überhaupt **lädt** — die hängt am
//    Service Worker und nicht am Zwischenspeicher. Fällt der aus, nützt der
//    ganze Umbau aus v0.79.0 im Browser nichts, und heute merkt das niemand.
//
// Der Ablauf ist der echte: einmal mit Empfang öffnen und anmelden, dann das
// Netz wegnehmen und **neu laden** — der Fall aus #232.
//
// Flutter-Web zeichnet auf Canvas. Textfelder brauchen deshalb KOORDINATEN
// (Viewport fest, Werte aus den Screenshots in shots/), geprüft wird über
// Semantics-Labels. Beides wie in console.mjs.

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const APP_URL = process.env.APP_URL ?? 'http://localhost:8731/';
const SUPABASE_URL = required('E2E_SUPABASE_URL');
const SERVICE_KEY = required('E2E_SUPABASE_SERVICE_KEY');

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`FEHLER: ${name} fehlt (tool/browser_e2e.sh nutzen).`);
    process.exit(2);
  }
  return value;
}

const runTag = Date.now().toString(36);
const handle = `off${runTag}`;
const groupPassword = 'browser-e2e-offline-1';
// Die Login-Adresse jeder Gruppe — steht serverseitig so in auth.users und
// wird in core/group_login.dart genauso gebildet.
const groupEmail = `${handle}@grp.fahrgemeinschaft.app`;

mkdirSync(new URL('./shots/', import.meta.url), { recursive: true });
const shot = (name) => new URL(`./shots/${name}.png`, import.meta.url).pathname;

const rest = (path, init = {}) =>
  fetch(`${SUPABASE_URL}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${SERVICE_KEY}`,
      apikey: SERVICE_KEY,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });

// ---------------------------------------------------------------- Seeding

/// Legt die Gruppe per Admin-API an: Der Trigger `handle_new_group()` macht
/// daraus die Zeile in `groups` (Status `pending`) samt Vorgabe-Parametern.
/// Aktiv geschaltet wird sie mit dem Service-Key — im Betrieb macht das die
/// Konsole, und der Weg dorthin ist in admin_console_e2e_test.dart und
/// console.mjs abgedeckt. Hier geht es um etwas anderes.
async function seedGroup() {
  const created = await rest('/auth/v1/admin/users', {
    method: 'POST',
    body: JSON.stringify({
      email: groupEmail,
      password: groupPassword,
      email_confirm: true,
    }),
  });
  if (!created.ok) {
    throw new Error(`Gruppen-Konto nicht angelegt: ${await created.text()}`);
  }
  const { id } = await created.json();

  const activated = await rest(`/rest/v1/groups?id=eq.${id}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ status: 'active' }),
  });
  if (!activated.ok) {
    throw new Error(`Gruppe nicht aktiviert: ${await activated.text()}`);
  }

  // Eine Person genügt: Sie steht in „Wer ist dran?" und ist damit der
  // Beweis, dass wirklich Zeilen aus dem Speicher kommen — der Rahmen
  // allein stünde auch ohne sie.
  const person = await rest('/rest/v1/persons', {
    method: 'POST',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({ group_id: id, name: 'Anna', active: true }),
  });
  if (!person.ok) {
    throw new Error(`Person nicht angelegt: ${await person.text()}`);
  }
  return id;
}

// ---------------------------------------------------------------- Browser

const browser = await chromium.launch();
const context = await browser.newContext({
  viewport: { width: 1100, height: 1200 },
});
const page = await context.newPage();
page.on('pageerror', (e) => console.log('!! JS-Fehler:', e.message));

/// Flutter baut den a11y-Baum erst auf Anforderung — nur dispatchEvent über
/// den Locator löst den Platzhalter aus (siehe run-web-Skill).
///
/// **Kurze Frist, und die ist nicht kosmetisch:** Nach der ersten Aktivierung
/// ist der Platzhalter aus dem DOM verschwunden, der Aufruf läuft also
/// zwangsläufig in seine Frist. Mit den ursprünglichen 15 Sekunden kostete
/// jeder Versuch der Warteschleife darunter 16,5 s — ein Fehlschlag brauchte
/// zwölf Minuten statt einer halben.
async function activateSemantics(timeout = 1000) {
  await page
    .locator('flt-semantics-placeholder')
    .dispatchEvent('click', { timeout })
    .catch(() => {});
  await page.waitForTimeout(500);
}

async function labels() {
  const result = [];
  for (const node of await page.locator('flt-semantics[aria-label]').all()) {
    const label = (await node.getAttribute('aria-label')) ?? '';
    if (label.trim()) result.push(label);
  }
  return result;
}

async function expectLabel(re, hint) {
  for (let attempt = 0; attempt < 24; attempt++) {
    if ((await labels()).some((l) => re.test(l))) return;
    // **Bei jedem Versuch neu anfordern.** Der erste Lauf dieses Flows
    // (10.08.2026) fand exakt die Labels, die im Moment der Aktivierung
    // schon standen — Navigationsleiste und das Anmerkungs-Banner —, aber
    // keine einzige Ranking-Zeile: Die entsteht Sekundenbruchteile später,
    // wenn Personen und Statistik geladen sind. Flutter-Web trägt diesen
    // Nachschub nicht von allein in den a11y-Baum nach; ein Poller, der nur
    // die DOM-Knoten abfragt, sieht ihn also nie. Ohne diese Zeile prüft der
    // ganze Flow bloß, was vor dem ersten Frame fertig war.
    await activateSemantics();
  }
  console.log('--- LABELS ---');
  for (const l of await labels()) console.log(l.replace(/\n/g, ' | '));
  throw new Error(`Erwartetes Label fehlt: ${re} (${hint})`);
}

async function expectNoLabel(re, hint) {
  // Erst auffrischen: „steht nicht da" hieße sonst nur „stand beim letzten
  // Aufbau noch nicht da", und die Prüfung wäre wertlos.
  await activateSemantics();
  if ((await labels()).some((l) => re.test(l))) {
    throw new Error(`Label darf hier nicht stehen: ${re} (${hint})`);
  }
}

async function clickAt(x, y) {
  await page.mouse.click(x, y);
  await page.waitForTimeout(600);
}
async function typeAt(x, y, text) {
  await clickAt(x, y);
  await page.keyboard.type(text, { delay: 15 });
  await page.waitForTimeout(300);
}

let step = 0;
async function checkpoint(name) {
  step += 1;
  await page.screenshot({
    path: shot(`${String(step).padStart(2, '0')}-offline-${name}`),
  });
  // Das Inventar bei JEDEM Schritt, nicht erst im Fehlerfall. Beim ersten
  // Lauf (10.08.2026) stand am Ende nur „Label fehlt: /Anna/" — und die
  // Frage, WAS statt dessen im Baum steht, war aus dem Log nicht zu
  // beantworten. Der Baum von Flutter-Web ist ausdrücklich lückenhaft
  // (siehe console.mjs); wer darauf prüft, muss ihn mitschreiben.
  console.log(`✓ ${name} — Labels: ${JSON.stringify(await labels())}`);
}

/// Zustand des Service Workers — die Vorbedingung dafür, dass ohne Netz
/// überhaupt eine Seite ausgeliefert wird. Rein diagnostisch, aber im
/// Fehlerfall die erste Frage.
///
/// **Mit Skript-Adresse und Geltungsbereich**, und das ist der Kern: Am
/// 10.08.2026 meldete dieser Aufruf `registrations: 1, active: activated`
/// bei **leerem** Cache. Genau so sieht es aus, wenn nicht der App-Worker
/// von Flutter läuft, sondern ein anderer — es gibt je Geltungsbereich nur
/// EINEN, und wer sich zuletzt registriert, verdrängt den davor. In Frage
/// kommt `firebase-messaging-sw.js` (das FCM-SDK registriert ihn beim
/// Token-Holen, siehe `webServiceWorkerPath`); der cacht nichts. Ohne die
/// Adresse im Log ist „aktiv, aber leer" nicht auflösbar.
async function serviceWorkerState() {
  return page.evaluate(async () => {
    if (!('serviceWorker' in navigator)) return { supported: false };
    const registrations = await navigator.serviceWorker.getRegistrations();
    const keys = await caches.keys();
    const cached = {};
    for (const key of keys) {
      cached[key] = (await (await caches.open(key)).keys()).length;
    }
    return {
      supported: true,
      workers: registrations.map((r) => ({
        scope: r.scope,
        script:
          (r.active ?? r.installing ?? r.waiting)?.scriptURL ?? null,
        state: (r.active ?? r.installing ?? r.waiting)?.state ?? null,
      })),
      cached,
    };
  });
}

/// Woran zu erkennen ist, dass die Übersicht wirklich Zeilen zeigt.
const _hasContent = /Wunsch oder Fehler melden|Wer ist dran|Anna/;

try {
  const groupId = await seedGroup();
  console.log(`✓ Gruppe ${handle} angelegt und aktiv`);

  // 1. Mit Empfang öffnen und anmelden. Koordinaten bei Viewport 1100×1200,
  //    Karte zentriert: Anmeldename (550,642) · Passwort (550,706) · Knopf
  //    „Anmelden" (550,770). Abgelesen an einem Screenshot des echten Builds
  //    — beim Anpassen shots/ ansehen, statt zu rechnen.
  await page.goto(APP_URL, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  await clickAt(550, 300); // Splash: ein Tipp überspringt
  await activateSemantics();
  await checkpoint('login');

  await typeAt(550, 642, handle);
  await typeAt(550, 706, groupPassword);
  await clickAt(550, 770);
  await page.waitForTimeout(5000);
  await activateSemantics();

  // Die Startabfrage „Wer bist du?" (#121) liegt modal über der Übersicht.
  // Sie ist hier nicht das Thema — „Später" zählt als beantwortet.
  const later = page.locator('flt-semantics[aria-label="Später"]');
  if (await later.count()) {
    await later.first().click().catch(() => {});
    await page.waitForTimeout(1500);
  }
  await checkpoint('angemeldet');

  // **Der Anker ist eine Auswahl, und das ist der ehrliche Umgang mit einem
  // lückenhaften Baum.** Alle drei Zeichen stehen ausschließlich in
  // `_Content` (dashboard_screen.dart), und den baut die Übersicht nur bei
  // **nicht leerer** Rangliste — Personen, Statistik und Parameter sind
  // dann geladen. Genau das ist die Aussage; welches der drei den Beweis
  // liefert, ist gleichgültig.
  //
  // Warum nicht eines: Der a11y-Baum von Flutter-Web trägt sie nicht
  // zuverlässig. Gemessen am 10.08.2026 auf demselben Schirm — mit
  // Firebase im Bau stand dort das Banner, aber KEIN Personenname; ohne
  // Firebase der Personenname, aber kein Banner. Wer sich auf eines
  // festlegt, prüft die Lücke statt den Inhalt.
  await expectLabel(_hasContent, 'Inhalt der Übersicht');
  await expectNoLabel(
    /Offline · Stand/,
    'mit Empfang darf die Leiste nicht stehen',
  );
  console.log('✓ Start MIT Netz: Inhalt da, keine Offline-Leiste');

  // 2. Und jetzt der gemeldete Fall: Netz weg, App neu starten.
  const before = await serviceWorkerState();
  console.log('Service Worker vor dem Neuladen:', JSON.stringify(before));
  await context.setOffline(true);

  const reload = await page
    .reload({ waitUntil: 'domcontentloaded' })
    .then(() => 'ok')
    .catch((e) => e.message.split('\n')[0]);
  if (reload !== 'ok') {
    throw new Error(
      `Der Start ohne Netz kam nicht einmal bis zur Seite: ${reload}\n` +
        `Service Worker: ${JSON.stringify(before)}\n` +
        'Ohne einen Worker, der die App-Shell vorhält, startet die PWA ohne ' +
        'Empfang gar nicht — der Zwischenspeicher (#169) liegt dann hinter ' +
        'einer Tür, die sich nicht öffnet. Steht oben eine leere ' +
        'Worker-Liste oder allein `firebase-messaging-sw.js` bei leerer ' +
        'Cache-Ablage, ist es der am 10.08.2026 gemessene Zustand: Flutters ' +
        'App-Worker registriert sich in 3.44 gar nicht, sein ' +
        'Bootstrap-Ladeweg führt sich selbst als deprecated. Das ist eine ' +
        'Frage an den Web-Build, nicht an die Datenschicht.',
    );
  }

  await page.waitForTimeout(8000);
  await activateSemantics();
  await checkpoint('ohne-netz');

  // Der Kern von #169: Es steht etwas da, und zwar aus dem Speicher. Ohne
  // Netz kann `_Content` nur entstehen, wenn Personen, Statistik und
  // Parameter von der Platte kommen — genau das ist die Aussage.
  await expectLabel(
    _hasContent,
    'Übersicht ohne Netz aus dem Zwischenspeicher',
  );
  await expectNoLabel(
    /Keine Verbindung/,
    'der Gate-Schirm gehört hier nicht hin',
  );

  // Und der Kern von #169 zum Zweiten: Der Stand wird benannt, nicht als
  // aktuell ausgegeben. Die Leiste kommt bewusst mit zwei Sekunden Verzug
  // (v0.79.0) — deshalb erst hier gefragt.
  await expectLabel(/Offline · Stand/, 'die Leiste nennt den Zeitpunkt');
  console.log('✓ Start OHNE Netz: letzter Stand + Leiste');

  // 3. Zurück ins Netz: Die Leiste geht von allein weg.
  await context.setOffline(false);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  await activateSemantics();
  await checkpoint('wieder-online');
  await expectLabel(_hasContent, 'Übersicht wieder mit Netz');
  await expectNoLabel(/Offline · Stand/, 'mit Empfang gehört die Leiste weg');
  console.log('✓ Zurück im Netz: Leiste weg');

  // 4. Serverseitige Gegenprobe: Der ganze Lauf hat nichts geschrieben —
  //    ohne Netz eintragen geht nicht, und das soll auch so bleiben.
  const check = await rest(
    `/rest/v1/trips?select=id&group_id=eq.${groupId}`,
  );
  const trips = await check.json();
  if (!Array.isArray(trips) || trips.length !== 0) {
    throw new Error(
      `Es sind Fahrten entstanden (${JSON.stringify(trips).slice(0, 120)}) — ` +
        'der Zwischenspeicher ist ein Gedächtnis für Gelesenes, keine ' +
        'Warteschlange für Ungesendetes.',
    );
  }

  console.log('Browser-E2E (Offline): alle Schritte bestanden.');
  await browser.close();
} catch (error) {
  await page.screenshot({ path: shot('99-offline-fehler') }).catch(() => {});
  console.error('Browser-E2E (Offline) fehlgeschlagen:', error.message);
  console.error('Screenshots: tool/browser_e2e/shots/');
  await browser.close();
  process.exit(1);
}

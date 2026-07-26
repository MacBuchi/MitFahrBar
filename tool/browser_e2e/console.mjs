// console.mjs – Browser-E2E der Verwalter-Konsole (Issue #71, #106).
//
// Fährt die ECHTE Web-App im echten Browser gegen den lokalen Supabase-
// Stack — den Weg, den eine Gründerin wirklich geht: Verwalter-Konto
// registrieren → Code aus der Mail (Mailpit) in die App tippen (verifyOTP
// meldet gleich an) → **Gruppe anlegen** → Gruppe erscheint verwaltet in der
// Liste. Das ist die letzte Naht, die Widget-Tests (Fakes) und Dart-E2E
// (Backend) nicht abdecken: Hier läuft echtes Flutter-Web gegen die echte
// Edge Function, mit dem JWT aus einer echten Browser-Sitzung.
//
// Das Übernehmen einer bestehenden Gruppe (claim) deckt die Dart-E2E ab
// (admin_console_e2e_test.dart) — es bräuchte hier eine per Service-Key
// vorbereitete Waisen-Gruppe, und seit #106 ist das Anlegen der Weg, den
// jeder neue Verwalter zuerst nimmt.
//
// Der Code statt des Bestätigungs-Links seit Issue #102: Der Link ist an
// das Gerät gebunden, das ihn angefordert hat (PKCE-Verifier im lokalen
// Speicher). Die Vorlagen unter supabase/templates/ führen deshalb nur
// {{ .Token }} — mailCode() wacht darüber, dass das so bleibt.
//
// Flutter-Web zeichnet auf Canvas. Buttons und Felder fehlen teils im
// Semantics-Baum, deshalb läuft die Bedienung über KOORDINATEN (Viewport
// ist fixiert; die Werte stammen aus den Screenshots in shots/ und sind
// unten dokumentiert). Geprüft wird über Semantics-Labels, wo vorhanden,
// sonst über die Screenshots — bei Fehlschlag zuerst shots/ ansehen!

import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';

const APP_URL = process.env.APP_URL ?? 'http://localhost:8731/';
const SUPABASE_URL = required('E2E_SUPABASE_URL');
const SERVICE_KEY = required('E2E_SUPABASE_SERVICE_KEY');
const MAILPIT_URL = required('E2E_MAILPIT_URL');

function required(name) {
  const value = process.env[name];
  if (!value) {
    console.error(`FEHLER: ${name} fehlt (tool/browser_e2e.sh nutzen).`);
    process.exit(2);
  }
  return value;
}

const runTag = Date.now().toString(36);
const groupHandle = `be2e${runTag}`;
const groupPassword = 'browser-e2e-gruppe-1';
const adminEmail = `be2e-admin-${runTag}@browser-e2e.test`;
const adminPassword = 'browser-e2e-admin-1';

// Y-Koordinaten der Anlage-Karte bei **leerer** Gruppenliste (Viewport
// 1100×1200, Karte maxWidth 480, x immer 550). Abgelesen an
// shots/06-anlage-ausgefuellt.png vom 26.07.2026 — nicht geschätzt: Jedes
// zusätzliche Feld, jeder geänderte Hilfetext und jede Gruppe in der Liste
// darüber verschiebt alles nach unten. Beim Anpassen `tool/browser_e2e.sh`
// laufen lassen und die Bilder ansehen, statt zu rechnen.
const CREATE_NAME = 333;
const CREATE_HANDLE = 417;
const CREATE_PW = 501;
const CREATE_REPEAT = 565;
const CREATE_BUTTON = 622;

mkdirSync(new URL('./shots/', import.meta.url), { recursive: true });
const shot = (name) => new URL(`./shots/${name}.png`, import.meta.url).pathname;

// ---------------------------------------------------------------- Backend

/// Sechsstelliger Code aus der ersten Mailpit-Mail an [to] mit [subjectPart]
/// im Betreff — zugleich der Wächter über die Mail-Vorlage: Ein Link darin
/// hieße, {{ .ConfirmationURL }} steht noch drin und der gerätegebundene
/// (kaputte) Weg ist wieder erreichbar.
async function mailCode(to, subjectPart) {
  const query = encodeURIComponent(`to:"${to}" subject:"${subjectPart}"`);
  for (let i = 0; i < 40; i++) {
    const res = await fetch(`${MAILPIT_URL}/api/v1/search?query=${query}`);
    const { messages } = await res.json();
    if (messages?.length) {
      const detail = await fetch(
        `${MAILPIT_URL}/api/v1/message/${messages[0].ID}`,
      );
      const body = await detail.json();
      const text = `${body.Text}\n${body.HTML}`;
      if (text.includes('auth/v1/verify')) {
        throw new Error(
          'Die Mail enthält einen Link — die Vorlage darf nur den Code ' +
            'zeigen (supabase/templates/, Issue #102)',
        );
      }
      const match = text.match(/\b\d{6}\b/);
      if (match) return match[0];
      throw new Error(
        `Kein sechsstelliger Code in der Mail an ${to} — zeigt die Vorlage ` +
          '{{ .Token }}?',
      );
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Keine Mail an ${to} (subject: ${subjectPart})`);
}

// ---------------------------------------------------------------- Browser

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1100, height: 1200 } });
page.on('pageerror', (e) => console.log('!! JS-Fehler:', e.message));

/// Flutter baut den a11y-Baum erst auf Anforderung — nur dispatchEvent
/// über den Locator löst den Platzhalter aus (siehe run-web-Skill).
async function activateSemantics() {
  await page
    .locator('flt-semantics-placeholder')
    .dispatchEvent('click', { timeout: 15000 })
    .catch(() => {});
  await page.waitForTimeout(1500);
}

async function labels() {
  const nodes = await page.locator('flt-semantics[aria-label]').all();
  const result = [];
  for (const n of nodes) {
    const l = (await n.getAttribute('aria-label')) ?? '';
    if (l.trim()) result.push(l);
  }
  return result;
}

/// Wartet, bis ein Semantics-Label [re] matcht — die Assertionsseite.
async function expectLabel(re, hint) {
  for (let attempt = 0; attempt < 24; attempt++) {
    if ((await labels()).some((l) => re.test(l))) return;
    await page.waitForTimeout(500);
  }
  console.log('--- LABELS ---');
  for (const l of await labels()) console.log(l.replace(/\n/g, ' | '));
  throw new Error(`Erwartetes Label fehlt: ${re} (${hint})`);
}

/// Feld/Knopf an fester Position anklicken; für Felder danach tippen.
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
    path: shot(`${String(step).padStart(2, '0')}-${name}`),
  });
  console.log(`✓ ${name}`);
}

try {
  // 1. App laden, Semantics aktivieren, Splash wegtippen, dann per
  //    Router-URL direkt zum Konsolen-Login.
  await page.goto(APP_URL, { waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);
  await activateSemantics();
  await page.mouse.click(550, 300); // Splash: Tipp überspringt (leere Fläche)
  await page.waitForTimeout(1200);
  await page.goto(`${APP_URL}#/console/login`, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
  await checkpoint('konsole-login');

  // 2. Registrieren. Koordinaten (Viewport 1100×1200, Karte zentriert
  //    maxWidth 400). ACHTUNG: Der Registrieren-Modus hat ein drittes Feld,
  //    das ganze Formular rutscht dadurch nach oben — die Werte stammen aus
  //    shots/02 im Registrieren-Zustand: E-Mail (550,618) · Passwort
  //    (550,682) · Wiederholen (550,746) · Knopf (550,810). Der Segmented-
  //    Umschalter liegt davor noch im Anmelden-Layout bei (638,594).
  await clickAt(638, 594);
  await typeAt(550, 618, adminEmail);
  await typeAt(550, 682, adminPassword);
  await typeAt(550, 746, adminPassword);
  await checkpoint('register-ausgefuellt');
  await clickAt(550, 810);
  await page.waitForTimeout(1500);
  await checkpoint('registriert');

  // 3. Code aus der Mail eintippen. Nach dem Registrieren steht der Screen
  //    im Bestätigen-Modus: nur E-Mail (vorbelegt) und Code-Feld. verifyOTP
  //    liefert die Sitzung gleich mit, der Router leitet in die Konsole —
  //    ohne zweite Anmeldung und ohne Umweg über den Browser.
  //    Koordinaten aus shots/04 im Bestätigen-Zustand: Code (550,644) ·
  //    Knopf „Adresse bestätigen" (550,760).
  const code = await mailCode(adminEmail, 'Adresse');
  await typeAt(550, 644, code);
  await checkpoint('code-eingetragen');
  await clickAt(550, 760);
  await page.waitForTimeout(6000);
  await activateSemantics();
  await checkpoint('konsole-nach-code');
  await expectLabel(/Neue Gruppe anlegen/, 'Konsole nach Code-Bestätigung');

  // 4. Gruppe anlegen. Vier Felder — das Gruppenpasswort wird doppelt
  //    abgefragt (#107). Koordinaten aus shots/05 (leere Liste, Anlege-Karte
  //    oben): Name (550,CREATE_NAME) · Anmeldename (550,CREATE_HANDLE) ·
  //    Gruppenpasswort (550,CREATE_PW) · Wiederholen (550,CREATE_REPEAT) ·
  //    Knopf „Gruppe anlegen" (550,CREATE_BUTTON).
  await typeAt(550, CREATE_NAME, 'Browser-E2E-Gruppe');
  await typeAt(550, CREATE_HANDLE, groupHandle);
  await typeAt(550, CREATE_PW, groupPassword);
  await typeAt(550, CREATE_REPEAT, groupPassword);
  await checkpoint('anlage-ausgefuellt');
  await clickAt(550, CREATE_BUTTON);
  await page.waitForTimeout(3000);
  await activateSemantics();
  // Anker ist das ListTile der Gruppenkarte, nicht ein Knopf: Flutter-Web
  // exponiert die Knöpfe der Karte NICHT im Semantics-Baum (nachgesehen am
  // 26.07.2026 — im Baum stehen nur die ListTile- und Kartentexte). Dafür
  // nennt dieses Label die konkrete Gruppe und ist damit der genauere Beweis.
  await expectLabel(
    new RegExp(`Verwaltet: ${groupHandle}`),
    'Gruppenkarte nach dem Anlegen',
  );
  await checkpoint('angelegt');

  // 5. Serverseitige Gegenprobe: Die Gruppe ist aktiv UND verknüpft — beides
  //    gehört zusammen, sonst gehörte sie niemandem.
  const check = await fetch(
    `${SUPABASE_URL}/rest/v1/groups?select=status,handle,` +
      `group_admins!inner(user_id)&handle=eq.${groupHandle}`,
    { headers: { Authorization: `Bearer ${SERVICE_KEY}`, apikey: SERVICE_KEY } },
  );
  const rows = await check.json();
  if (!Array.isArray(rows) || rows.length !== 1) {
    throw new Error(
      `Gruppe fehlt oder ist unverknüpft (${JSON.stringify(rows).slice(0, 200)})`,
    );
  }
  if (rows[0].status !== 'active') {
    throw new Error(`Gruppe ist ${rows[0].status}, erwartet: active`);
  }
  console.log('✓ Gruppe ist aktiv und verknüpft');

  console.log('Browser-E2E: alle Schritte bestanden.');
  await browser.close();
} catch (error) {
  await page.screenshot({ path: shot('99-fehler') }).catch(() => {});
  console.error('Browser-E2E fehlgeschlagen:', error.message);
  console.error('Screenshots: tool/browser_e2e/shots/');
  await browser.close();
  process.exit(1);
}

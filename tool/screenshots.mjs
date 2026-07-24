// screenshots.mjs – erzeugt die README-Screenshots aus dem laufenden Demo-Build.
//
// Nicht direkt aufrufen, sondern über `tool/screenshots.sh` — das baut die App
// im Demo-Modus, liefert sie aus und räumt hinterher auf.
//
// Flutter-Web zeichnet auf Canvas: Es gibt keinen DOM-Text und nur einen
// lückenhaften Semantics-Baum. Die Navigation läuft deshalb über
// aria-labels (die gibt es), alles andere über Koordinaten im 430×900-
// Viewport. Ändert sich das Layout, stimmen die Koordinaten nicht mehr —
// dann fällt es im PR sofort auf, weil die Bilder falsch aussehen.
import { chromium } from 'playwright';

const BASE = process.env.SCREENSHOT_URL ?? 'http://localhost:8731/';
const OUT = process.env.SCREENSHOT_OUT ?? 'doc/screenshots';

const VIEWPORT = { width: 430, height: 900 };

const browser = await chromium.launch();

async function open() {
  const page = await browser.newPage({ viewport: VIEWPORT, deviceScaleFactor: 2 });
  page.on('pageerror', (e) => {
    console.error('JS-Fehler in der App:', e.message);
    process.exitCode = 1;
  });
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.waitForTimeout(4000);
  // Flutter baut den a11y-Baum erst auf Anforderung — nur dispatchEvent
  // löst das aus, .click() und ein selbstgebautes MouseEvent nicht.
  await page.locator('flt-semantics-placeholder').dispatchEvent('click');
  await page.waitForTimeout(2000);
  // Der Feedback-Hinweis oben würde jeden Screenshot um ein Banner
  // verschieben — wegklicken, bevor irgendetwas vermessen wird.
  await page.mouse.click(381, 88);
  await page.waitForTimeout(1200);
  return page;
}

async function tap(page, label) {
  for (const node of await page.locator('flt-semantics[aria-label]').all()) {
    if ((await node.getAttribute('aria-label')) === label) {
      await node.dispatchEvent('click');
      return true;
    }
  }
  throw new Error(`Kein Element mit aria-label "${label}" gefunden.`);
}

async function clicks(page, points, pause = 300) {
  for (const [x, y] of points) {
    await page.mouse.click(x, y);
    await page.waitForTimeout(pause);
  }
}

async function shot(page, name) {
  await page.screenshot({ path: `${OUT}/${name}.png` });
  console.log(`${OUT}/${name}.png`);
}

// 1 · Übersicht: „Wer ist dran?" mit Kennzahlen und Monatschart.
{
  const page = await open();
  await shot(page, 'uebersicht');
  await page.close();
}

// 2 · Wochenplan mit echtem Vorschlag — dafür erst Verfügbarkeiten setzen
//     (Mo–Mi für alle vier Personen; Raster-Spalten x, Zeilen y).
{
  const page = await open();
  await tap(page, 'Woche');
  await page.waitForTimeout(2500);
  const grid = [];
  for (const x of [191, 238, 286]) for (const y of [226, 262, 298, 334]) grid.push([x, y]);
  await clicks(page, grid, 250);
  await page.waitForTimeout(2000);
  await shot(page, 'wochenplan');
  await page.close();
}

// 3 · Fahrt eintragen mit gesetzter Auswahl: Anna, Clara und David (Fahrer).
{
  const page = await open();
  await page.mouse.click(332, 776); // FAB „Fahrt eintragen"
  await page.waitForTimeout(2500);
  await clicks(page, [[68, 285], [292, 285], [68, 367]], 400);
  await page.waitForTimeout(1500);
  await shot(page, 'fahrt-eintragen');
  await page.close();
}

// 4 · Statistik je Person.
{
  const page = await open();
  await tap(page, 'Statistik');
  await page.waitForTimeout(2500);
  await shot(page, 'statistik');
  await page.close();
}

await browser.close();

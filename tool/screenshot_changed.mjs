// screenshot_changed.mjs – Haben sich die Screenshots WIRKLICH geändert?
//
//   node tool/screenshot_changed.mjs <alt-verzeichnis> <neu-verzeichnis>
//
// Gibt „changed" oder „unchanged" auf stdout aus, dazu je Datei die Zahl
// abweichender Pixel auf stderr.
//
// Warum das nötig ist: Zwei Läufe derselben App liefern **nicht** dasselbe
// Bild. Die Stimmungs-Gesichter animieren, und jeder Lauf erwischt eine
// andere Phase. Die Bounding-Box der Abweichung lag in jeder Messung exakt
// auf einem Smiley; über vier Läufe hinweg waren es 5, 40, 113 und 281
// Pixel. `reducedMotion: 'reduce'` im Browser hilft nicht — Flutter-Web
// reicht `prefers-reduced-motion` nicht bis `disableAnimations` durch.
// Ohne Toleranz committete die CI deshalb bei jedem Lauf neue Bilder.
//
// TOLERANCE liegt eine Größenordnung über diesem Rauschen und immer noch
// weit unter jeder echten Änderung: Bei 860×1800 sind 1000 Pixel 0,06 %
// der Fläche — ein geändertes Wort, eine verschobene Kachel oder eine
// neue Farbe bewegen ein Vielfaches davon. Wer die Zahl anfasst, misst
// vorher nach (`tool/screenshots.sh` zweimal laufen lassen), statt zu
// schätzen.
import { chromium } from 'playwright';
import { readdirSync, readFileSync, existsSync } from 'fs';

const TOLERANCE = 1000;

const [, , oldDir, newDir] = process.argv;
if (!oldDir || !newDir) {
  console.error('Aufruf: screenshot_changed.mjs <alt> <neu>');
  process.exit(2);
}

const toUrl = (p) =>
  'data:image/png;base64,' + readFileSync(p).toString('base64');

const files = readdirSync(newDir).filter((f) => f.endsWith('.png')).sort();
const browser = await chromium.launch();
const page = await browser.newPage();

let changed = false;
for (const file of files) {
  const before = `${oldDir}/${file}`;
  if (!existsSync(before)) {
    console.error(`${file}: neu`);
    changed = true;
    continue;
  }
  const diff = await page.evaluate(async ([a, b]) => {
    const load = (src) =>
      new Promise((res, rej) => {
        const img = new Image();
        img.onload = () => res(img);
        img.onerror = rej;
        img.src = src;
      });
    const data = (img) => {
      const c = document.createElement('canvas');
      c.width = img.width;
      c.height = img.height;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0);
      return ctx.getImageData(0, 0, img.width, img.height).data;
    };
    const [ia, ib] = await Promise.all([load(a), load(b)]);
    if (ia.width !== ib.width || ia.height !== ib.height) return Infinity;
    const da = data(ia);
    const db = data(ib);
    let n = 0;
    for (let i = 0; i < da.length; i += 4) {
      if (
        da[i] !== db[i] ||
        da[i + 1] !== db[i + 1] ||
        da[i + 2] !== db[i + 2]
      ) {
        n++;
      }
    }
    return n;
  }, [toUrl(before), toUrl(`${newDir}/${file}`)]);

  console.error(`${file}: ${diff} Pixel abweichend`);
  if (diff > TOLERANCE) changed = true;
}

await browser.close();
console.log(changed ? 'changed' : 'unchanged');

---
name: run-web
description: RideBuddy als Web-App lokal starten und mit Playwright durchklicken, um eine Änderung in der echten App zu sehen. Nutzen, wenn die App gestartet, bedient oder per Screenshot geprüft werden soll — oder wenn zu prüfen ist, ob etwas wirklich funktioniert und nicht nur der Test grün ist.
---

# RideBuddy im Browser bedienen

Flutter-Web zeichnet auf **Canvas**. Es gibt keinen DOM-Text zum Auslesen —
geprüft wird über **Screenshots, die man sich ansieht**. Ein leeres oder
unverändertes Bild ist ein Fehlschlag, kein Zwischenstand.

Der Weg hat sich mehrfach bewährt: Er hat einen echten Mandanten-Fehler,
eine irreführende Meldung und einen kaputten Datei-Dialog gefunden, die
alle 200 Tests durchgelassen hatten.

## 1. Demo-Build erzeugen

Der Demo-Modus greift, sobald `SupabaseConfig.url` der Platzhalter ist:
In-Memory-Daten, **kein Login**, vier Personen (Anna, Ben, Clara, David)
mit Fahrten der letzten zwei Wochen. Das ist fast immer der richtige
Stand — kein echter Gruppenzugang, keine Migrationsabhängigkeit.

```bash
export PATH="/Volumes/MacStore/Programming/Flutter/SDK/flutter/bin:$PATH"
sed -i '' "s|azrlhlcxhpwmxcinjovp.supabase.co|REPLACE-ME.supabase.co|" \
  lib/core/supabase_config.dart
flutter build web
git checkout -- lib/core/supabase_config.dart   # SOFORT zurück
git status --short lib/core/supabase_config.dart  # muss leer sein
```

**Immer sofort zurücksetzen und das prüfen.** Der Platzhalter darf nie
committet werden — sonst läuft die veröffentlichte App im Demo-Modus.

> **`git checkout --` wirkt nur auf getrackte Dateien.** Wer für einen
> Testbau eine *neue* Datei anfasst, muss sie aus einer Kopie
> zurückholen. Das ist hier schon einmal schiefgegangen und hinterließ
> geänderte Werte im Arbeitsverzeichnis.

Braucht der Testfall etwas, das die Demo nicht hergibt (z. B. eine
gesetzte Mindestversion oder ein verfügbares Update), dazu **eine**
weitere Datei per Kopie sichern, patchen, bauen, zurückkopieren.

### Nach jeder neuen Dependency: `flutter clean`

`flutter build web` benutzt sonst eine zwischengespeicherte
`web_plugin_registrant.dart` **ohne** das neue Plugin. Der Aufruf landet
dann im Method-Channel und stirbt zur Laufzeit — der Code ist in Ordnung,
der Build nicht. So verlor der CSV-Import eine Stunde:

```bash
newest=$(ls -t .dart_tool/flutter_build/*/web_plugin_registrant.dart | head -1)
grep -c '<paket>' "$newest"   # 0 => flutter clean && neu bauen
```

## 2. Ausliefern

```bash
cd build/web && python3 -m http.server 8731   # im Hintergrund starten
```

## 3. Bedienen

Playwright liegt nicht im Projekt; einmalig im Scratchpad einrichten:

```bash
npm init -y && npm i playwright && npx playwright install chromium
```

Gerüst — Kern ist das Aktivieren des Semantics-Baums:

```js
import { chromium } from 'playwright';
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 1100, height: 1200 } });
p.on('pageerror', (e) => console.log('!! JS-Fehler:', e.message));
p.on('console', (m) => { if (m.type() === 'error') console.log('!!', m.text()); });
await p.goto('http://localhost:8731/', { waitUntil: 'networkidle' });
await p.waitForTimeout(3500);

// Flutter baut den a11y-Baum erst auf Anforderung. NUR so:
await p.locator('flt-semantics-placeholder').dispatchEvent('click');
await p.waitForTimeout(2000);

await p.screenshot({ path: '01.png' });
await b.close();
```

**`.click()` und `page.evaluate` funktionieren dafür nicht.** Der
Platzhalter liegt bei (-1,-1) außerhalb des Viewports, und ein von Hand
gebautes `MouseEvent` ignoriert Flutter. Nur `dispatchEvent` über den
Locator löst aus.

### Elemente finden

Zuerst über die Beschriftung — dieselbe, die ein Screenreader liest:

```js
const nodes = await p.locator('flt-semantics[aria-label]').all();
for (const n of nodes) {
  const l = (await n.getAttribute('aria-label')) ?? '';
  if (/^Anna, Mo, /.test(l)) await n.dispatchEvent('click');
}
```

Der Baum ist aber **lückenhaft**: Navigation und beschriftete Zellen
tauchen auf, viele Schaltflächen nicht. Dann über **Koordinaten aus dem
Screenshot** klicken (`viewport` entspricht 1:1 den Bildpunkten) und nach
jedem Schritt erneut abbilden. Vorsicht: Banner verschieben das Layout —
nach dem Wegklicken sitzt der Knopf woanders.

### Dateidialoge

Funktioniert, sobald das Plugin registriert ist (siehe `flutter clean`):

```js
p.on('filechooser', async (fc) => fc.setFiles('probe.csv'));
```

## Was hier nicht geht

- **Text aus dem DOM lesen.** `innerText` ist leer. Nur Screenshots.
- **Android prüfen.** Teilen-Menü (`share_plus`), Dateiauswahl
  (`file_selector`) und das In-App-Update (`ota_update`) laufen im
  Browser über andere Pfade. Wer die prüfen will, braucht ein Gerät.
- **Echte Gruppendaten.** Bewusst nicht: Für Tests gibt es keinen echten
  Gruppenzugang.

## Zum Schluss

Server beenden und bestätigen, dass das Arbeitsverzeichnis sauber ist:

```bash
git status --short
```

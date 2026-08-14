# Store-Grafiken

Assets für den Play-Store-Eintrag. **Alles hier ist ERZEUGT, nicht
gezeichnet** — von `tool/store_assets.py`, aus Quellen, die im Repo längst
gepflegt werden. Nie von Hand nachbearbeiten; nach Änderungen an Marke oder
Screenshots das Skript neu laufen lassen (dieselbe Linie wie bei den Icons
und den README-Screenshots).

Nichts davon landet im Build (`doc/` steht in keiner Asset-Liste und ist vom
Version Guard ausgenommen): eine neue Grafik ist kein Release.

| Datei | Format | Play-Feld | Quelle |
|---|---|---|---|
| `icon-512.png` | 512 × 512, 32-Bit PNG | App-Symbol | `web/icons/Icon-maskable-512.png` (aus `tool/brand/build_icons.sh`) |
| `feature-graphic.png` | 1024 × 500 | Feature-Grafik | Marken-Verlauf + `ic_launcher_foreground.png` + `assets/fonts/` |
| `screenshots/01–04` | 1080 × 1920 (9:16) | Telefon-Screenshots | `doc/screenshots/*.png` (aus `tool/screenshots.sh`) |
| `data_safety.csv` | CSV | Datensicherheit → „Aus CSV importieren" | `tool/play_data_safety.py` + `data_safety_template.csv` |
| `data_safety_template.csv` | Quelle | — | Googles Muster-CSV aus der Play-Console-Hilfe |

**Tablet-Screenshots gibt es bewusst nicht.** Das Feld ist optional, und
MitFahrBar hat kein eigenes Tablet-Layout. Hochskalierte Telefon-Bilder
dort einzustellen wäre eine Behauptung über eine Darstellung, die es nicht
gibt — leer lassen ist die ehrlichere Antwort (dieselbe Entscheidung wie bei
PilzBuddy).

## Neu erzeugen

```bash
python3 tool/store_assets.py       # Grafiken, braucht nur Pillow
python3 tool/play_data_safety.py   # Datensicherheits-CSV, nur stdlib
```

Die Maße prüft `test/store_assets_test.dart` bei jedem Lauf mit — ein
falsches Format fällt sonst erst der Console auf, und die sagt nur, dass
etwas nicht passt.

## Drei Entscheidungen, die im Skript stecken

- **Das App-Symbol ist das maskable PWA-Icon**, nicht `Icon-512.png`: Play
  verlangt eine volle 512×512-Fläche als 32-Bit-PNG, und das normale Icon
  ist die weiße Marke auf Transparenz — im Store-Umfeld unsichtbar.
- **Die Screenshots werden seitlich aufgefüllt, nie beschnitten.** Die
  README-Screenshots sind 860×1800 (1:2,09), und Play lehnt alles über 2:1
  ab. Ein Zuschnitt träfe App-Bar oder Navigationsleiste; stattdessen
  skaliert das Skript auf 1920 Höhe und füllt links/rechts mit der
  Randfarbe des jeweiligen Bildes — die Naht ist unsichtbar.
- **Der Textkontrast der Feature-Grafik wird gemessen, nicht geschätzt**
  (WCAG 4,5:1 gegen den Verlauf am Textende, wie in
  `test/banner_contrast_test.dart`). Der Lauf bricht darunter ab — und er
  bricht auch bei Überlappung von Text und Marke ab, denn genau die hat
  die Messung beim ersten Wurf gefangen (Weiß auf Weiß, 1,00:1).

# Preisarchiv skalieren: Woche statt Gebiet — und kein Raster

**Status:** entschieden und gemessen am 2026-08-21 · **Ergänzt, ersetzt
nicht:** `doc/finanzierung-und-skalierung.md`,
`doc/entscheidung-preisarchiv-lizenz.md`

## Die Frage

Halten die Spritpreise auch bei hunderten Nutzern, ohne den Free Tier zu
verlassen? Der naheliegende Vorschlag war ein **Preis-Netz für ganz
Deutschland**: ein grobes Raster, dessen Punkte sich alle Gruppen teilen —
statt eines Werts je Gruppe.

## Was wirklich skalierte

Nicht die Zeilen. `price_week` hat 156 Zeilen je Gruppe und Jahr; selbst bei
tausend Gruppen ist das nichts (`doc/finanzierung-und-skalierung.md` §3).

**Der Download war es.** Der Nachfüller lief gebietsweise, und jede Woche
kostet sieben Tagesdateien à ~30 MB. Weil `region_key` auf zwei
Nachkommastellen auflöst (~1 km, `supabase/schema.sql:548-551`), hat
praktisch jede Gruppe ihr eigenes Gebiet — die zweite Gruppe im Nachbarort
zahlte dieselben 210 MB noch einmal. Der Aufwand wuchs also mit der Zahl der
Gruppen, obwohl **dieselben Dateien jeden Mittelpunkt in Deutschland
tragen**: Gefiltert wird erst beim Lesen.

## Die Messung: darf der Mittelpunkt einrasten?

Ein Raster hätte zusätzlich die Zeilen geteilt — um den Preis, dass der
Wert nicht mehr für den Punkt der Gruppe gilt, sondern für den nächsten
Gitterpunkt. Was das kostet, ist eine Messfrage
(`tool/import_fuel_history.py --compare-grid`).

144 Vergleiche je Maschenweite: 8 Orte × 6 Wochen (2023–2026) × 3 Sorten.
Die Orte waren sechs echte Gegenden (Bad Rappenau, München, Schwerin,
Leipzig, Köln, Freiburg) und **zwei konstruierte Eckpunkte**, die maximal
weit einrasten — sonst misst man nur den Glücksfall.

| Maschenweite | Versatz | Mittel (Zug) | exakt gleich | ≤ 1 ct | p95 | Maximum |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 0,1° | ~3–7 km | −0,078 ct | 78 % | 89 % | 1,00 ct | 1,50 ct |
| 0,25° | ~7–17 km | +0,017 ct | 63 % | 76 % | 1,00 ct | 1,90 ct |
| 0,5° | ~16–28 km | −0,164 ct | 46 % | 58 % | 2,00 ct | 3,00 ct |

**Kein systematischer Zug bei keiner Größe** — alle Mittelwerte liegen unter
0,17 ct. Das Einrasten verschiebt das Preisniveau also nicht, es verrauscht
es. Genau diese Unterscheidung hat schon die Stichproben-Frage entschieden:
Mo–Do zog **systematisch** bis 1 ct (abgelehnt), ein Tag je Woche rauschte
mit ±2 ct (ebenfalls abgelehnt).

**Die Schwelle war 1 ct, und sie reißt auch die feinste Maschenweite**
(0,1°: 1,50 ct). Damit ist das Raster abgelehnt — nicht knapp, sondern nach
demselben Maßstab, an dem die anderen beiden Fragen entschieden wurden.

## Die Lösung, die nichts kostet

Der Gewinn hing nie am Raster. Er hing daran, in welcher Reihenfolge
geschleift wird:

**Die Woche steht außen, die Gebiete innen** (`collect_weeks`). Eine Woche
wird einmal gelesen und trägt daraus beliebig viele Mittelpunkte — jeden mit
seinem exakten 20-km-Kreis. Der Download hängt ab hier an der Zahl der
offenen **Wochen** und ist von der Zahl der Gruppen unabhängig.

| | vorher | nachher |
| --- | --- | --- |
| Download | 210 MB je **Gebiet und Woche** | 210 MB je **Woche**, für alle |
| Genauigkeit | exakter Kreis je Gruppe | **unverändert exakt** |
| Zeilen | 156/Jahr je Gruppe | unverändert |
| Lizenzlage | jede Gruppe liest nur ihre Werte | **unverändert** |

Belegt an synthetischen Daten: drei Gebiete, dieselbe Woche — getrennt 14
Preisdateien, geteilt 7, **bei bitgleichen Werten**. Die Gleichwertigkeit
ist die eigentliche Prüfung; ein schnellerer Lauf, der andere Zahlen
liefert, wäre kein Fortschritt.

`--max-weeks` zählt seither **geladene Wochen** statt Gebiet-mal-Woche —
also das, was wirklich Geld und Zeit kostet.

## Was das nicht löste — und was einen Tag später fiel

Beim Schreiben dieses Dokuments blieb **Tankerkönigs Minutenlimit** offen:
Der Live-Takt fragte je Gebiet dreimal täglich ab, gedeckelt auf fünf
Gebiete je Lauf, und der Deckel schnitt ohne Sortierung und ohne Cursor ab —
ab dem sechsten Gebiet wäre dauerhaft dasselbe leer ausgegangen.

**Erledigt mit v0.86.0:** Der geplante Takt ist abgeschaltet, die
Wochenwerte kommen ausschließlich aus dem Archiv (Migration
20260822020000). Es ging folgenlos, weil der Nachfüller von Anfang an
dieselbe Kennzahl rechnete — genau dafür war die Deckungsgleichheit gebaut.
Der API-Schlüssel bleibt liegen: Ein späterer Tankdaumen ist eine
Nutzeraktion und damit die Nutzung, um die Tankerkönig bittet.

## Wer das Raster wieder vorschlägt

`--compare-grid` bleibt im Werkzeug stehen, wie der Soak-Test bei der
Fahrerwahl: **Die Messung wiederholen, nicht diesen Satz zitieren.** Sie
kostet zwei Minuten und braucht weder Datenbank noch Schreibrechte.

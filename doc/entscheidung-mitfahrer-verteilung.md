# Designentscheidung: Mitfahrer-Verteilung bei Mehrfahrer-Tagen

**Status:** entschieden am 2026-07-24 · **Kontext:** Issue #62 ·
**Beleg:** `test/plan_soak_test.dart` (PR #79)

## Die Frage

Mit dem Mehrfahrer-Ausbau (v0.26.0–v0.28.0) blieben zwei Konzeptfragen offen:

1. Ist die Punkte-Näherung der **Wochen-Simulation** bei geteilten Tagen
   akzeptabel?
2. Soll die **Vorbelegung der Autos** beim Eintragen die Mitfahrer anders
   verteilen — konkret: „Anti-Solo" (bei Platz-Gleichstand bekommt das noch
   leere Auto den Mitfahrer, damit kein Fahrer leer ausgeht) statt der
   heutigen Regel (meiste freie Plätze, Gleichstand → bedürftigster Fahrer)?

Hintergrund zu Frage 2: Eine Solo-Fahrt zählt bewusst in keine Kennzahl
(v0.24.0). Wer bei einem geteilten Tag das zweite Auto solo fährt, fährt
also „umsonst" — im Sichttest kam genau das vor (3+1-Verteilung: der
bedürftigste Fahrer bekam alle Mitfahrer, der zweite fuhr allein).

## Die Methode

Statt Bauchgefühl: eine deterministische Langzeit-Simulation
(`test/plan_soak_test.dart`). 400 Wochen ≈ 2000 Arbeitstage, 8 Personen mit
Sitzen von 2 bis 7, Verfügbarkeiten aus einem eigenen xorshift32-PRNG mit
festem Seed — der Datensatz ist damit „einmal erstellt und für immer
gleich", ohne als Datei im Repo zu liegen. Jede Woche wird geplant
(`planWeek`, keine Overrides) und der Vorschlag exakt wie im
Bestätigen-Flow gebucht. Zwei Szenarien: **Alltag** (Ø ~3,5 Anwesende,
Kapazität bindet selten) und **Dauervoll** (Ø ~6,1 Anwesende, nur ein
7-Sitzer). Für Frage 2 lief derselbe Datensatz zusätzlich mit einem
Wegwerf-Patch (Anti-Solo-Tie-Break im Verteil-Loop von
`lib/core/fairness.dart`); der Patch wurde nach der Messung verworfen.

## Die Ergebnisse

**Frage 1 ist von der Implementierung überholt:** `planWeek` simuliert je
Auto eine eigene Pseudo-Fahrt mit der konkreten Sitzverteilung (Solo-Auto
zählt null, 1-way halb) — es gibt keine „Gleichverteilungs-Näherung" mehr.
Vorschau und Realität stimmten im Sichttest exakt überein.

**Frage 2: Der Tie-Break ist praktisch wirkungslos.**

| Kennzahl (Alltag, 2000 Tage) | heutige Regel | Anti-Solo |
|---|---|---|
| Solo-Fahrten | 85 | 84 |
| Punkte-Spreizung Ende | 1140,0 | 1139,5 |
| größte Punkt-Verschiebung je Person | — | ≤ 3 |
| Szenario Dauervoll | — | **byte-identisch** |

Der erzwungene Solo-Fall existiert, ist aber so selten, dass er über acht
simulierte Jahre eine einzige Fahrt und eine halbe Punktestelle bewegt.
Die 85 Solo-Fahrten des Alltags-Szenarios sind fast ausschließlich echte
Ein-Personen-Tage, keine Verteilungs-Artefakte.

**Der eigentliche Befund — Kapazitäts-Kohorten:** Die Fairness-Logik
(Punkte-Vorrang + gedeckelter Raten-Trim) konvergiert hervorragend
**innerhalb** vergleichbarer Autogrößen: Die 4-7-Sitzer enden nach 2000
Tagen ~28 Punkte auseinander, die beiden 3-Sitzer 5,5. **Zwischen** den
Kohorten driftet es unbegrenzt: Der 2-Sitzer-Besitzer sinkt auf −831
(ehrlich — er nimmt täglich, kann fast nie geben), im Dauervoll-Szenario
sammelt der einzige Bus-Besitzer +4187 Punkte bei ~45 % Überfahranteil,
weil der Sitzfilter fast täglich nur ihn qualifiziert und der
Punkte-Vorrang nur unter Qualifizierten wählen kann. Die Buchhaltung ist
korrekt; die Divergenz ist eine strukturelle Eigenschaft von Sitzfilter +
„ein Auto, wann immer eines reicht".

## Die Entscheidung

1. **Die Mitfahrer-Verteilung bleibt, wie sie ist** (meiste freie Plätze,
   Gleichstand → bedürftigster Fahrer). Ein Anti-Solo-Tie-Break brächte
   messbar nichts und wäre Komplexität ohne Ertrag. Der seltene echte Fall
   wird per Handarbeit im Editor sortiert — Handarbeit gewinnt ohnehin.
2. **Die Simulations-Frage ist gegenstandslos** (realistische Simulation
   ist implementiert und gepinnt).
3. **Die Kapazitäts-Kohorten-Grenze wird dokumentiert, nicht „repariert".**
   Für die heutige Flotte ist sie irrelevant; eine kapazitätsbewusste
   Entlastung wäre eine Produktentscheidung mit der Gruppe, kein
   Formel-Feintuning.

## Nachtrag 2026-07-24: Realflotte — der maßgebliche Lauf

Auf Marcus' Review hin wurde die Simulation mit dem realen Setup der Gruppe
wiederholt (Ø ~3,3 Anwesende bei Tagen mit ≥ 2, 5er-Tage ~9 %, ≥ 6 nur
~3 %; Autos 4/4/4/4/5/5/5/7) und gegen sein explizites Ziel geprüft:
Punktedifferenzen um 0, Fahrraten ±2 Prozentpunkte.

- **Punkte-Ziel: klar erfüllt.** Alle acht Endstände nach 2000 Tagen
  innerhalb ±2 Punkten, Spreizung stationär (max. 18,5 im letzten
  Viertel). Zum Vergleich: Das synthetische Setup lag bei ±831.
- **Raten-Ziel: strukturell unvereinbar mit gemischter Flotte.** Der
  7-Sitzer weicht −8,8 pp ab — punkte-fair fährt er seltener, aber
  voller: Rate ≈ 1/(1 + Ø Mitgenommene je eigener Fahrt), und die hängt
  an der Autogröße. Die **Kontrolle** (identische Anwesenheit, alle Autos
  5 Sitze) erfüllt BEIDE Ziele (±1,0 pp) und isoliert damit die
  Autogröße als einzige Ursache. Wer Raten-Gleichheit über
  Punkte-Gleichheit stellt, trifft eine Produktentscheidung (z. B.
  stärkerer Raten-Trim) — es ist kein Planer-Fehler.
- **A/B auf der Realflotte:** weiterhin bedeutungslos (gleiche Fahrten-
  und Solo-Zahlen, Endstände verschieben sich ≤ 3 Punkte). Die
  Entscheidung oben bleibt unverändert.

Beide Läufe sind als Szenarien „Realflotte" und „Kontrolle" in
`test/plan_soak_test.dart` gepinnt; das ±2-pp-Ziel ist dort als Assertion
verankert, wo es erreichbar ist (Kontrolle).

## Nachtrag 2026-07-24 (2): Finetuning-Sweep — kRateBalance ist wirkungslos

Auf Marcus' Frage „können wir Finetuning an der Logik vornehmen?" wurde der
einzige Tuning-Parameter der Fahrerwahl, der Raten-Trim `kRateBalance`
(heute 2), auf dem Realflotten-Datensatz von 0 (Trim aus) bis 12
(sechsfache Autorität) gesweept — jeweils als Wegwerf-Patch:

| kRateBalance | 0 | 1 | 2 | 4 | 6 | 8 | 12 |
|---|---|---|---|---|---|---|---|
| max. Raten-Abw. Realflotte (pp) | 9,1 | 9,3 | 8,8 | 8,8 | 9,1 | 8,8 | 8,6 |
| max. Raten-Abw. Kontrolle (pp) | 1,0 | 1,2 | 1,0 | 1,0 | 1,0 | 0,7 | 1,3 |
| max. Endpunkte-Betrag Realflotte | 2,5 | 1,5 | 2,0 | 2,5 | 2,5 | 3,0 | 2,0 |

**Beide Kurven sind flach.** Der Trim bewegt die Raten-Spreizung nicht —
weder in der Realflotte (dort ist die Rate bei Punkten ≈ 0 durch
Rate ≈ 1/(1 + Ø Belegung eigener Fahrten) festgelegt, und WER volle Tage
fahren darf, entscheidet die Sitz-Abdeckung) noch in der Kontrolle (dort
gleichen die Punkte die Raten schon allein an). **Konsequenz:**

1. Es gibt an dieser Logik nichts zu tunen; `kRateBalance` bleibt bei 2.
   Wer die Bus-Rate angleichen wollte, müsste Abdeckungsregel oder
   Punkte-Vorrang ändern — Produktentscheidung, kein Parameter.
2. Der Trim wird trotzdem NICHT entfernt: Er ist in CLAUDE.md bewusst
   verankert, kostet nichts und könnte in nicht simulierten Regimen
   wirken. Aber: Von einer Erhöhung ist nichts zu erwarten — dieser
   Nachtrag existiert, damit das niemand mehr ausprobieren muss.

## Nachtrag 2026-07-24 (3): Zielflotte — das Akzeptanz-Szenario

Marcus hat das Soll-Set neu gesetzt: Flotte **1×4 / 6×5 / 1×7** Sitze, und
die Tagesgrößen nicht mehr geschätzt, sondern **aus dem echten
DaciaRacing-Protokoll gemessen** (401 Fahrt-Tage 2023–2026): 2er 40 %,
3er 33 %, 4er 20 %, 5er 5,5 %, 6er 1,0 % — **nie 7 oder 8**. Ein 7er-Tag
liegt mit 0,4 % (≈ 1×/Jahr, Marcus' Obergrenze) trotzdem im Würfel, ein
8er nicht. Anwesenheits-Gewichte = die gemessenen Quoten der acht
Aktivsten (64…7,5 %); der 7-Sitzer gehört wie real dem viert-präsentesten
Stammfahrer, der 4-Sitzer als härtester Fall dem präsentesten (Annahme —
wenn er real woanders steht, ist das eine Konstante). One-Way 5 %
(real 4,8 %). Szenario „Zielflotte" in `test/plan_soak_test.dart`,
je Variante 10 Seeds à 2000 Tage.

**Ergebnis mit der heutigen Logik (kRateBalance = 2):**

| Kennzahl (10 Seeds) | Wert |
|---|---|
| Endpunkte | Haupt-Seed ±2, über alle Seeds ≤ 5,5 |
| Raten-Abweichung Ø der Seed-Maxima | 16,8 ‰ |
| Raten-Abweichung Worst-Case | 27 ‰ (Bus) |
| echte Gruppe, von Menschen geplant (Referenz) | bis −51 ‰ |

Das Punkte-Ziel ist klar erfüllt, das Raten-Ziel (±20 ‰) im Mittel auch;
der Worst-Case liegt bei ±2,7 pp — und die Automatik schlägt die
menschliche Planung der echten Gruppe (±5,1 pp) etwa um Faktor zwei.

**Woher der Rest kommt — der strukturelle Boden:** Die Kontrolle
„gleicher Würfel, aber lauter 5-Sitzer" reißt das ±2-pp-Ziel genauso
(Worst 22 ‰, Ø 11,7 ‰). Ursache ist die **Anwesenheits-Struktur**, nicht
die Flotte: Selten Anwesende sind eher an großen Tagen dabei — im echten
Protokoll genauso (Ø-Tagesgröße 3,1 beim Präsentesten vs. 3,8 bei
Rang 7) — und wer an großen Tagen fährt, fährt voller, verdient mehr je
Fahrt und fährt bei Punkten ≈ 0 zwangsläufig seltener
(Rate ≈ 1/(1 + Ø Mitgenommene)). Kein Fahrerwahl-Mechanismus kann
darunter, denn er entscheidet nur, WER an einem Tag fährt, nicht, wer
anwesend ist. Die Flotte selbst (Bus + 4-Sitzer) legt nur noch ~0,5 pp
obendrauf, konzentriert auf den Bus (−) und den 4-Sitzer (+).

**Mechanismen-Vergleich (je 10 Seeds, Wegwerf-Patches):**

| Mechanismus | Ø Seed-Maxima | Worst |
|---|---|---|
| heutiger Trim, k = 2 | 16,8 ‰ | 27 ‰ |
| stärkerer Trim, k = 6 | 15,6 ‰ | 22 ‰ |
| kombinierter Rang (`points_weight` 0,95/0,9/0,8) | — | 32 ‰, verworfen |

Der kombinierte Rang ist auf allen drei Gewichten byte-identisch und
schlechter als beide Trim-Varianten — er schaltet den tagesgrößen-
bewussten Trim ab, der die eigentliche Angleich-Arbeit macht. Der
stärkere Trim k = 6 erreicht praktisch den Boden der Kontrolle; seine
theoretische Autorität wächst auf ±6 Punkte, die praktische bleibt bei
`6 · Δ-Rate · |dayFactor|` ≈ 0,2 Punkten — der Punkte-Vorrang bliebe de
facto intakt. **Einordnung zu Nachtrag 2:** „kRateBalance ist
wirkungslos" gilt für die alte Kalibrierung mit ~12 % großen Tagen; auf
der Zielflotte bewegt k = 6 den Worst-Case messbar (−0,5 pp), wenn auch
nicht kategorial.

**Stand:** Der Test pinnt die heutige Logik mit der Boden-Schranke
±30 ‰. **Offen ist eine einzige Produktentscheidung:** kRateBalance
2 → 6 (eine Konstante in `fairness.dart`, Versions-Bump, Marcus' Merge)
senkt den Worst-Case von ±2,7 auf ±2,2 pp ≈ Boden. Tiefer ginge nur ein
Eingriff in die Punkte-Formel selbst (Belegungs-Normierung) — der stünde
im Konflikt mit KONZEPT 3.2 und dem Grundsatz „Punkte = gegebene
Mitfahrten" und ist nicht empfohlen.

## Wiedervorlage-Kriterien

- Die Flotte bekommt ein dauerhaftes Groß-/Kleinwagen-Gefälle **und** volle
  Tage werden die Regel → Kohorten-Drift wird real spürbar („wer ist dran"
  zeigt dauerhaft dieselbe Person, die nie fahren kann). Dann: Entscheidung
  mit der Gruppe über kapazitätsbewusste Entlastung.
- Wer Sitzfilter, Rückfalllinie oder Ein-Auto-Regel ändert, sieht die
  gepinnten Zahlen in `test/plan_soak_test.dart` wandern und kalibriert
  bewusst neu — mit Update dieses Reports.

# Finanzierung und Skalierung von MitFahrBar

**Status:** recherchiert am 2026-08-17 · **Plattformseite:**
`doc/finanzierung-plattformvergleich.md` · **Ergänzt, ersetzt nicht:**
`doc/entscheidung-preisarchiv-lizenz.md`

Dies ist **keine Steuer- oder Rechtsberatung.**

## Die Frage

Was kostet MitFahrBar heute, was bricht zuerst, wenn die Gruppenzahl steigt,
und welche Finanzierungsmodelle sind hier überhaupt zulässig?

## Die Antwort in einem Satz

**MitFahrBar ist die einzige der drei Apps, bei der die Finanzierungsfrage
zuerst eine Lizenzfrage ist.** Das historische Preisarchiv steht unter
CC BY-NC-SA 4.0; jede Form von Einnahme mit Gegenleistung bricht die
NC-Bedingung, bevor sie irgendein technisches Problem löst. Und die härteste
Wachstumsgrenze — Tankerkönigs Minutenlimit — verschwindet durch Geld
ohnehin nicht.

## Kostenbild heute

**0 €/Monat.**

| Posten | Dienst | Tarif |
| --- | --- | --- |
| Datenbank, Auth, Edge Functions | Supabase | Free |
| Auth-Mails | Brevo | Free |
| Push | Firebase Cloud Messaging | kostenlos, unbegrenzt |
| Web-Auslieferung | GitHub Pages | frei (öffentliches Repo) |
| APK-Auslieferung | GitHub Releases | frei, keine Bandbreitengrenze |
| CI | GitHub Actions | frei (öffentliches Repo) |
| Preisdaten | Tankerkönig | frei, Schlüssel kostenlos |

Der Free-Plan gibt 500 MB Datenbank, 5 GB Egress, 50.000 monatlich aktive
Nutzer und 500.000 Edge-Function-Aufrufe. Kein Point-in-Time-Recovery — dafür
läuft der wöchentliche verschlüsselte Dump (`.github/workflows/backup.yml`,
`tool/db_backup.sh`, Verfahren in `doc/backup-restore.md`).

## Was zuerst bricht — in dieser Reihenfolge

### 1. Tankerkönigs Minutenlimit. Und Geld löst es nicht.

Das ist die schärfste Grenze im ganzen System, und sie ist keine Kostengrenze.

Die Nutzungsbedingungen nennen **eine Abfrage je Minute je Schlüssel** — das
Limit hängt am Schlüssel, nicht am Gerät. `supabase/functions/fuel-sample/`
setzt das um: `MAX_REGIONS_PER_RUN = 5` und `REGION_GAP_MS = 61_000`, also
fünf Regionen nacheinander mit 61 Sekunden Abstand, rund vier Minuten
Laufzeit je Aufruf, bei drei Läufen pro Tag (`sample-fuel-prices`,
`5 5,11,17 * * *`).

Solange mehrere Gruppen im selben Gebiet fahren, kostet das nichts extra —
`fuel-sample` entdoppelt über `price_area.region_key`, zwei Gruppen in
derselben Region teilen sich einen Abruf. **Die Grenze ist die Zahl
verschiedener Regionen, nicht die Zahl der Gruppen.** Ab etwa fünf
unterschiedlichen Gebieten bricht der Lauf ab und vertagt den Rest; ab etwa
fünfzehn kommt eine Region seltener als einmal täglich dran.

Was dagegen hilft, ist keine Bezahlplattform, sondern: ein zweiter
API-Schlüssel (sofern die Nutzungsbedingungen das hergeben — **zu klären**),
oder ein kommerzieller Vertrag mit Tankerkönig. Beides ist eine Absprache mit
Tankerkönig, keine Rechnung an uns.

### 2. `push_log` wächst unbegrenzt

`public.push_log` hat **keine Retention** — im ganzen Schema und in
`tool/` findet sich kein `delete`, kein Aufräum-Cron, nichts. Die Tabelle
bekommt je Person, Plantag und Meldungsart eine Zeile und behält sie für
immer. Bei vier Personen und rund 250 Fahrtagen im Jahr sind das mehrere
tausend Zeilen je Gruppe und Jahr, die nie wieder gelesen werden — die
Abfragen in `push_due()` interessieren sich ausschließlich für den aktuellen
Plantag.

Das ist der erste Posten, der ohne jeden Nutzen gegen die 500-MB-Grenze
arbeitet. Gegenmittel ist ein `pg_cron`-Job, der Zeilen älter als etwa 90
Tage löscht — dasselbe Muster, das `rollup-fuel-weeks` für `price_sample`
schon fährt (21 Tage). **Vorgemerkt für den Effizienz-Durchgang.**

### 3. Datenbankgröße

Der Rest ist gutmütig. Je Gruppe und Jahr grob: ~200–250 `trips`,
~600–1.200 `trip_participations`, ~1.000 `plan_availability`, 156
`price_week`. `push_outbox` wird bei jedem Veröffentlichen vor `keep_from`
geleert, bleibt also am Planungshorizont hängen statt zu wachsen.
`price_sample` ist regionsgebunden statt gruppengebunden und wird nach 21
Tagen gelöscht.

Das heißt: **Zeilen je Gruppe sind kein Problem, `push_log` schon** — und
genau deshalb steht es eine Stufe höher.

### 4. Egress und Edge-Function-Aufrufe

`flush-due-push` läuft **jede Minute** (`schema.sql`), das sind fest
~43.800 Aufrufe im Monat von 500.000 — knapp 9 % des Kontingents, unabhängig
von der Gruppenzahl. Der Haken: Die DB-Funktion steigt nur aus, wenn die
Vault-Geheimnisse fehlen; **ob überhaupt etwas fällig ist, prüft sie vor dem
HTTP-Aufruf nicht**. Nachts, an Wochenenden und in fahrfreien Wochen ruft sie
also verlässlich ins Leere. Auch das ist für den Effizienz-Durchgang
vorgemerkt — nicht weil das Kontingent bricht, sondern weil es die Sorte
Abfrage ist, die niemand braucht.

Egress ist unkritisch: Die App überträgt JSON-Zeilen, der einzige große
Datenstrom ist der Nachfüll-Lauf des Preisarchivs (~30 MB je Tagesdatei), und
der läuft auf GitHub-Runnern, nicht durch Supabase.

## Die Lizenzfrage — der Kern dieses Dokuments

Die Spritpreise kommen aus **zwei Quellen mit zwei verschiedenen Lizenzen**:

| Quelle | Was | Lizenz | Kommerziell? |
| --- | --- | --- | --- |
| Tankerkönig-**API** (`fuel-sample`) | laufende Wochen | CC BY 4.0 | **ja**, mit Namensnennung |
| Tankerkönig-**Preisarchiv** (`tool/import_fuel_history.py`) | zurückliegende Wochen | **CC BY-NC-SA 4.0** | **nein** |

`doc/entscheidung-preisarchiv-lizenz.md` hat das bereits festgehalten und
definiert NC dort wörtlich als „keine Werbung, kein Verkauf, kein bezahlter
Zugang, keine Weiterverwertung der Daten" — mit dem Satz, der jetzt schlagend
wird: *„Sie ist deshalb die Bedingung, die als Erstes bricht, wenn sich am
Projekt etwas Grundsätzliches ändert."* Genau das ist der Fall, sobald aus
MitFahrBar Geld mit Gegenleistung fließt.

Es gibt drei Wege, und sie schließen einander aus.

### Weg 1 — nicht-kommerziell bleiben

Nur **Spenden ohne Gegenleistung**: GitHub Sponsors, Ko-fi oder ein
PayPal-Link auf der Projektseite, ohne dass Spender irgendetwas bekommen, was
andere nicht haben. Das Preisarchiv bleibt, `doc/entscheidung-preisarchiv-lizenz.md`
bleibt gültig, `test/price_archive_license_test.dart` bleibt grün, und es
braucht keine Gewerbeanmeldung.

**Das ist der Weg mit dem geringsten Reibungsverlust** und der einzige, der
nichts wegnimmt. Er trägt allerdings realistisch keine 35 $/Monat.

### Weg 2 — das Archiv aufgeben

Nur noch die Live-API benutzen. Die steht unter CC BY 4.0 und **erlaubt
kommerzielle Nutzung** bei Namensnennung; damit wären Einmalkauf, Pro-Version
und Abo lizenzrechtlich frei.

Der Preis ist konkret und sichtbar: `tool/import_fuel_history.py` und
`.github/workflows/fuel-history.yml` entfielen, die zurückliegenden Wochen in
`price_week` verlören ihre gemessene Grundlage, und die Ersparnis-Kurve fiele
auf den Zustand vor v0.53.0 zurück — also auf die Parameter-Konstante, die
laut CLAUDE.md rund 0,40 € unter dem realen Niveau liegt. Die 164 bereits
importierten Wochen dürfte man nicht kommerziell weiterverwenden; sie müssten
gelöscht werden.

**Ehrlich benannt:** Das ist der Weg, der ein gebautes und gemessenes Feature
gegen eine Einnahmemöglichkeit tauscht, die es noch nicht gibt.

### Weg 3 — kommerziellen Vertrag mit Tankerkönig schließen

Tankerkönig bietet für das Archiv ausdrücklich kostenpflichtige Verträge an.
Damit bliebe alles wie gebaut, und die NC-Klausel wäre durch eine
Einzellizenz ersetzt. Sinnvoll nur, wenn die Einnahmen den Vertrag tragen —
also nicht als erster Schritt, sondern als möglicher zweiter, **nachdem**
sich gezeigt hat, dass jemand zahlt. Nebenbei löste ein solcher Vertrag
womöglich auch das Minutenlimit; **beides in einem Gespräch klären.**

### Was in jedem Fall bleibt: die SA-Klausel

ShareAlike greift bei **Weitergabe**. Dass sie heute nicht bindet, ist keine
Eigenschaft der Lizenz, sondern des Codes: Die abgeleiteten Wochenwerte
verlassen die Gruppendatenbank nicht. Deshalb hat `price_sample` `revoke all`,
`price_week` nur Select mit RLS, und der CSV-Export deckt Fahrten und Personen
ab, **aber keine Preise**.

**Der fehlende Preis-Export ist ein Lizenzmerkmal, keine Bequemlichkeit.**
Wer ihn ergänzt — und es ist eine naheliegende Bitte —, muss vorher Weg 2
oder 3 gegangen sein.

## Die Modelle, einzeln bewertet

| Modell | Lizenzlage | Passt zu MitFahrBar? |
| --- | --- | --- |
| **Spenden** | unproblematisch | **Ja.** Sofort möglich, ohne Gewerbe. |
| **Abo je Gruppe** | braucht Weg 2 oder 3 | **Strukturell am besten** — die Kosten fallen je Gruppe an, nicht je Nutzer. Ein Abo bildet die Kostenstruktur exakt ab. |
| **Einmalkauf / Pro** | braucht Weg 2 oder 3 | Mäßig. Die Kosten sind laufend, ein Einmalbetrag ist es nicht. |
| **Werbung** | bricht NC sofort | **Nein.** Siehe unten. |

### Warum Werbung hier die schlechteste Option ist

Drei Gründe, und jeder allein reicht:

1. Sie bricht die NC-Klausel sofort und ohne Umweg — die
   Entscheidungsdatei nennt Werbung als Erstes in ihrer Aufzählung.
2. Sie widerspricht dem, was im Play Store steht: `doc/play-console.md`
   trägt „Werbung: Nein / In-App-Käufe: Nein" und das Data-Safety-Formular
   begründet das mit „Keine Werbe- oder Analyse-SDKs in `pubspec.yaml`".
   Beides müsste im selben Zug geändert werden.
3. Ein Werbe-SDK ist ein neues Netzziel mit eigener Datenweitergabe — in
   einer App, deren Nutzerkreis eine private Fahrgemeinschaft ist und deren
   ganze Architektur auf Datensparsamkeit ausgelegt ist (Push-Texte nie ins
   Log, Einladungstext nie ins Log, keine Fremd-Fehlerpipeline).

Der erwartbare Ertrag bei dieser Nutzerzahl steht in keinem Verhältnis dazu.

## Empfehlung

1. **Erst aufräumen**: `push_log`-Retention, `flush-due-push` nur bei
   tatsächlicher Fälligkeit. Kostet nichts und nimmt niemandem etwas.
2. **Klären, ob beide Supabase-Projekte in derselben Organisation liegen** —
   siehe Plattformvergleich; das entscheidet, ob der Free-Plan schon
   ausgereizt ist.
3. **Spenden** aufsetzen (Weg 1). Der einzige Schritt, der heute ohne
   Lizenz- und Gewerbefragen möglich ist.
4. **Mit Tankerkönig sprechen**, bevor irgendetwas anderes entschieden wird —
   zu Minutenlimit *und* Archivlizenz in einem Aufwasch. Das Ergebnis
   entscheidet, ob Weg 2 überhaupt nötig ist.
5. **Werbung nicht.**

## Offene Punkte

- Liegen PilzBuddy und MitFahrBar in derselben Supabase-Organisation?
- Erlauben Tankerkönigs Nutzungsbedingungen einen zweiten API-Schlüssel für
  denselben Betreiber?
- Was kostet ein kommerzieller Archivvertrag?
- Wie viele Gruppen und wie viele verschiedene `region_key` gibt es aktuell?
  Steht nicht im Repo — der wöchentliche Usage-Report
  (`tool/usage_report.dart`) meldet bewusst nur Summen.

## Quellen

Abgerufen am 2026-08-17.

- [Tankerkönig: CC-BY-4.0 für die Live-API, BY-NC-SA-4.0 für das Archiv](https://creativecommons.tankerkoenig.de/)
- Repo-intern: `doc/entscheidung-preisarchiv-lizenz.md`,
  `tool/import_fuel_history.py`, `supabase/functions/fuel-sample/index.ts`,
  `supabase/schema.sql`, `doc/play-console.md`, `README.md` §Lizenz
- Plattformpreise und rechtlicher Rahmen: `doc/finanzierung-plattformvergleich.md`

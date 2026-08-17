# Finanzierung und Skalierung von MitFahrBar

**Status:** recherchiert am 2026-08-17, am selben Tag gegen Code und
Produktion nachgemessen (§4 korrigiert, Zahlen ergänzt) · **Plattformseite:**
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

### 2. `push_log` wuchs unbegrenzt — erledigt in v0.84.1

`public.push_log` hatte **keine Retention** — im ganzen Schema und in
`tool/` fand sich kein `delete`, kein Aufräum-Cron, nichts. Die Tabelle
bekommt je Person, Plantag und Meldungsart eine Zeile und behielt sie für
immer. Bei vier Personen und rund 250 Fahrtagen im Jahr sind das mehrere
tausend Zeilen je Gruppe und Jahr, die nie wieder gelesen werden — die
Abfragen in `push_due()` interessieren sich ausschließlich für den aktuellen
Plantag.

Nachgemessen am 2026-08-17 (`supabase inspect db table-stats`): heute sind
das **55 Zeilen / 48 kB**, die ganze Datenbank liegt bei rund 4 MB von
500 MB. Der Posten ist also Struktur-Hygiene mit Jahren an Vorlauf, kein
akuter Brand — er steht trotzdem an dieser Stelle, weil er der einzige ist,
der ohne Gegenmaßnahme prinzipiell unbegrenzt wächst.

**Erledigt seit v0.84.1:** `prune_push_log()` löscht täglich Zeilen, deren
`plan_date` mehr als 90 Tage zurückliegt — dasselbe Muster, das
`rollup-fuel-weeks` für `price_sample` schon fährt (21 Tage). Warum das
nichts erneut auslösen kann, steht in der Migration
(`20260817220000_push_log_retention.sql`); `test/schema_test.dart` hält
Funktion, Cron-Job und Grenze fest. Damit ist von der ursprünglichen
Bruchliste dieses Dokuments nichts mehr offen, was im Repo lösbar wäre —
übrig bleiben die Tankerkönig-Fragen (§1) und die Lizenzentscheidung.

### 3. Datenbankgröße

Der Rest ist gutmütig. Je Gruppe und Jahr grob: ~200–250 `trips`,
~600–1.200 `trip_participations`, ~1.000 `plan_availability`, 156
`price_week`. `push_outbox` wird bei jedem Veröffentlichen vor `keep_from`
geleert, bleibt also am Planungshorizont hängen statt zu wachsen.
`price_sample` ist regionsgebunden statt gruppengebunden und wird nach 21
Tagen gelöscht.

Das heißt: **Zeilen je Gruppe sind kein Problem; `push_log` war das eine,
das keins bleiben durfte** — und steht deshalb eine Stufe höher, samt
seiner Lösung.

### 4. Egress und Edge-Function-Aufrufe

**Korrigiert am 2026-08-17 — die Erstfassung dieses Abschnitts behauptete
das Gegenteil und hätte fast einen „Effizienz-Fix" für etwas Gebautes
ausgelöst.** Sie rechnete `flush-due-push` als ~43.800 Edge-Function-Aufrufe
im Monat (9 % des Kontingents) und merkte an, die Funktion prüfe vor dem
HTTP-Aufruf nicht, ob etwas fällig ist. Beides stimmt nicht:

- Der Minutentakt ist ein `pg_cron`-Aufruf der **DB-Funktion** — er läuft
  innerhalb von Postgres und kostet kein Edge-Function-Kontingent.
- Die Fälligkeits-Prüfung steht seit dem 29.07.2026 in der Funktion selbst
  (`supabase/migrations/20260729140000_push_dispatch.sql`, #138):
  `if not exists (select 1 from public.push_due()) then return;` — samt
  Kommentar „Nichts zu tun heißt: nicht anklopfen". Die Edge Function wird
  nur gerufen, wenn wirklich etwas zu verschicken ist.

Nachgemessen: `push_outbox` (80 Zeilen) trägt ~62.000 Seq-Scans — die
Prüfung läuft minütlich, lokal, und ist auf Tabellen dieser Größe gratis.
Ins Edge-Kontingent gehen nur die tatsächlichen Fälligkeits-Minuten plus
`fuel-sample` (3 Aufrufe am Tag) — zusammen weit unter 1 % der 500.000.

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

1. **Aufräumen: erledigt.** Die `push_log`-Retention kam mit v0.84.1 (§2);
   die zweite Hälfte der ursprünglichen Empfehlung — `flush-due-push` nur
   bei tatsächlicher Fälligkeit — war seit #138 gebaut (Korrektur unter §4).
2. **Geklärt (2026-08-17): Beide Supabase-Projekte liegen in derselben
   Organisation** (`supabase projects list`). Das Free-Kontingent von zwei
   aktiven Projekten ist damit belegt — eine dritte Backend-App erzwingt
   Pro; dafür fiele Pro nur **einmal** an (~35 $/Monat für beide zusammen).
3. **Spenden** aufsetzen (Weg 1). Der einzige Schritt, der heute ohne
   Lizenz- und Gewerbefragen möglich ist.
4. **Mit Tankerkönig sprechen**, bevor irgendetwas anderes entschieden wird —
   zu Minutenlimit *und* Archivlizenz in einem Aufwasch. Das Ergebnis
   entscheidet, ob Weg 2 überhaupt nötig ist.
5. **Werbung nicht.**

## Offene Punkte

- Erlauben Tankerkönigs Nutzungsbedingungen einen zweiten API-Schlüssel für
  denselben Betreiber?
- Was kostet ein kommerzieller Archivvertrag?

## Seit der Erstfassung beantwortet (2026-08-17)

- **Dieselbe Supabase-Organisation.** `supabase projects list` zeigt beide
  Projekte in `ueryalfmngzsbocqxekk` — siehe die aktualisierte Empfehlung.
- **2 Regionen, 3 Gruppen.** `supabase inspect db table-stats` (Schätzwerte
  aus der Statistik): `price_area` 2 Zeilen, `groups` 3. Beim Minutenlimit
  (5 Regionen je Lauf) ist also reichlich Luft.
- **`flush-due-push` prüft die Fälligkeit längst** — Korrektur unter §4.

## Quellen

Abgerufen am 2026-08-17.

- [Tankerkönig: CC-BY-4.0 für die Live-API, BY-NC-SA-4.0 für das Archiv](https://creativecommons.tankerkoenig.de/)
- Repo-intern: `doc/entscheidung-preisarchiv-lizenz.md`,
  `tool/import_fuel_history.py`, `supabase/functions/fuel-sample/index.ts`,
  `supabase/schema.sql`, `doc/play-console.md`, `README.md` §Lizenz
- Plattformpreise und rechtlicher Rahmen: `doc/finanzierung-plattformvergleich.md`

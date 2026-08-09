# MitFahrBar — Arbeitsregeln

Flutter-Web-App (PWA) + Android-APK zur Verwaltung einer Fahrgemeinschaft:
Fahrtenprotokoll, Punkte-/Fairness-System („wer ist dran"), Statistik,
Dashboard-Charts. Supabase-Backend (multi-tenant, RLS in
`supabase/schema.sql`), Riverpod 2 ohne Codegen, go_router, deutsche
UI-Strings direkt im Code. Fachkonzept: `KONZEPT.md`.

Produktname ist **MitFahrBar** (seit v0.34.0, davor RideBuddy ab v0.6.0).
Repo, Dart-Package und Bundle-ID tragen den Namen mit — die Umbenennung war
bewusst vollständig (Issue #87): Ein Neuinstall auf Android war der Gruppe
lieber als ein zweiter Name im System.

**Zwei Dinge blieben trotzdem stehen, und das ist kein Versehen:**

- **`grp.fahrgemeinschaft.app`** (`core/group_login.dart` + Edge Function)
  ist die Login-Adresse jeder bestehenden Gruppe — sie steht serverseitig
  als E-Mail in `auth.users`. Umbenennen hieße Migration auf den
  Zugangsdaten der aktiv genutzten Gruppe, für etwas, das nie jemand
  sieht (der Login ist Handle + Passwort).
- **Der Handle `fahrgemeinschaft`** in
  `20260720140000_multi_tenant_groups.sql` gehört der Gruppe, die die
  Multi-Tenant-Migration aus dem damals einzigen Auth-User gemacht hat: bis
  v0.38.0 die Admin-Gruppe. Sie ist **nicht** die aktiv genutzte Gruppe —
  das ist DaciaRacing unter eigenem Handle. Es sind Daten in einer bereits
  eingespielten Migration, und die wird nie nachträglich umgeschrieben; auch
  `is_admin` steht dort noch, obwohl die Spalte seit v0.38.0 fehlt. Wer eine
  Frischinstallation braucht, nimmt `supabase/schema.sql` — die
  Migrationskette ist Geschichte, kein Sollzustand.

Ebenso unverändert: die `CHANGELOG.md`-Einträge vor v0.34.0 — sie
beschreiben Releases, die wirklich RideBuddy hießen.

Projektübergreifende Guidelines (Architektur, State, Testing, CI, Signing,
In-App-Update/-Feedback) liegen im DocuHub unter
`/Volumes/MacStore/Programming/ProgrammingGuidelineDocuHub/`. Diese Datei
beschreibt, was für MitFahrBar davon abweicht oder zusätzlich gilt.

## Bekannte Abweichungen Konzept ↔ Implementierung

`KONZEPT.md` ist an diesen Stellen überholt — bei Widersprüchen gilt der Code:

- Name „FairFahrt" (§9.1) → das Produkt heißt MitFahrBar.
- `tool/import_xlsx.dart` (Dart-CLI) → umgesetzt wurde `tool/import_seed.py`.
- Postgres-View `person_stats` (§4) → nie gebaut; alle Kennzahlen entstehen
  clientseitig in `lib/core/fairness.dart`.
- Preis-Historisierung mit „Gültig-ab" (§3.4) → `settings` ist nur
  `(group_id, key) → value`, ohne `valid_from`.
- §5.5 ist abgearbeitet: Personen und Fahrzeuge pflegt seit v0.10.0
  `features/persons/persons_screen.dart` (`/persons`), die **Parameter**
  seit v0.33.0 `features/settings/settings_screen.dart` (`/settings`).
- Admin-Screen und Gruppen-Freigabe (§7) → seit v0.38.0 entfernt (#108),
  siehe „Der Gruppen-Lebenszyklus" unten.

## Architektur-Leitplanken (nicht verhandelbar)

- 3 Schichten: `core/` (router, theme, tokens, fairness, log) · `data/`
  (Repositories + `providers.dart`-Registry) · `models/` · `features/<name>/`.
- Die Fairness-/Punktelogik lebt NUR in `lib/core/fairness.dart` und ist durch
  `test/fairness_test.dart` inkl. Excel-Backtest abgesichert. Änderungen an der
  Formel brauchen angepasste Tests UND einen Abgleich mit `KONZEPT.md` 3.2.
- **Die Reihenfolge entscheiden seit 2026-07-21 allein die Punkte**
  (`points_weight = 1.0`, Issue #38). Der kombinierte Rang aus Punkten und
  Fahranteil steckt weiter in `rankPresent` — nur das Gewicht ist gesetzt.
  Das ist bewusst so gebaut: Zurückdrehen heißt, den Parameter zu ändern,
  nicht die Formel. Wer den Fahranteil-Term „aufräumt", nimmt der Gruppe
  diese Rückfahrkarte; `test/fairness_test.dart` nagelt beide Gewichte fest.
  Der Parameter lebt **pro Gruppe in der DB** — eine Änderung der Dart-
  Vorgabe allein erreicht keine bestehende Gruppe, dafür braucht es eine
  Migration (siehe `20260721090000_points_only_ranking.sql`).
- Kennzahlen (Punkte, Quote, km, Ersparnis) werden immer berechnet, nie
  gespeichert.
- **Das Kriterium des Parameter-Screens ist nicht „Kosten", sondern: Der
  Wert darf die Punkte nie berühren** (`features/settings/`, seit v0.33.0,
  Issue #91; umformuliert v0.57.0 mit #139). Drin sind Arbeitsweg und die
  drei Kraftstoffpreise (gehen in Kilometer und Ersparnis ein) sowie die
  festen Vorgaben „Fahrt & Treffpunkt" (gehen nur in Banner und
  Benachrichtigung ein). `one_way_factor` und `points_weight` liegen in
  derselben Tabelle wie die Kosten, gehören aber **nicht** in dieses
  Formular: Sie verschieben rückwirkend die Punkte *aller* — und
  `points_weight` ist die dokumentierte Rückfahrkarte der Fairness-Regel,
  die über eine Migration gesetzt wird, nicht von einem beliebigen
  Mitglied. Weil `saveSettings` immer die ganze Tabelle schreibt, reicht
  der Screen beide Werte über `AppSettings.copyWith` unverändert durch —
  `test/flows/settings_flow_test.dart` nagelt genau das fest, auch am
  zweiten Schreibweg. Wer dort ein Feld ergänzt, prüft zuerst, ob es die
  Punkte berührt.
- **Abfahrtszeiten und Treffpunkt stehen in `group_defaults`, nicht in
  `settings`** (#139, seit v0.57.0). Der Grund ist keine Ordnungsliebe:
  `settings` ist `(group_id, key) → value numeric` und kann einen
  Treffpunkt nicht tragen; eine Uhrzeit als Minutenzahl unterzubringen
  hätte die Hälfte des Problems gelöst und die andere verschleiert.
  - **Die Spalten heißen `outbound_time` / `return_time` — nie
    `departure_time`.** Der Name ist in `notification_prefs` vergeben und
    bedeutet dort das Gegenteil einer Abfahrt: die persönliche Deadline,
    ab der eine Meldung niemanden mehr erreicht. Zwei Bedeutungen unter
    einem Spaltennamen sieht man beim Lesen einer Query nicht.
  - **Keine Zeile / alles NULL = Feature aus**, deshalb kein Seed und kein
    Eintrag in `handle_new_group()`. Eine erfundene Vorgabezeit stünde
    einer Gruppe im Banner, die sie nie gesetzt hat.
  - **Sie stehen im Text, aber NICHT im Digest.** Eine geänderte
    Abfahrtszeit ist eine Parameter-, keine Planänderung — sie verschiebt
    keinen Tag und keinen Fahrer. Nähme `dayDigestFor` sie auf, bekäme
    beim Speichern im Parameter-Screen die halbe Gruppe eine
    „Änderung"-Meldung über einen unveränderten Tag. Dieselbe Linie wie
    „der Digest hängt nicht an den Punkten". Festgenagelt in
    `test/push_digest_test.dart` und `test/push_outbox_test.dart`.
  - **`GroupDefaults` hat bewusst kein `copyWith`**, und `toJson` schreibt
    nicht gesetzte Werte als `null` mit. Sonst wäre eine einmal gesetzte
    Uhrzeit nie wieder loszuwerden: Der Screen baut die Vorgaben beim
    Speichern frisch, der Upsert schreibt immer alle drei Felder.
  - **Tages-Abweichungen sind seit v0.64.0 eigene Werte** (`plan_defaults`,
    #183) — das **revidiert** „Tages-Abweichungen bleiben Anmerkungen"
    (#127, 2026-08-04). Die Absage galt, solange eine Zeit nur Text war;
    seit #164 entscheidet sie, wann das Handy klingelt, und eine Anmerkung
    kann keine Erinnerung verschieben. Im Plan stand „wir fahren um 9",
    geweckt wurde um 7:10 — die Anmerkung war damit nicht bloß schwächer,
    sondern irreführend. Dieselbe Form wie die Spritpreis-Revision. Für
    alles, was weder Zeit noch Ort ist, bleibt die Anmerkung der Weg.
    - **Feldweise aufgelöst, nie objektweise** (`effectiveDefaults`). Ein
      Tag, der nur die Hinfahrt verschiebt, behält die Rückfahrt der
      Gruppe; objektweise ersetzt fiele sie auf `null` und die
      Rückfahrt-Erinnerung entfiele stillschweigend.
    - **Seit v0.75.0 nur noch ZWEI Ebenen: `Auto → Gruppe`** (#211). Von
      v0.66.0 bis v0.74.0 lag dazwischen eine Tages-Ebene
      (`plan_defaults`), begründet mit: „heute fahren alle früher" sei eine
      andere Aussage als „Auto 2 fährt später".
      - **Diese Begründung ist widerlegt, nicht bloß aufgegeben** (Gruppe,
        09.08.2026): „Heute fahren alle früher" ist keine Abweichung, die
        jemand einträgt, sondern die **Folge** davon, dass alle der Abfahrt
        eines Fahrers zustimmen. Zwei Ebenen für eine Aussage sind eine zu
        viel — dieselbe Form wie die Spritpreis- und die Anmerkungs-Revision:
        Der tragende Grund fiel weg, nicht die Regel war von Anfang an falsch.
      - **Damit existiert #206 nicht mehr, statt behoben zu sein.** Bei EINEM
        Auto schrieb der Zeiten-Schirm stillschweigend die Tages-Ebene; weil
        eine Zusage am **Auto** hängt, wurde dann niemand gefragt — und zwar
        am häufigsten Tag überhaupt. Mit nur einer Ebene kann der Fall nicht
        wieder entstehen.
      - **Gelesen wird die Tages-Ebene weiter, geschrieben nicht mehr.**
        `effectiveDefaults` und `outboxEntries` lösen `Auto → Tag → Gruppe`
        unverändert auf, damit Altzeilen nicht stillschweigend ihre Wirkung
        verlieren. Die Tabelle fällt erst in einer späteren Migration — sie
        jetzt zu droppen hieße, etwas zu entfernen, das ein veröffentlichter
        Client liest, und damit die Mindestversion zu heben.
      - **Das ist Schritt 1 von „erweitern → ausliefern → entfernen"**
        (allgemein im DocuHub, `guidelines/datenhaltung.md`). Seit den zwei
        Release-Kanälen (#217) ist der Termin für Schritt 3 präzise
        benennbar: **nach der ersten Beförderung, die den lesenden Client
        stabil macht.** Vorher gedroppt bricht es genau die Leute, die brav
        auf stabil sind — und die Mindestversion hilft dagegen nicht, weil
        der Sperr-Schirm nur anbieten kann, was veröffentlicht ist.
        Kontrolle vor dem Drop: `plan_defaults` hatte am 09.08.2026 noch
        **3 Zeilen** in Produktion (Abfrage-Rezept steht in der Erinnerung
        `supabase-prod-lesen`).
      - **Der eine Preis, ausgesprochen:** Eine Zeit zu setzen schreibt ab
        jetzt IMMER einen Fahrer fest, auch bei einem Auto. „Wir fahren
        früher, wer fährt, sehen wir noch" lässt sich nicht mehr sagen. Das
        ist konsequent zu #183 („die Zeit zu setzen ist die Fahrer-Zusage"),
        aber es ist eine Einschränkung und gehört so in den Changelog.
      - **Geschlüsselt am Fahrer** — `(group_id, plan_date, driver_id)`, der
        Schlüssel von `plan_overrides`. Das ist keine Analogie: Ein Auto
        existiert in der Datenbank **nur** als „diese Person fährt an diesem
        Tag"; die Autos selbst rechnet `planWeek` und speichert sie nie.
      - **Wer für sein Auto eine Zeit setzt, schreibt den Fahrer fest**, und
        zwar den ganzen Satz des Tages. Der Vorschlag kippt, sobald jemand
        seine Verfügbarkeit ändert — die Zeile hinge dann an jemandem, der
        gar nicht mehr fährt. Nur *einen* festzuhalten genügt nicht: Die
        Wahl der übrigen verschiebt auch dieses Auto.
      - **Verwaiste Zeilen bleiben stehen und wirken nicht.** Sie fallen
        beim Auflösen heraus; kommt der Fahrer zurück, gelten sie wieder.
        Ein Aufräum-Trigger müsste den Plan nachrechnen — `planWeek` in SQL,
        genau die zweite Wahrheit, die der Korb vermeidet.
      - **`push_due()` wurde dafür nicht angefasst.** Die wirksame Zeit
        steht seit Stufe A je Person in der Korb-Zeile; zwei Personen
        desselben Tages tragen ab hier verschiedene Zeiten, und der Versand
        merkt davon nichts. Genau dafür war die Spalte da.
      - **Geweckt wird nur, wer im Auto sitzt.** In den Digest geht die für
        *diese Person* anwendbare Abweichung — Auto über Tag verschmolzen,
        nichts sonst. Eine Meldung an den ganzen Tag wäre falsch: Die
        anderen fahren unverändert.
    - **Die Abweichung steht im Digest, die Gruppen-Vorgabe nicht** — und
      genau darin liegt die Trennung: Die Vorgabe ist ein *Parameter*
      (ändern weckt niemanden, sonst meldete der Parameter-Screen der
      halben Gruppe eine Planänderung), die Abweichung eine *Tatsache über
      diesen Tag* (ändern muss wecken). In den Digest gehört nur die
      **Abweichung**, nie die aufgelöste Zeit — sonst käme die Vorgabe
      durch die Hintertür zurück. Beide Hälften sind in
      `test/push_outbox_test.dart` rot verifiziert.
    - **Und nur, wenn es sie wirklich gibt.** Eine leere Abweichung darf
      nichts anhängen: Ein Client von vor v0.64.0 rechnet ohne sie, und
      unterschieden sich die Digests für einen unveränderten Tag, wäre
      jeder Wechsel zwischen beiden Clients eine „Änderung"-Meldung an
      alle Anwesenden. Deshalb schreibt das Repository eine leer gewordene
      Zeile **weg**, statt sie leer stehen zu lassen.
    - **Die wirksame Zeit reist im Ausgangskorb**, nicht in `push_due()`:
      Ab Stufe B hängt sie daran, in welchem Auto jemand sitzt, und das
      weiß nur `planWeek`. Im Versand nachgerechnet wäre es die zweite
      Wahrheit über die Fairness-Regel. Die neuen Spalten stehen deshalb
      **nicht** im Entprell-Vergleich (die `title_out`-Lehre), und
      `group_defaults` wird in `push_due()` seither **left** gejoint — als
      innerer Join verschluckte er den Tag, der eine Zeit trägt, ohne dass
      die Gruppe je eine gesetzt hat.
  - **Ein Tap auf die leere eigene Zelle trägt ein, jeder andere öffnet das
    Menü** (#183, seit v0.64.0). Vorher schaltete jeder Tap eine Stufe
    weiter; mit „fahren wollen" und den Zeiten wären daraus fünf Stufen
    geworden. Der Alltagsfall bleibt damit **ein** Klick, alles Seltene
    kostet zwei.
    - **Eine fremde Zelle öffnet das Menü auch leer.** Vorher hing die
      Vertipper-Bremse aus #121 am Durchschalten; ohne diese Zeile träfe
      ein Fehltipp jemand anderen mit einem einzigen Klick. Der Flow-Test
      dazu **tippt**.
    - **Ohne „Ich bin" zählt jede Zeile als eigene, nicht als fremde.** Wer
      die Startabfrage übersprungen hat, hatte die Rückfrage nie — sie ihm
      jetzt zu geben hieße, ihn dafür zu bestrafen. Im Demo-Modus ist die
      Zuordnung ohnehin aus, dort entstehen die README-Screenshots.
    - **Kein Longpress.** Ohne Affordanz, mit der Maus in der PWA
      Drücken-und-Halten, und ohne Tastatur- oder Screenreader-Weg.
    - **Die Autos eines Tages tragen Farbe UND Nummer** (`AppCarTones`, seit
      v0.65.0). Farbe **je Auto-Platz, nicht je Person**: Gefragt ist „mit
      wem fahre ich *heute*", und Platz-Farben halten die zwei, drei Autos
      eines Tages maximal auseinander — `personLineColor` könnte zwei
      benachbarte Töne nebeneinanderlegen. Der Preis ist bewusst: Dieselbe
      Person trägt in der Statistik eine andere Farbe.
      - **Die Nummer ist kein Beiwerk.** Ohne sie verlöre jeder
        Rot-Grün-Schwache und jeder Graustufen-Screenshot die Zuordnung —
        und ab dem fünften Auto gibt es keine Farbe mehr. Sie steht auch in
        der Screenreader-Beschriftung der Zelle („…, fährt, Auto 2"); genau
        daran hängen die Flow-Tests, nicht an Pixeln.
      - **Erst ab zwei Autos.** Bei einem sitzen alle darin, eine Marke wäre
        Dekoration in einem dichten Raster. Rot verifiziert in **beide**
        Richtungen: Marke ganz weg und Marke auch bei einem Auto.
      - **Vier Töne, nicht zehn**, und je Theme eine eigene Fassung: Für
        beide Untergründe zugleich bliebe nur das schmale Luminanz-Band um
        0,15, und darin liegen Violett und Rosé nicht.
      - **Unterschieden wird über den Farbton, nicht über das
        Kontrastverhältnis.** Das misst Helligkeit — Türkis und Bernstein
        liegen beide bei Luminanz 0,15 und stehen sich mit 1,08:1 gegenüber,
        als Verhältnis gelesen wären sie „gleich". Gefordert sind 60° im
        Farbkreis; die Fläche gegen das Blatt bleibt bei WCAG 3:1, die
        Ziffer darauf bei 4,5:1. Alle drei misst
        `test/banner_contrast_test.dart`.
    - Die Zeit zu setzen ist gleichzeitig die Fahrer-Zusage — sie schreibt
      `plan_overrides`, sonst hinge morgen eine 6:45 an einem Auto, das
      jemand anders fährt. Deshalb erscheint „Ich möchte fahren" nur, wenn
      man nicht ohnehin schon fährt.
      - **Und deshalb steht „Zeiten & Treffpunkt" nur im Menü eines
        Fahrers** (#188, seit v0.66.2). Bis dahin stand der Eintrag in
        JEDER Zelle: Ein Mitfahrer traf damit sein Auto — also ein
        fremdes — und schrieb über `setDrivers` nebenbei den ganzen
        Fahrersatz des Tages fest; wer „kann nicht" stand, kam ebenfalls
        heran. Die Zusage von der anderen Seite gelesen: Wer die Abfahrt
        verantwortet, setzt sie auch.
      - **Das gilt für beide Ebenen des Schirms, auch für den ganzen
        Tag.** Ein Tag ohne Auto hat keine Abfahrt, die man verschieben
        könnte; und `driverIds` trägt auch den *vorgeschlagenen* Fahrer,
        der Weg steht also an jedem Tag offen, an dem überhaupt jemand
        kann. Wer nicht selbst fährt, tippt die Zelle des Fahrers an —
        die Rückfrage aus #121, keine Sperre. Eine Zugriffskontrolle wäre
        es ohnehin nicht: „Ich bin" ist ein Geräte-Merkmal.
      - **Der Geltungsbereich sucht das Auto, das die Person FÄHRT**, nicht
        das, in dem sie sitzt (`indexWhere` auf `driverId` statt
        `carIndexOf`). Genau die andere Frage hat den Mitfahrer an ein
        fremdes Auto gelassen; der zweite Riegel kostet nichts.
      - Rot verifiziert in beide Richtungen: Mitfahrer und Nicht-Mitfahrer
        sehen den Eintrag nicht, **der Fahrer aber schon** — sonst könnte
        niemand mehr eine Zeit setzen. Die Tests **tippen** die Zelle an
        und prüfen erst, dass das Menü überhaupt offen ist; ein reines
        `find` wäre auch bei einem toten Tap grün.
    - **„Ich möchte fahren" trägt ZUERST ein** (v0.66.1, gemeldet am
      07.08.): Der Pin allein verfällt in `planWeek` als tote Auswahl —
      das Übersteuern wirkt nur auf Verfügbare, 1-way schließt Fahren aus.
      Ohne den `setRide(full)`-Schritt davor passiert sichtbar **gar
      nichts**, und genau so ist es durchgerutscht: Kein Test hat den
      Eintrag je angetippt. Seitdem tippt eine ganze Matrix (leer / dabei /
      1-way × Vorschlag / gesetzt) in `test/flows/plan_flow_test.dart`.
    - **Ein Vorschlag wird ersetzt, eine Menschenentscheidung bekommt
      Gesellschaft** (`day.isOverridden` entscheidet — dasselbe Kriterium
      wie das Etikett „von Hand gesetzt"). Auf einem Vorschlags-Tag heißt
      „Ich möchte fahren" „statt dessen" (ein Auto); auf einem gesetzten
      Tag entsteht das **zweite** Auto — sonst spielte der zweite
      Freiwillige Reise nach Jerusalem und entpinnte den ersten still.
      Zwei Freiwillige ohne Mitfahrer sind dann ehrlich zwei Solo-Autos
      und zählen nichts (#61).
    - **Jede Abweichung ist im Planer sichtbar, verwaiste nie** (v0.66.1,
      zweite Meldung vom selben Tag: Eine Auto-Zeit war NIRGENDS zu sehen —
      B1 unfertig ausgeliefert). Tageszeile zeigt das Wirksame („Auto 2:
      hin 06:45"; bei einem Auto ohne Präfix), am Fahrer hängt das Glyph
      (Uhr; nur Ort → Marker) in seiner Auto-Farbe, und es steht in der
      Zell-Semantik („…, andere Zeiten") — daran tippen die Tests. Eine
      Zeile, deren Fahrer nicht fährt, erscheint nicht: Sie wirkt auch
      nicht, und sie zu zeigen wäre der gemeldete Fehler mit umgekehrtem
      Vorzeichen. Das Banner löst bei EINEM Auto dessen Abweichung mit auf;
      bei mehreren nennt es die Tageszeit — zwei Abfahrtszeiten in EINER
      Banner-Zeile wären eine eigene Design-Entscheidung.
      - **Seit v0.66.3 sind es aber mehrere Zeilen** (#189): Ab zwei Autos
        zählt `composeGroupBody` sie einzeln auf („Auto 2: Dora mit Emil
        (hin 06:45)"), jedes mit seinen Mitfahrern und seiner eigenen
        Abweichung. Damit ist die offene Design-Entscheidung beantwortet,
        ohne die Regel zu brechen: Eine Zeile trägt weiter genau eine Zeit.
        Ohne die Abweichung am Auto wäre die Aufzählung der Fehler aus
        v0.66.1 an neuer Stelle — eine Zeile je Auto, die für eines davon
        die falsche Zeit behauptet.
      - **Erst ab zwei**, wie bei den Auto-Marken im Raster: Bei einem Auto
        sitzen ohnehin alle darin, „Auto 1:" wäre eine Unterscheidung ohne
        Unterschied. Das „N Autos" am Ende entfällt dafür — wer „Auto 1"
        und „Auto 2" liest, hat sie gezählt.
      - **Seit v0.66.4 sind es abgesetzte Zeilen mit Auto-Marke** (#189,
        zweite Rückmeldung: „beide Fahrzeuge sind im Banner
        zusammengewurstelt"). Jede Zeile trägt die Farbe und Nummer ihres
        Auto-Platzes — dieselbe Marke wie im Raster, damit man an einem
        Punkt sieht, wo man sitzt.
      - **Die Zeilen haben eine eigene Fläche, und das ist Kontrast, keine
        Optik.** Die Auto-Farben tragen auf dem blanken Verlauf gegen
        dessen helles Ende 1,71:1 (Violett) bis 2,79:1 (Bernstein) — alle
        unter den 3,0:1 einer Grafik. Mit dem Schleier
        (`AppBannerTones.carLineScrim`, Schwarz 40 %) sind es 3,51:1 bis
        9,64:1. **Unterteilen und Farben übernehmen ist dieselbe
        Entscheidung, nicht zwei** — wer die Fläche „aufräumt", macht die
        Marken unsichtbar, und im Bild sieht man das nicht.
      - **Der Schleierwert steht in `tokens.dart`**, nicht im Widget: Der
        Kontrast-Test rechnet mit demselben Wert, mit dem gezeichnet wird.
        Zwei Stellen wären zwei Wahrheiten, und die Rechnung wäre
        stillschweigend ungültig, sobald jemand eine davon senkt.
      - **Das Banner nimmt `AppCarTones.onDark`, nicht `byIndex`.** Der
        Verlauf ist in hell wie dunkel derselbe dunkle Teal, braucht also
        beide Male die hellen Flächen; nach der Theme-Helligkeit gefragt
        käme im hellen Theme dunkel auf dunkel. Die Zuordnung zum Planer
        trägt trotzdem: **Der Farbton ist die Identität, nicht die
        Helligkeit** — Auto 2 ist in beiden Sätzen violett.
      - **Die Abweichung ist ein Chip, kein Wort** (#189): Als farbige
        Schrift ginge es nicht, der Untertitel läuft über das helle
        Verlaufsende. Der Chip bringt seine eigene Fläche mit und trägt
        den Anmerkungs-Akzent — „Ort und Zeitänderung sind Anmerkungen".
        Uhr, sobald eine Zeit abweicht; nur der Ort → Marker, dieselbe
        Regel wie im Planer.
      - **`subtitle` bleibt Pflicht und wird zur Screenreader-
        Beschriftung.** `groupBody` liefert die Teile, `composeGroupBody`
        setzt genau dieselben zum Satz — eine Quelle, zwei Darstellungen.
        Wer die flache Fassung danebenbaut statt daraus, hat zwei
        Wortlaute; und wer nichts sieht, hört sonst zusammenhanglose
        Wortgruppen.
      - **`composeGroupBody` speist nur das Banner**, nicht den Push
        (das ist `composeBody`) und nie den Digest — der Wortlaut darf sich
        hier also ändern, ohne dass jemand eine „Änderung"-Meldung bekommt.
        Der Wortlaut der Abweichung ist trotzdem **derselbe** wie in der
        Tageszeile des Planers (`hin 06:45, zurück 16:20, Ort`): zwei
        Wortlaute für dieselbe Zeile liest man als zwei verschiedene Sachen.
    - **Der Pin ist an der Ablage zu prüfen, nicht am Etikett:** Wer genau
      die vorgeschlagenen Fahrer festschreibt (der Normalfall beim
      Zeit-Setzen), sieht weiter „Vorschlag" — `isOverridden` vergleicht
      Mengen. Sichtbar wird der Pin erst, wenn er etwas festhält; genau
      dafür ist er da.
  - **Die Sitzwahl ist ein Einverständnis, keine freie Auto-Wahl**
    (`plan_seat_choices`, #189 Stufe B2, seit v0.67.0; entschieden 07.08.).
    Der Wunsch hieß „Mitfahrer wählen ihr Auto"; gebaut ist der engere
    Fall, denn der Anlass ist ein anderer: Seit #183 kann ein Fahrer die
    Abfahrt seines Autos verschieben, und wer zu 07:30 zugesagt hat, darf
    nicht stillschweigend auf 05:30 gezogen werden. `accepted=true` ist
    ein **Pin** (dieser Platz, diese Bedingungen), `false` ein
    **Ausschluss** — und der kann ein weiteres Auto erzwingen: „Zu diesen
    Bedingungen nicht" heißt, jemand anderes muss fahren; wer, entscheiden
    exakt die Punkte. Sagt niemand zu, fährt der Spezialfahrer allein.
    - **`terms` ist der Kern, kein Beiwerk.** Gespeichert wird, WOZU
      jemand ja oder nein gesagt hat (`termsOf`, kanonischer Text
      `hh:mm|hh:mm|Ort`; leer = feste Vorgaben). Stimmt er nicht mehr mit
      der aktuellen Abweichung überein, ist die Entscheidung **veraltet
      und wirkt nicht** — eine Zusage ist kein Blankoscheck, und ein Nein
      überlebt die zurückgenommene Abweichung nicht (sonst gäbe es
      dauerhaft zwei Autos wegen einer Zeit, die es nicht mehr gibt).
      Aufgeräumt wird nichts: verwaiste Zeilen wirken nicht, wie bei
      `plan_car_defaults`.
    - **Ein Ausschluss erzwingt ein Auto auch dann, wenn die übrigen nur
      VOLL sind** (seit v0.76.0). Bis dahin endete die Zusatzauto-Schleife,
      sobald für jeden **irgendein** nicht ausgeschlossenes Auto existierte —
      ob dort ein Platz frei ist, fragte niemand. Die Verteilung stopfte die
      Leute anschließend über die Rückfalllinie hinein: Ein Nein bewirkte am
      Ende ein überfülltes Auto statt eines zusätzlichen.
      - **Das ist ausdrücklich NICHT der Fall aus #62.** Dort reichen die
        Sitze des Tages insgesamt nicht, und Überfüllen ist die ehrliche
        Antwort — diese Rückfalllinie bleibt. Hier reichen sie, sie sind nur
        durch Absagen unerreichbar.
      - **Gezählt wird nach Hall:** Wer ausschließlich in eine bestimmte Menge
        Autos darf, muss dort Platz finden; die Fahrer dieser Autos belegen je
        einen Sitz im eigenen. Reicht es nicht, kommt ein Auto dazu — die
        Schleife terminiert, weil jedes zusätzliche Auto die Kapazität erhöht.
      - **Am Soak ändert das nichts, und das ist geprüft**: Er läuft ohne
        Sitz-Entscheidungen, also ohne Ausschlüsse — `excludedBy` ist dort
        leer und die Bedingung fällt auf „alle Autos ausgeschlossen" zurück.
    - **Ein erzwungener Fahrer ist im Umschalter gesperrt, nicht abwählbar**
      (#203, seit v0.70.0; `PlannedDay.forcedFor`). Gemeldet als „das
      Zurücknehmen des zweiten Fahrers wirkt nicht" — es *konnte* nicht
      wirken: Wer abgesagt hat, muss irgendwo sitzen, also setzt `planWeek`
      den Fahrer im selben Atemzug zurück. Der Dialog nahm die Anweisung
      trotzdem an und verwarf sie stumm, die Klasse „toter Knopf" aus
      0.37.0. Drei Dinge daran:
      - **`forcedFor` ist berechnet, nie gespeichert** — wie der
        Fahrer-Vorschlag selbst. Es hält Fahrer → wer ihn braucht, damit am
        Eintrag der Name steht: „wird gebraucht — Bert fährt sonst nicht
        mit". „Ausgegraut" allein sagt nicht, mit wem man reden muss.
      - **Nur Absage-Zwang, nicht Platznot.** Zwei Autos aus Kapazität sind
        eine Kapazitätsfrage und bleiben frei abwählbar; `forcedFor` ist
        dort leer. Beide Richtungen nagelt `test/plan_test.dart` fest.
      - **Der Weg hinaus führt über die Person, nicht über den Planer.** Die
        Absage mit abzuwählen wäre der eine Weg, der nicht in Frage kommt:
        Ein Dritter überstimmte damit still die Entscheidung eines
        Mitfahrers über seine eigene Fahrt — genau das, wogegen #189 gebaut
        wurde. Sagt die Person doch zu (Zell-Menü oder „Mit wem fahren?"),
        verschwindet das Auto von selbst; ist sie nicht mehr verfügbar oder
        ihre Absage veraltet, ebenso. Ein Weg bleibt also immer offen.
      - **Der Spezialfahrer selbst ist davon nicht betroffen**, und das ist
        gemessen: Nimmt man IHN zurück, fallen seine Mitfahrer auf die
        Standardzeit zurück und es entsteht **kein** Ersatzauto — seine
        Abweichung existiert nicht mehr, also auch die Absage dagegen
        nicht. Wer hier „aufräumt" und Entscheidungen löscht, nimmt sich
        die Rückkehr: Kommt er wieder, gelten sie wieder.
    - **Wer zuerst gepinnt hat, bleibt** (`decided_at`). Der Nachrang
      fällt in die automatische Verteilung — nicht aus dem Tag und nicht
      dauerhaft aus dem Wunsch-Auto. `decided_at` geht damit in die
      Plan-Rechnung ein; beim Umschreiben derselben Entscheidung bleibt es
      erhalten, nur neue Bedingungen setzen es neu.
    - **Je Person gilt höchstens EIN Pin, nämlich der zuletzt getroffene**
      (`seatPinsOf`, seit v0.68.0 mit #199). Ohne diese Zeile gewänne die
      **ältere** Zusage: `planWeek` setzt Pins in `decided_at`-Reihenfolge
      und überspringt, wer schon sitzt. Wer sein Auto wechselt, bliebe damit
      im alten — der Tipp täte sichtbar gar nichts, dieselbe Klasse wie der
      tote „Ich möchte fahren"-Pin aus v0.66.1. Aufgeräumt wird auch hier
      nichts: Die überholte Zeile bleibt stehen und greift wieder, wenn die
      neue verfällt.
    - **Ein Mitfahrer sucht sich sein Auto aus** („Mit wem fahren?" im
      Zell-Menü, #199 seit v0.68.0) — der wörtliche Wunsch aus #189, den
      Stufe B2 offengelassen hatte. Bis dahin bestätigte der Pin immer nur
      den Platz, den die Automatik ohnehin vergeben hatte (`carOf`), und
      beide Wege dorthin hingen an einer Abweichung; zwei gleichzeitig
      abfahrende Autos ließen also gar keine Wahl. **Ablage und Rechnung
      konnten es längst** — `planWeek` setzt einen Pin über
      `driverSet.indexOf(pin.driverId)` auf jedes Auto des Tages —, es
      fehlte allein die Oberfläche.
      - **Eine Wahl IST die Zusage**: dieselbe Zeile wie „Passt", mit den
        `terms` des gewählten Autos. Sie veraltet also mit dessen Abfahrt,
        und ein Auto ohne Abweichung trägt leere `terms` wie eh und je.
        Der Ausschluss bleibt bei der Rückfrage — „mit wem fahre ich" ist
        keine Antwort auf eine verschobene Abfahrt.
      - **Ein volles Auto ist gesperrt, nicht überbucht** (entschieden
        08.08.). Ein Pin greift in `planWeek` nur auf einen **freien**
        Platz; angenommen und still verfallen wäre er wieder der tote Tipp.
        Was blockiert, sind die **festen Zusagen** der anderen, nicht die
        automatisch verteilten Mitfahrer — die verteilt der Plan hinterher
        neu, ein Pin läuft davor. Gerechnet wird das in `freeSeatsForPin`,
        damit Schirm und Verteilung dieselbe Antwort geben; zwei Stellen
        sperrten Autos, in die man gekonnt hätte, oder umgekehrt. Der
        Flow-Test **tippt** den gesperrten Eintrag und prüft, dass der
        Dialog offen **bleibt** — ein angenommener, still verfallender Pin
        sähe von außen genauso aus.
      - **„Egal" räumt ALLE Zusagen des Tages weg**, nicht nur die
        wirksame: Bliebe eine ältere stehen, wäre sie ab sofort die neue
        wirksame, und „egal" hätte ein Auto gewählt. `seatChoicesOn` gibt
        dafür eine **Kopie** heraus, nicht die Liste des Notifiers — der
        Aufrufer löscht beim Darüberlaufen, und optimistisch geschrieben
        wird in dieselbe Liste. Auf dem Original ist das ein
        `ConcurrentModificationError`, den der Schirm als „Speichern
        fehlgeschlagen" meldet, **obwohl gespeichert wurde**. Gefunden im
        Browser (`.claude/skills/run-web/`), nachdem die Suite grün war;
        der Flow-Test prüft seither die Meldung mit, nicht nur das
        Ergebnis.
      - **Erst ab zwei Autos und nur für Mitfahrer**, dieselbe Regel wie
        bei den Auto-Marken und bei „Zeiten & Treffpunkt" (#188): Bei einem
        Auto sitzen ohnehin alle darin, und ein Fahrer sitzt in seinem
        eigenen. Wer in **keinem** Auto sitzt (allen abgesagt), behält den
        Eintrag — er ist der Weg zurück.
    - **Gefragt wird am offenen Dialog, nie per Schweigen ein zweites Auto.**
      Die Rückfrage kommt beim Eintragen — dort steht die Person vor dem
      Gerät. Ein nicht beantworteter Push darf den Plan nicht sprengen
      (#180: zugestellt ist nicht angezeigt). Das Nein kostet zwei Taps:
      Zell-Menü → „Dein Auto fährt anders".
      - **Seit v0.70.0 gilt Opt-out: Wer nicht ablehnt, ist zugesagt**
        (entschieden 08.08., `answer ?? true`). Das **revidiert** „Wegtippen
        entscheidet nichts", und zwar auf dieselbe Weise wie die
        Spritpreis- und die Anmerkungs-Revision: Der Grund fiel weg, nicht
        die Regel war falsch. Getragen hatte sie „ein Schweigen darf keinen
        Plan sprengen" — und das gilt weiter, denn Schweigen erzeugt nach
        wie vor **kein zweites Auto**; es hält die Person dort, wo sie
        ohnehin säße. Was daran teuer war, war die leere Ablage: Ohne Zeile
        fand die nachträgliche Rückfrage (#200) nichts Veraltetes und
        **schwieg**, wenn der Fahrer später von 05:30 auf 04:00 ging — die
        Person wurde mitgezogen, ohne je zugestimmt zu haben. Genau der
        Schaden, den #189 verhindern sollte, durch die Hintertür.
        Nebeneffekt, der die Gruppe freut: weniger Autos (Opt-out spart
        CO₂).
      - **Der Dauerschleifen-Merker aus v0.69.0 ist damit entfallen** — und
        zwar weil er *unerreichbar* wurde, nicht weil er störte: Seit jeder
        Ausgang des Dialogs eine gültige Entscheidung ablegt, schweigt die
        Rückfrage von allein. Sein Test konnte nicht mehr rot werden, und
        ein Riegel, der nicht mehr fehlschlagen kann, ist keiner. Bleibt
        der Schreib stecken, wird wieder gefragt — richtig so, beantwortet
        wurde dann nichts.
    - **Und noch einmal, wenn die zugesagte Abfahrt sich verschiebt**
      (#200, seit v0.69.0 — Stufe 2). Die veraltete Zusage wirkt schon
      seit v0.67.0 nicht mehr; was fehlte, war der Anstoß. Beim Ankommen
      im Planer wird neu gefragt.
      - **Keine neue `PushKind`, und das ist der Kern.** Genau dieses
        Ereignis ändert bereits den Digest (die anwendbare Abweichung
        steht darin) und löst die `change`-Meldung aus — eine zweite Art
        wäre eine zweite Nachricht zum selben Vorgang, müsste die
        Empfängerfrage neu beantworten und bräuchte ein Gegenstück zu
        `removedDigest` (das #127-Argument). Gefragt wird stattdessen beim
        **Ankommen**, und das trägt weiter als ein Deep-Link: Es wirkt
        auch, wenn die Meldung nie angezeigt wurde (#180) oder der
        Abend-Blick abgeschaltet ist.
      - **Ein Push-Tipp frischt die Planung auf** (`refreshPlanning`,
        `app.dart`). Die Plan-Provider sind bewusst nicht `autoDispose`;
        wer die App aus dem Hintergrund holt, sah sonst den Stand von
        vorhin — ausgerechnet in dem Moment, in dem eine Meldung sagt,
        dass sich etwas geändert hat, und die Rückfrage könnte gar nicht
        wissen, dass sie fällig ist. Alle vier Ebenen zusammen: Ein halb
        aufgefrischter Plan sähe aktuell aus.
      - **Der Anlass ist die überholte Entscheidung, nicht die
        Abweichung.** Wer nie etwas entschieden hat, wird weiterhin nur
        beim Eintragen gefragt — ihn hier anzusprechen wäre eine neue,
        ungefragte Unterbrechung.
      - **Gegen die Dauerschleife schützt die Ablage, nicht ein Merker im
        Schirm** (seit v0.70.0). v0.69.0 hatte dafür ein `_asked` am
        `_ContentState`; mit dem Opt-out legt jeder Dialog-Ausgang eine
        gültige Entscheidung ab, und `_maybeAskConsent` steigt beim nächsten
        Durchlauf von selbst aus. Wer den Merker wieder einführt, verdeckt
        damit nur, dass das Schreiben nicht ankommt.
      - **Ohne „Ich bin" fragt niemand nach.** Ohne die Geräte-Zuordnung
        (#121) ist nicht bekannt, WESSEN Zusage überholt ist; im
        Demo-Modus ist sie ohnehin aus, dort entstehen die
        README-Screenshots.
      - **Bekannte Grenze:** Die Zusage hängt an der **Auto**-Abweichung.
        Bei nur EINEM Auto schreibt der Zeiten-Schirm bewusst die
        Tages-Ebene (`_editDay`) — dort entsteht also gar keine Zusage und
        folglich auch keine Rückfrage. Wer das ändern will, ändert #189,
        nicht #200.
    - **Seit v0.72.0 sind es DREI Antworten** (#210, `SeatAnswer`): „egal"
      (Vorgabe), „ja unbedingt", „auf keinen Fall". Sie sind **nicht
      symmetrisch**, und die Etiketten verschweigen das fast: Das Nein ist
      eine Bedingung (es kann ein Auto erzwingen), das Ja nur eine
      Bevorzugung — ist das Wunsch-Auto voll, fällt die Person in die normale
      Verteilung, statt ein zweites Sonderzeit-Auto zu erzwingen.
      - **„Egal" wird ABGELEGT, nicht weggelassen.** Als fehlende Zeile
        umgesetzt fände die Rückfrage aus #200 nichts Veraltetes, und wer zu
        06:00 „egal" gesagt hat, würde bei 04:00 stillschweigend mitgezogen —
        genau das Loch, das #200 geschlossen hat.
      - **Die Spalte `answer` ist nullable und hat KEINEN Default**, und das
        ist der Kern der Verträglichkeit: Ein Client von vor v0.72.0 schreibt
        sie nicht, sie bleibt NULL, und der neue liest die Zeile über
        `accepted` — also mit der Bedeutung, die der alte gemeint hat. Mit
        `default 'dontcare'` ginge jede **Ablehnung** eines alten Clients
        verloren, mit `'yes'` würde sie zum Pin auf genau das abgelehnte
        Auto.
      - **`accepted` bleibt als Mitschrift stehen, mit genau EINEM
        Schreiber** (`SeatChoice.accepted` in Dart). Sie auf NULL zu öffnen
        wäre das sauberere Datenmodell gewesen und hätte die Mindestversion
        gehoben; das trifft jede Gruppe, auch die ohne Problem. Wer die
        Ableitung anderswo nachbaut, macht aus der Mitschrift die zweite
        Wahrheit.
    - **Der Schalter steht seit v0.73.0 in der Tageszeile** (#210,
      `_SeatAnswerRow`) — je abweichendem Auto eine Zeile mit „Egal / Ja /
      Nein", darunter ein Satz, was die Wahl bedeutet.
      - **Er ersetzt die Rückfrage nicht, er steht daneben.** Die Rückfrage
        spricht an, wenn sich etwas ändert (#200); der Schalter zeigt
        dauerhaft, was gilt. Nur die Rückfrage hieße, dass man seine eigene
        Entscheidung nirgends nachlesen kann; nur der Schalter hieße, dass
        eine verschobene Abfahrt niemanden mehr erreicht.
      - **Eine veraltete Entscheidung zeigt „Egal"** — genau so behandelt die
        Engine sie. Zeigte der Schalter das alte Ja, behauptete er eine
        Zusage, die nicht mehr gilt, und die Rückfrage widerspräche ihm im
        nächsten Moment.
      - **Nur bei Abweichung, nur für Mitfahrer, nur mit „Ich bin"** — sonst
        zeigte er auf nichts, oder es wäre unklar, wessen Entscheidung
        gemeint ist. Geschrieben wird über `_saveSeatAnswer`, den **einzigen**
        Schreibweg: Zwei Fassungen wären zwei Antworten auf „behält der Pin
        seinen Rang?", und der Unterschied fiele erst am vollen Auto auf.
      - Der Flow-Test setzt eine **hohe Fläche**: Der Schalter steht unter dem
        Raster, und ein Tipp außerhalb des Sichtbereichs trifft ins Leere,
        **ohne zu werfen** — der Test wäre grün gewesen, wenn der Schalter
        gar nichts tut.
    - **Verteilt wird seit v0.72.0 nach KOPFZAHL** (#210): ins Auto mit den
      wenigsten Insassen, erst bei vollem Auto gewinnt ein anderes mit freiem
      Platz. Bis dahin entschieden die meisten freien Plätze — was bei
      ungleich großen Autos gerade nicht gleichmäßig verteilt, weil ein
      7-Sitzer und ein 4-Sitzer mit gleich vielen FREIEN Plätzen enden.
      - **Die Rückfalllinie aus #62 bleibt**: Reichen die Sitze insgesamt
        nicht, wird überfüllt statt jemanden stillschweigend stehen zu
        lassen. Ohne sie verschwänden Leute aus dem Plan, sobald ein Auto zu
        klein ist.
      - **Der Preis ist gemessen — und über zwölf Seeds ein Unentschieden.**
        Die erste Messung (zehn Seeds, eine Kennzahl) sah nach einer
        Verschlechterung aus; mit zwei aus `0xDAC1A` **mutierten** Seeds und
        einer Kontrolle gegen die alte Regel löst sich das auf: Fahrrate im
        Mittel 17,0 → 17,8 ‰, `max|Punkte|` im schlechtesten Fall dagegen
        5,5 → **3,0**. Der schlechteste Fahrraten-Wurf (30 ‰) tritt unter
        **beiden** Regeln auf demselben Seed auf — er gehört zum
        Anwesenheitsmuster, nicht zur Verteilregel.
      - **Die Lehre daraus ist die wichtigere:** Wer aus einer Kennzahl auf
        einem Seed eine Regel-Eigenschaft macht, misst zu schmal. Die
        Schranke steht auf 30 ‰ als struktureller Boden dieser Kalibrierung;
        wer sie anfasst, wiederholt die Kontrolle gegen die andere Regel.
        Zahlen in beiden Nachträgen von
        `doc/entscheidung-mitfahrer-verteilung.md`.
    - **Ohne Entscheidungen rechnet `planWeek` bitgleich wie vorher** —
      per Test festgenagelt. Daran hängt auch der Soak-Report
      (`doc/entscheidung-mitfahrer-verteilung.md`): Er misst die
      **automatische** Verteilung und bleibt dafür gültig; das Verhalten
      unter vielen Pins/Ausschlüssen ist **nicht** gemessen. Wer die
      Zusagen ±2 Punkte/±2 pp auf gepinnte Wochen ausdehnen will, misst
      neu, statt den Report zu zitieren.
    - Der Boden (`tool/notify.dart`) lädt Entscheidungen UND
      Auto-Abweichungen und reicht beide an `planWeek` — ohne sie
      verteilte er die Mitfahrer anders als die App und der Korb trüge je
      nach Schreiber verschiedene Zeiten.
    - Die Rückfrage liest die gemerkte Entscheidung **aus dem
      `WeekPlanNotifier`** (`seatChoiceFor`), nicht aus einem eigenen
      Provider: Dort liegt die Kopie, mit der gerechnet wird, samt der
      optimistischen Schreibvorgänge. Ein zweiter Ladepfad hing beim
      Weiterschalten einen Roundtrip hinterher und fragte genau dann
      doppelt — so gefunden im Flow-Test, bevor es jemand erlebt hat.
- **Die ganze Auto-Zuordnung hat einen Gruppen-Schalter** (#213, seit
  v0.71.0): `settings.car_assignment_enabled` (0/1), im Parameter-Screen.
  Der Grund ist keine Bequemlichkeit: Es gibt **keinen Stable-/Latest-Kanal**
  — ein Merge mit Versions-Bump *ist* die Veröffentlichung und erreicht alle
  Gruppen zugleich. Ein Wert, den die Gruppe selbst umlegt, ist damit der
  einzige Rückweg, der kein neues Release braucht. Er ist die erste Fahne
  dieser Art; das Kriterium des Parameter-Screens hält er ein (er verschiebt
  keine eingetragene Fahrt, nur künftige Vorschläge).
  - **Aus heißt: feste Zeiten für alle.** Keine Abfahrt je Auto, keine
    Zusage, keine Auto-Wahl, und im Push ausschließlich `group_defaults`.
    Die **Autos bleiben** — dass ein voller Tag zwei braucht, ist Kapazität
    (#62) und keine Zuweisung; sie zu verstecken wäre eine Lüge über den Tag.
  - **Der Schalter wirkt an drei Stellen, und jede ist bewusst gewählt:**
    - **`planWeek` liest ihn selbst** aus `settings` und leert `seatChoices`
      und `carDefaults` beim Normalisieren. Nicht bei den Aufrufern gefiltert:
      Es gibt zwei (App und `tool/notify.dart`), und filterte einer nicht,
      verteilte er die Mitfahrer anders — der Korb trüge je nach Schreiber
      verschiedene Zeiten. Weil beide `settings` ohnehin durchreichen, ist die
      Falle hier konstruktiv erledigt.
    - **`outboxEntries` bekommt ihn als Parameter**, weil es dort kein
      `AppSettings` gibt. Vorgabe ist der *bisherige* Zustand (an), damit ein
      vergessener Aufrufer nichts still abschaltet — und genau deshalb prüft
      `test/push_outbox_test.dart` **am Quelltext**, dass beide Schreiber ihn
      übergeben (Bauart wie `test/read_retry_test.dart`).
    - **Die beiden Abweichungs-Provider geben leer zurück.** Das ist der
      Riegel für die ganze Oberfläche an einer Stelle; ohne ihn müsste jede
      Anzeigestelle einzeln fragen, und die eine, die man vergisst, zeigt
      „hin 06:45", während die Erinnerung um 07:30 klingelt — der Fehler aus
      v0.66.1 mit umgekehrtem Vorzeichen. Beim Laden gilt „aus": kurz zu
      wenig zeigen ist besser als kurz das Falsche.
  - **Abgelegte Zeilen werden inert, nie gelöscht** — dieselbe Regel wie bei
    verwaisten Zeilen. Ein Schalter, der Daten wegwirft, wäre kein Rückweg;
    Wiedereinschalten stellt her, was dastand.
  - **Vorgabe aus, aber nur für NEUE Gruppen.** Fehlt die Zeile, gilt aus —
    deshalb seedet `handle_new_group()` sie bewusst nicht (dasselbe Muster
    wie `charging_price_per_kwh` und `e10_price_per_liter`). Bestehende
    Gruppen setzt die Migration ausdrücklich auf 1: Ihnen die Zuordnung per
    neuer Vorgabe zu nehmen wäre ein Entzug, keine Vorgabe.
  - **Die Mindestversion bleibt unangetastet**, und das ist geprüft: Es fällt
    nichts weg, und `saveSettings` ist ein **Upsert je Schlüssel** — ein alter
    Client kennt `car_assignment_enabled` nicht, schreibt ihn also nicht und
    lässt die Zeile stehen. **Bekannte Grenze:** Er zeigt die Zuordnung
    trotzdem und schreibt seine Digests mit Abweichung. Solange der Schalter
    an steht (überall, wo das Feature heute läuft), ist das richtig; schaltet
    eine Gruppe ihn ab, während jemand einen alten Client benutzt, wechseln
    sich die Digests ab und es gäbe „Änderung"-Meldungen. Der Ausweg ist
    „erst alle aktualisieren, dann abschalten" — **nicht** die Mindestversion
    zu heben, denn die träfe auch jede Gruppe, bei der nichts falsch ist.
  - **Der Demo-Modus läuft mit AN** (`FakeCarpoolRepository`), obwohl neue
    Gruppen aus starten. Kein Widerspruch: Dort entstehen die
    README-Screenshots, und mit der Vorgabe „aus" verlören sie
    stillschweigend die Auto-Zeilen und -Marken.
- **Spritpreise kommen seit v0.53.0 doch aus dem Netz — aber genau dort,
  wo die alte Absage sie verortet hatte** (revidiert 2026-08-02, ersetzt
  „holt die App bewusst nicht aus dem Netz" vom 2026-07-24). Der Satz von
  damals endete mit „Wird es je gebaut, ist die Function der Ort — nie der
  Client", und dabei bleibt es: Der API-Schlüssel liegt in
  `supabase secrets` und wird von `supabase/functions/fuel-sample/`
  benutzt. Im Client stünde er in `main.dart.js` lesbar, verstieße gegen
  die Nutzungsbedingungen (die GitHub ausdrücklich nennen) und stürbe am
  Minutenlimit, sobald ein zweites Gerät fragt — das Limit hängt am
  Schlüssel, nicht am Gerät. Was die Absage trug, war die Kosten-Kennzahl
  („ganz grob"); die ist weiterhin **nicht** umgestellt. Gebaut ist die
  Ablage, nicht die Umrechnung.
  - **Ein Wochenwert je Gruppe und Sorte, und das ist das 10. Perzentil.**
    Nicht das Minimum — man tankt nie beim billigsten Anbieter zum
    billigsten Zeitpunkt; im 20-km-Umkreis um Bad Rappenau wandert das
    Minimum um 11 ct, sobald der Kreis wächst, das Perzentil steht still.
    Die Zahl steht an **drei** Stellen (`defaultPercentile` in
    `core/price_series.dart`, `percentile_cont(0.10)` in
    `rollup_fuel_weeks()`, `PERCENTILE` in `tool/import_fuel_history.py`) —
    eine Implementierung ist bei Dart + SQL + Python nicht zu haben, eine
    Definition schon. `test/schema_test.dart` und
    `test/fuel_history_workflow_test.dart` halten alle drei zusammen.
  - **Die Stichzeiten sind UTC, nicht Ortszeit.** `pg_cron` rechnet in UTC
    (`5 5,11,17 * * *`), der Live-Takt tastet im Winter also eine Stunde
    früher ab. Wer den Nachfüll-Lauf auf feste Ortszeiten stellt — der
    naheliegende Griff —, stellt im Winterhalbjahr eine andere Frage als
    die gemessene und baut genau die Stufe an der Naht ein, die das ganze
    Vorgehen vermeiden soll. Festgenagelt gegen die Cron-Zeile.
  - **Konstanten werden nie gespeichert, nur beim Lesen eingesetzt und
    markiert.** Sonst schriebe eine Parameteränderung die Vergangenheit um.
    Dieselbe Linie wie bei Punkten und Quote.
  - **Die Parameter-Konstante erscheint im Diagramm nur, wenn es GAR KEINE
    Messung gibt** (seit v0.54.0). Sobald eine Woche gemessen ist, wird jede
    andere aus Messungen abgeleitet: dazwischen linear überbrückt
    (`PriceOrigin.interpolated`), an den Rändern der nächste bekannte Wert
    gehalten — beides gestrichelt, Legende „nicht gemessen". Grund: Die
    Konstante liegt rund 0,40 € unter dem realen Niveau, und gut ein
    Drittel der Kalenderwochen ist fahrfrei. Jede davon zeichnete einen
    Preissturz, den es nie gab; über 164 Wochen wurde daraus ein Kamm, der
    den Verlauf begrub. Wer den alten Rückfall wiederherstellt, baut genau
    das wieder ein. Ausgelassen werden dürfen Lücken **nicht**: Der Painter
    setzt die Punkte über ihren Index, eine fehlende Woche stauchte also
    den Zeitraum, statt eine Lücke zu zeigen.
  - **Das Zeitfenster des Preis-Screens wächst mit den Daten**
    (`_minWeeks` als Untergrenze). Ein festes Fenster hätte den
    Nachfüll-Lauf unsichtbar gemacht — 164 importierte Wochen bei 26
    gezeigten. Und über einen Jahreswechsel hinweg trägt die Zeitachse die
    **Jahreszahl** (`axisLabels`): „05.06." bis „27.07." liest sich wie
    sieben Wochen. Die Beschriftung liegt bewusst in `price_series.dart`
    und nicht im Painter — auf Canvas gezeichneter Text taucht in keinem
    Widget-Finder auf, im Painter wäre sie ungeprüft.
  - **Der Nachfüll-Lauf nimmt die Datenbank als Warteschlange**
    (`tool/import_fuel_history.py` + `.github/workflows/fuel-history.yml`).
    Der Auftrag ist „Woche mit Fahrt, ohne Zeile in `price_week`" — kein
    Flag, keine Zustandsdatei, dasselbe Muster wie „die Existenz einer
    Zeile in `trips` am Tag *ist* die Bestätigung". Deshalb ist der Deckel
    `--max-weeks` unbedenklich und ein zweiter Lauf automatisch die
    Fortsetzung. Geschrieben wird mit `resolution=ignore-duplicates`: Ein
    Nachfüllen kann einen **gemessenen** Wert nie überschreiben, und der
    ist die genauere Wahrheit über seine Woche.
    Es gibt bewusst **keinen** `schedule:` — der bräuchte zuerst einen
    Merker für Wochen, die das Archiv nie haben wird, sonst zöge der Job
    jede Nacht dieselben sieben Dateien vergeblich. Und die App stößt ihn
    **nicht** an: Das hieße ein Repo-Token in der Datenbank, und das bleibt
    ausgeschlossen.
  - **Zwei Quellen, zwei Lizenzen.** Die Live-API steht unter CC BY 4.0,
    das historische Archiv unter **CC BY-NC-SA 4.0** — nicht dasselbe.
    Nicht-kommerziell passt, SA greift nicht (die Wochenwerte bleiben in
    der Gruppendatenbank), BY steht in README und „Über MitFahrBar". Der
    Archivzugang ist **persönlich** und sein Passwort ist derselbe Wert wie
    der API-Schlüssel: ein Leck öffnet beides.
  - Am Vorgehen ist gemessen, nicht geraten: **alle sieben Tage** einer
    Woche (nur Mo–Do zöge systematisch bis 1 ct nach unten — Fr/Sa sind die
    teuren Tage), **nicht ein Tag je Woche** (±2 ct Rauschen in beide
    Richtungen), **Öffnungszeiten egal** (identische Werte mit und ohne
    Filter). Wer eine dieser drei Abkürzungen nimmt, spart Bandbreite und
    zahlt mit einer Stufe im Diagramm.
- **Personen werden nie gelöscht, nur inaktiv gesetzt.** `person_id` in
  `trip_participations` hängt an `ON DELETE CASCADE` — ein Löschen entfernt
  also stillschweigend alle Teilnahmen dieser Person und verändert damit
  rückwirkend die Punkte *aller anderen*. Deshalb gibt es bewusst kein
  `deletePerson` im Repository. `active: false` ist der Ersatz und wird von
  `activeRankingProvider` und dem Fahrten-Editor respektiert.
- **Ein Name gehört in EINER Gruppe genau einer Person — über Gruppengrenzen
  hinweg dagegen frei** (#109, seit v0.41.0). Bis dahin stand auf
  `persons.name` ein **globaler** `unique (name)` aus der Zeit vor der
  Mandantentrennung: Die zweite Gruppe konnte keine „Anna" anlegen und erfuhr
  an der Fehlermeldung, dass der Name woanders existiert — genau der
  Querverweis, den die RLS sonst unmöglich macht. Drei Dinge daran sind nicht
  beliebig:
  - **Index statt Constraint**, weil normalisiert verglichen wird:
    `lower(btrim(name))`. Das ist **genau** die Abbildung, mit der
    `core/csv_import.dart` Namen auf Personen zuordnet
    (`name.trim().toLowerCase()`). Driftete beides auseinander, fände der
    Import zu einem Namen zwei Zeilen, nähme willkürlich die erste und
    schriebe Fahrten auf die falsche Person.
  - **Inaktive zählen mit** (kein `where active`) — dieselbe Begründung wie
    beim fehlenden `deletePerson`: Wer zurückkommt, wird reaktiviert; eine
    zweite Zeile spaltete seine Punkte-Historie. Der Preis ist eine echt
    andere Anna, die dann „Anna K." heißt; unterscheidbar benennen muss die
    Gruppe sie ohnehin, weil überall nur der Name steht.
  - **Der Screen meldet den Fall, statt ihn zu verschlucken.** Bis v0.41.0
    lief `createPerson` ohne `try` — der Dialog schloss sich, als hätte es
    geklappt, und die Person fehlte einfach (dieselbe Klasse wie der tote
    Update-Knopf). Die Vorprüfung im Screen ist der Komfort, der Index der
    Riegel: Zwei Geräte können gleichzeitig anlegen. Übersetzt wird die
    23505 in `DuplicatePersonName`, damit die Oberfläche keinen
    Postgres-Fehlercode auswerten muss — und das Fake-Backend wirft dieselbe
    Ausnahme, sonst prüfte der Flow-Test einen nachgebauten Pfad.
  Bewiesen wird die Regel am echten Postgres (`test/e2e/rls_e2e_test.dart`),
  nicht im Fake: Ohne die Migration meldet der erste Test dort wortwörtlich
  `duplicate key value violates unique constraint "persons_name_key"`.
- In Screens keine rohen Farb-/Pixelwerte — `core/tokens.dart` bzw.
  `Theme.of(context)` verwenden.
- **Die Banner haben seit v0.47.0 eine eigene Palette neben dem
  `ColorScheme`** (`AppBannerTones`, `AppAccents`, `AppPush` in
  `core/tokens.dart`), übernommen aus `assets/fahrmitbar-design-set/`
  Kapitel 07 und 07b. Das trägt nur, weil die Untergründe der App ohnehin
  die des Design-Sets sind (hell 1,01:1, dunkel 1,03:1 auseinander).
  **Kapitel 06 (Theme-Tokens) ist bewusst NICHT übernommen** — es gibt ein
  anderes `primary` vor als der Seed, dem zu folgen wäre ein Umbau des
  ganzen Erscheinungsbilds. Wer die Palette anfasst, fasst nicht das Theme
  an, und umgekehrt.
  - **Der Verlauf der nächsten Fahrt läuft hell → dunkel, gespiegelt zur
    Vorlage.** Rechts sitzt der Anmerkungs-Zähler; auf dem hellen Teal ist
    der Magenta-Chip mit 1,61:1 unsichtbar. Das Design-Set nennt die Regel
    selbst („nie zwei Akzente im selben Banner") und ist genau daran zu
    spiegeln, nicht zu befolgen. Ebenso entfällt sein heller Endpunkt
    `#22D3EE`: Weiß darauf trägt 1,81:1.
    - **Seit v0.66.3 trägt auch die Sprechblase den Akzent — aber nur mit
      Anmerkung** (#189, entschieden am 07.08.: „Ort und Zeitänderung sind
      Anmerkungen", Chatsymbol in derselben Farbe). Es sind keine zwei
      Akzente: Chip und Blase sagen dieselbe Sache. Leer bleibt sie weiß,
      ein Akzent ohne Anmerkung zeigte auf nichts.
    - **Die Blase hat keine eigene Fläche** — anders als der Chip liegt sie
      frei auf dem Verlauf, und das ist genau die Rechnung, an der Magenta
      hier zweimal gescheitert ist. Sie geht nur am dunklen Ende auf
      (4,06:1 gegen 1,61:1 am hellen). Deshalb steht der Knopf rechts;
      `banner_contrast_test.dart` misst **beide** Enden, das helle
      ausdrücklich als Beleg für die Anordnung.
    - **Im Untertitel geht Magenta deshalb NICHT**, und das ist der Grund,
      warum die Abweichungen dort weiter in der normalen Schrift stehen:
      Der Text läuft über die ganze Breite, also auch über das helle Ende.
      Wer sie hervorheben will, braucht einen Chip mit eigener Fläche —
      farbige Schrift ist dort keine Option, sie sähe im Bild gut aus und
      wäre auf halber Strecke unlesbar.
  - **Jedes Paar wird gemessen, nicht geschätzt** —
    `test/banner_contrast_test.dart`, WCAG 4,5:1 für Text und 3,0:1 für
    Grafik. Bei einem Verlauf **jeder Stopp**, nie ein Mittelwert; genau
    das ließe den hellen Endpunkt wieder durch. Zwei Vorschläge sind an
    dieser Rechnung schon gescheitert, obwohl sie im Bild gut aussahen.
  - Zwei Flächen (`#FFE3D3`, `#3A1608`) stehen **nicht** im Design-Set und
    sind im Code als abgeleitet gekennzeichnet — wer sie dort sucht, sucht
    vergeblich.
- Sicherheit serverseitig (RLS), Auth-Guard im Router (`redirect` +
  `refreshListenable`), nicht nur in der UI.
- **`app_config` ist die einzige Tabelle ohne `group_id`** — und muss die
  einzige bleiben. Sie hält gruppenübergreifende Konfiguration
  (`min_supported_version`, Issue #19), enthält keine Gruppendaten und ist für
  Clients **nur lesbar**: bewusst keine Insert-/Update-Policy, sonst könnte ein
  Client die Mindestversion hochsetzen und alle aussperren. `anon` darf lesen,
  damit der Sperr-Schirm schon vor dem Login greift. `test/schema_test.dart`
  nagelt fest, dass dort nur `select` steht.
- **Die Regel dazu:** Jede Migration, die etwas entfernt oder umbenennt, das
  ein veröffentlichter Client liest, hebt **im selben File** die
  `min_supported_version` auf die Version, die damit umgehen kann. Der Wert
  liegt genau deshalb in der DB und nicht im Repo: So kann er dem Schema nicht
  vorauseilen.
- **Der Sperr-Schirm darf nie zur Falle werden.** `updateRequiredProvider`
  (`data/providers.dart`) sperrt nur, wenn es ein installierbares Update gibt,
  nie bei unbekannter Mindestversion (offline) und nie bei Gleichstand. Damit
  gilt: Der neueste Client kommt immer durch. Wer eine dieser drei Bedingungen
  „aufräumt", baut eine Aussperrung, die nur ein neues Release behebt —
  `test/update_check_test.dart` und `test/flows/update_required_flow_test.dart`
  halten alle drei fest.
  **Vierte Bedingung, seit v0.38.0 und teuer gelernt: Vom Schirm muss ein Weg
  wegführen, und der muss geprüft sein — nicht nur seine Sichtbarkeit.** Der
  Schirm ERSETZT im `builder` der MaterialApp den Router-Navigator; er
  braucht deshalb einen **eigenen** `Navigator` (`app.dart`), sonst findet
  `showDialog` keinen, wirft, Flutter schluckt die Exception und der Knopf tut
  sichtbar nichts. Genau das lief bis 0.37.0 (Pixel 7, 26.07.2026): Es half
  nur Deinstallieren und Neuinstallieren. Im Normalbetrieb fällt es nie auf,
  weil das Update-**Banner** innerhalb des Router-Navigators sitzt — kaputt
  ist nur der Weg, den man ausschließlich im gesperrten Zustand sieht.
  Deshalb steht daneben `openUpdateInBrowser` als zweiter Weg **ohne
  BuildContext**: kein Dialog, kein Navigator, kein Overlay. Wer ihn an eine
  SnackBar, einen Router-Aufruf oder einen Dialog hängt, nimmt ihm den Zweck.
  Der Regressionstest **tippt** beide Knöpfe an; ein Test, der nur `find`
  benutzt, hätte den Ausfall wieder nicht gesehen.
- **Eine Mindestversion ist erst dann berechtigt, wenn der alte Client
  wirklich bricht.** Sie zu heben ist nicht der Normalfall einer Migration,
  sondern der Ausnahmefall: Sie wirft jeden veralteten Client auf den
  Sperr-Schirm, und ein Fix an diesem Schirm erreicht genau die nicht, die
  schon davorstehen — aus diesem Loch kann man sich nicht heraus-releasen.
  Vor dem Heben also prüfen, was der veröffentlichte Client mit dem neuen
  Schema tatsächlich tut. Bei #108 etwa fing `json['is_admin'] as bool? ??
  false` die entfernte Spalte sauber ab, die Selects liefen ins Leere statt in
  Fehler — dort wurde bewusst **nicht** gehoben. Gehoben wird, wenn der Client
  ohne Update falsche Daten zeigt oder in eine Exception läuft.
- **Jedes Gate braucht einen Weg weg — auch das Gruppen-Gate** (#169, seit
  v0.60.0). Dieselbe Lehre wie beim Sperr-Schirm, nur an der anderen Tür:
  `AppShell` zeigte bei `AsyncError` von `myGroupProvider` ein nacktes
  `Text('Fehler: $error')` ohne Rahmen. Ohne Empfang stand dort der rohe
  Ausnahmetext samt Projekt-URL und Gruppen-Kennung — und weil
  `myGroupProvider` an `currentUserIdProvider` hängt (der sich bewusst nur
  bei echtem An-/Abmelden ändert), lief nach der Rückkehr des Netzes von
  allein **nichts** neu: Es half nur, die App zu beenden. Drei Dinge daran
  gehören zusammen und dürfen nicht einzeln „aufgeräumt" werden:
  - **Der Knopf wird im Test getippt, nicht gefunden.** Genau daran ist der
    tote Update-Knopf in 0.37.0 durchgerutscht.
  - **Der Rohtext bleibt vom Schirm.** Er sagt der Gruppe nichts und trägt
    Adressen nach außen; die Fehlersenke (#136) hat ihn ohnehin. Wer ihn
    „zum Debuggen" wieder anzeigt, baut das Leck neu.
  - **Kein Netz ist kein Defekt** und bekommt einen eigenen Text.
    Unterschieden wird über die String-Form (wie bei `isPasswordRecovery`):
    Die Typen kommen aus `http`/`dart:io` und sind im Web-Build nicht
    dieselben.
- **PGRST303 wird wiederholt — aber NUR beim Lesen** (`data/read_retry.dart`,
  #169). PostgREST lehnt eine Anfrage mit `JWT issued at future` ab, wenn das
  `iat` des Tokens vor **seiner** Uhr in der Zukunft liegt; ausgestellt wird
  es von GoTrue, geprüft von PostgREST. Belegt in `error_reports` KW 32: 12
  Vorfälle, Android **und** Web, über mehrere Versionen, und immer im Rudel —
  nach einer Token-Erneuerung feuern alle Provider gleichzeitig.
  - **Gewartet wird, nicht erneuert.** `refreshSession()` ist der
    naheliegende und genau falsche Griff: Es besorgt ein noch jüngeres Token,
    dessen `iat` noch weiter in der Zukunft liegt. Der Fehler heilt allein
    dadurch, dass Zeit vergeht.
  - **Schreibende Aufrufe bleiben ungehüllt.** Ein wiederholtes `createTrip`
    legte die Fahrt zweimal an und verschöbe rückwirkend die Punkte *aller* —
    dieselbe Klasse Schaden wie ein doppelt angelegter Name beim CSV-Import.
    `test/read_retry_test.dart` prüft **beide** Richtungen am Quelltext der
    Datenschicht und ist gegen eine umgehüllte Schreibmethode rot verifiziert.
  - Genau ein zweiter Anlauf, keine Schleife: Sonst würde aus einem sichtbaren
    Fehler ein zähes Hängen.
- **Der Zwischenspeicher hält Zeilen, nie Kennzahlen** (#169, seit v0.61.0;
  `data/offline_cache.dart` und `data/caching_repository.dart`). Ohne Netz liest die App
  den zuletzt geladenen Stand; Punkte, Quote, Ersparnis und der vorgeschlagene
  Fahrer entstehen weiter in `core/fairness.dart` aus genau diesen Zeilen. Läge
  eine berechnete Zahl im Speicher, gäbe es zwei Wahrheiten über dieselbe Woche
  — dieselbe Linie wie „der Fahrer-Vorschlag wird nie gespeichert".
  - **Dekorierer, kein Umbau.** `CachingCarpoolRepository` /
    `CachingGroupRepository` legen sich um die Supabase-Fassungen; Provider und
    Screens wissen nichts davon, und die Fakes der Testsuite laufen daran
    vorbei. Wer die Regel stattdessen in die Provider zöge, verteilte sie auf
    ein Dutzend Stellen.
  - **Nur Lesezugriffe.** Schreiben geht unverändert durch und scheitert ohne
    Netz ehrlich. Ein „später hochschieben"-Korb ist bewusst **nicht** gebaut:
    Er müsste beantworten, was passiert, wenn zwei Leute denselben Tag offline
    unterschiedlich eintragen, und kollidierte mit „die Existenz einer Zeile in
    `trips` *ist* die Bestätigung".
  - **Geschrieben wird nur nach einem erfolgreichen Netz-Lesezugriff.** Ein
    Treffer aus dem Speicher darf seinen eigenen Zeitstempel nicht auffrischen
    — sonst stünde in der Leiste ewig „heute 07:12", auch drei Tage später.
  - **Je Gruppe getrennt, und Fremdes wird beim ersten Lesezugriff gelöscht**
    (`keepOnly`) — die Mandantentrennung der RLS, auf dem Gerät nachgezogen.
    Bewusst am Lesezugriff und nicht an einem Abmelde-Haken: Der liefe nicht,
    wenn jemand die App angemeldet schließt und die nächste Person sich
    anmeldet.
  - **Die Leiste nennt den Zeitpunkt, nicht nur „offline".** Ohne ihn hielte
    man einen alten Plan für den aktuellen und führe zur falschen Zeit los. Sie
    sitzt im `AppShell` über dem Inhalt, nicht in einem Tab — der Stand gilt für
    die ganze App. Und sie hört an einem eigenen Halter statt an einem Provider:
    Die Meldung entsteht, *während* ein Provider lädt; ein Provider-Schreib in
    diesem Moment stieße eine Invalidierung mitten in der Build-Phase an.
  - **Das Preisarchiv ist bewusst draußen** (entschieden 05.08.2026): mit
    Abstand die meisten Zeilen, und ein Diagramm ohne Empfang war der
    schwächste der Wünsche.
- **Multi-Tenant:** Eine Gruppe = ein Login (`group_id = auth.uid()`). Alle
  Datentabellen tragen `group_id` (Default `auth.uid()`), RLS erzwingt
  `group_id = auth.uid() AND my_group_active()`. Neue Gruppen entstehen seit
  v0.37.0 in der Verwalter-Konsole und sind sofort `active`; `pending` gibt es
  nur noch als Ruhezustand für Fremd-Signups gegen die Gruppen-Domain (siehe
  Lebenszyklus unten). Login = Handle → `handle@grp.fahrgemeinschaft.app`
  (`core/group_login.dart`). Neue Datentabellen brauchen zwingend `group_id`
  plus dieselbe RLS-Policy, sonst lecken Daten zwischen Gruppen.
- **Der Gruppen-Lebenszyklus trägt drei Invarianten** (#106, seit v0.37.0).
  Sie sind der Grund, warum das Stilllegen ungenutzter Gruppen später ein Job
  von wenigen Zeilen ist und kein Umbau:
  - **Eine aktive Gruppe hat genau einen Verwalter.** Jede Gruppe entsteht
    verknüpft (Function schreibt `status='active'` UND die
    `group_admins`-Zeile; scheitert der zweite Schritt, wird der Auth-User
    zurückgenommen). Der einzige legitime Ausnahmezustand ist das
    Übergabefenster nach `admin_release_group` — und der ist **markiert**:
    `groups.released_at` wird von einem Trigger auf `group_admins` gesetzt,
    der auch die Kaskade eines gelöschten Verwalter-Kontos fängt. Ohne diesen
    Trigger wäre eine stille Waise von einer laufenden Übergabe nicht zu
    unterscheiden.
  - **Ein unbekannter Status gilt niemals als aktiv.** `Group.statusFrom`
    parst tolerant (`unbekannt → archived`) statt mit `byName`, das **wirft**.
    Wer das zurückdreht, macht jede künftige Statusänderung zu einem
    Release-Zwang: Der Fehler landete in `myGroupProvider`, die Nutzerin sähe
    „Fehler: Invalid argument", und der Sperr-Schirm greift bewusst nie ohne
    installierbares Update. `test/group_status_test.dart` wacht über den
    Parser, `test/flows/auth_flow_test.dart` über die andere Hälfte: dass der
    `archived`-Zweig im `PendingScreen` wirklich **erklärt** statt zu
    scheitern. Ohne diesen Zweig wäre der tolerante Parser wertlos.
  - **Archivieren ist ein Statuswechsel, keine Löschung.**
    `my_group_active()` prüft auf `'active'` — `status='archived'` macht eine
    Gruppe über alle Policies hinweg still, verlustfrei und umkehrbar. Der
    Wert steht deshalb schon im Check-Constraint, obwohl ihn heute nichts
    setzt.
  Vorgesehen, aber **nicht gebaut**: ein Aufräum-Job neben `tool/notify.dart`
  (GitHub Actions, Service-Role-Key, nur Zahlen ins Log). Verwaist = `groups`
  ohne `group_admins`-Zeile (Join, kein Feld nötig), ungenutzt = `trips` /
  `plan_availability` / `auth.users.last_sign_in_at`, das GoTrue von selbst
  pflegt. Bewusst **kein** `last_active_at`: Es müsste vom Client kommen, und
  `groups` hat keine Update-Policy. Ebenfalls benannt und nicht gebaut: Wer
  Postfach UND Passwort verliert, kommt an seine Gruppen nicht mehr heran —
  vorgesehen dafür ist eine **Übernahme mit Widerspruchsfrist**, nicht ein
  zweiter Schlüssel (jedes Mitglied kennt das Gruppenpasswort). Diese Lücke
  darf nicht verschlimmert werden; deshalb überlebt das Verwalter-Konto das
  Löschen einer Gruppe.
- **Es gibt keine Admin-Gruppe und keine Freigabe mehr** (#108, seit v0.38.0).
  Weg sind `groups.is_admin`, `is_group_admin()`, die Update-Policy
  `groups_admin_update`, `features/admin/`, die Route `/admin` und
  `GroupRepository.pendingGroups`/`setStatus`. Der Grund ist kein Aufräumen:
  Die administrative Macht saß auf einem **geteilten** Gruppen-Login ohne
  „Passwort vergessen", und es gab keinen Code-Weg, das Flag zu setzen. Am
  26.07.2026 war eine Freigabe deshalb unmöglich und brauchte Betreiber-SQL.
  Verwaltet wird über das Verwalter-Konto mit echter E-Mail, wo der
  Reset-Weg (#102) funktioniert.
  - **Die Update-Policy auf `groups` kommt nie zurück.** Mit ihr könnte ein
    Client seinen eigenen `status` schreiben, sich also selbst freischalten
    und eine Archivierung zurückdrehen — damit wären **alle** Statuswerte als
    Riegel wertlos, auch der künftige `archived`, und der Aufräum-Job hätte
    keine Wirkung, die hält. Gruppen ändern sich ausschließlich über die
    SECURITY-DEFINER-Funktionen der Konsole und den Service-Role-Key.
    `test/schema_test.dart` prüft die Abwesenheit der Policy,
    `test/e2e/rls_e2e_test.dart` beweist sie am echten Postgres (eine
    pending-Gruppe kann sich nicht selbst aktivieren).
  - **`pending` heißt ab hier „nie in Gebrauch genommen"**, nicht „wartet" —
    es gibt niemanden mehr, der freigibt. Der Zustand entsteht nur noch durch
    ein Fremd-`signUp` gegen die Gruppen-Domain (nicht abstellbar, solange die
    Verwalter-Registrierung offen ist) und bleibt inert. `pending_screen.dart`
    trägt Texte für genau die drei Zustände, die es gibt.
  - **Die Migration ist der Musterfall für Reihenfolge.**
    `handle_new_group()` wird neu geschrieben **vor** dem `drop column` — die
    alte Fassung führt `is_admin` in ihrer Insert-Spaltenliste, fiele die
    Spalte zuerst, scheiterte in diesem Moment **jeder** Signup, auch der
    eines Verwalter-Kontos. Und die Policies fallen vor der Funktion, die sie
    aufrufen, sonst verweigert Postgres das `drop function`. Beides nagelt
    `test/schema_test.dart` als Positionsvergleich fest.
  - Weil eine Migration ihre eigene Entfernung begründet, prüfen solche
    „kommt nicht mehr vor"-Tests den SQL-Code **ohne Kommentare**
    (`sqlOnly` in `test/schema_test.dart`) — sonst scheitern sie an der
    Begründung im File selbst.
- **Gruppen-Konten entstehen nur serverseitig** (seit v0.27.0, Edge Function
  `supabase/functions/request-group/`). Grund: In Production ist die
  Mail-Bestätigung Pflicht (`mailer_autoconfirm` aus — nötig, damit
  Verwalter-Konten ihr Postfach beweisen und „Passwort vergessen"
  funktioniert). Ein Client-`signUp` für eine Gruppe schickte damit eine
  Bestätigungsmail an die unzustellbare Fake-Adresse (Bounce bei Brevo) und
  das Konto bliebe für immer gesperrt. Die Function legt es per Admin-API
  mit `email_confirm: true` an — mail-frei. Drei Fallen: Das Handle-Mapping
  existiert doppelt (Dart in `core/group_login.dart`, TypeScript in der
  Function) und muss synchron bleiben; wer `mailer_autoconfirm` wieder
  einschaltet, nimmt den Verwalter-Konten die Postfach-Verifizierung; und der
  Teststack läuft bewusst mit `enable_confirmations = true` (config.toml),
  damit die E2E-Suite (`test/e2e/auth_mail_e2e_test.dart`) genau diese
  Prod-Wahrheit prüft — genau dieser Config-Drift hat den Fehler ursprünglich
  versteckt.
  Nach jedem Merge, der `supabase/functions/` ändert: prüfen, ob die
  GitHub-Integration die Function deployt hat (sie deployt die in
  config.toml deklarierten), sonst manuell
  `supabase functions deploy request-group`. **Bei diesem Umbau ist das
  release-blockierend:** Neue App plus alte Function heißt, die Anlage läuft
  anonym durch, die Gruppe bleibt `pending` und unverknüpft — eine tote Gruppe.
  **Seit v0.37.0 ruft die Konsole diese Function, authentifiziert** (#106): Der
  Rumpf prüft mit `getUser`, dass ein Verwalter-Konto mit bestätigtem Postfach
  ruft (401 ohne Nutzer, 403 sonst). `verify_jwt = true` allein genügt dafür
  **nicht** — der anon-Key ist selbst ein gültiges JWT; ohne die Prüfung wäre
  der Endpunkt eine offene Gruppenfabrik. Der Deckel liegt bei 5 Gruppen je
  Konto und gilt zweifach: hier als klare Meldung (429) und als Wahrheit im
  Trigger `group_admins_cap`. Damit sind `SIGNUP_HOURLY_CAP` (#69) und die
  vorgemerkte **Cloudflare-Turnstile**-Idee erledigt und ausgebaut — der
  öffentliche Weg, den sie schützen sollten, existiert nicht mehr.
  Der Deckel ist bewusst ein **Trigger** und keine aufrufbare Funktion:
  `alter default privileges` gibt `authenticated` execute auf jede Funktion,
  eine „verknüpfe mich"-Funktion wäre also die Übernahme-Lücke.
- **`group_id` gehört auch in fachliche Primärschlüssel.** Wo der Schlüssel
  keine generierte UUID ist, sondern aus Fachdaten besteht (`plan_date`,
  `person_id`, …), muss `group_id` darin stehen — sonst ist er über alle
  Gruppen eindeutig, und die zweite Gruppe läuft beim Speichern in eine
  Unique-Verletzung auf einer Zeile, die die RLS ihr nicht einmal zeigt.
  Genau so lag `plan_overrides` bis v0.15.0 im Schema. Das Konfliktziel des
  `upsert` im Repository muss denselben Schlüssel nennen; driften beide
  auseinander, meldet Postgres „no unique or exclusion constraint matching
  the ON CONFLICT specification". Beides prüft `test/schema_test.dart`.
- **Eine Gruppe = ein Login bleibt, auch für den Wochenplaner** (entschieden
  2026-07-20). Es gibt bewusst **keine Identität pro Person**: Der Planer ist
  ein Raster Person × Wochentag, in dem jeder für jeden eintragen darf — das
  ist ehrlich zu dem, was ein geteilter Zugang ohnehin bedeutet. Echte Logins
  pro Person würden `group_id = auth.uid()` und damit jede RLS-Policy
  umkrempeln; das ist ein eigenes Projekt, kein Nebeneffekt eines Features.
  - **Die Geräte-Zuordnung „Ich bin" (#121, seit v0.44.0) ist davon keine
    Ausnahme** — sie ist eine **Einstellung dieses Geräts**, kein Login.
    `group_id = auth.uid()` ist unangetastet, keine Policy ändert sich, jeder
    kann jeden wählen und die Auswahl jederzeit ändern (Pärchen tragen
    füreinander ein). Sie schützt vor **Vertippern**, nicht vor Menschen: Ein
    zweites Gerät mit anderer Auswahl bearbeitet weiterhin alles. Wer sie je
    für eine Zugriffskontrolle hält, baut auf Sand — und wer den Planer
    darauf aufbaut, muss den Weg für andere offen lassen.
  - Sie liegt **lokal** (`data/device_identity.dart`), nicht in
    `push_devices`: Dort hinge sie am FCM-Token und gäbe es im Browser ohne
    Push und auf iOS gar nicht — genau dort soll sie aber wirken. Damit
    schreibt `lib/` **erstmals selbst** in SharedPreferences; die Folgen für
    die Android-Backup-Regeln stehen unten.
  - Drei Zustände, nicht zwei: nie gefragt / bewusst übersprungen /
    ausgewählt. Ohne den mittleren käme die Startabfrage bei jedem Start
    wieder. Gemahnt wird an **genau einer** Stelle — dem Banner auf der
    Übersicht, nicht zusätzlich per Dialog.
  - Die Startabfrage hängt an der **Übersicht**, nicht am `builder` der
    MaterialApp: Dort liegen Splash und Sperr-Schirm, und ein `showDialog`
    ohne eigenen Navigator ist genau der Fehler aus 0.37.0.
  - In Tests ist sie über `identityEnabledProvider` standardmäßig **aus**
    (`pumpApp(identity: …)` schaltet sie ein). Grund: `SupabaseConfig
    .isConfigured` ist im Test `true` — der eingecheckte Default ist die
    echte Projekt-URL, erst `--dart-define` auf den Platzhalter schaltet den
    Demo-Modus. Ohne den Schalter träfe jeder Flow-Test zuerst auf Dialog
    oder Banner. Derselbe Handel wie beim Splash, mit demselben Preis: Der
    Standardpfad deckt nur ab, wer ihn einschaltet.
- **Daneben: höchstens EIN Verwalter-Konto je Gruppe** (Issue #55, v0.23.0) —
  echte E-Mail, `account_type: 'admin'` in den Auth-Metadata. Es sieht
  **keine** Gruppendaten (anderer uid, RLS blockt) und kann ausschließlich
  über SECURITY-DEFINER-Funktionen: Gruppenpasswort neu setzen und Gruppe
  löschen (`admin_delete_group` löscht den Gruppen-**Auth-User** — die
  Kaskade nimmt alles mit; nie einzelne Tabellen löschen).
  **Umgekehrt trägt ein Konto seit v0.37.0 bis zu 5 Gruppen** (#106): PK ist
  `(user_id, group_id)`, `group_id unique` bleibt. Jede Aktion nennt deshalb
  ihre `target_group` und prüft das Eigentum — und `admin_delete_group`
  entfernt **genau eine** Zeile in `auth.users`, die der Zielgruppe. Das
  Verwalter-Konto überlebt: Bei mehreren Gruppen wäre ein Selbst-Löschen
  Datenverlust an den übrigen. Die Signaturen wurden dabei **gedroppt und neu
  angelegt**, nicht ersetzt — `create or replace` kann keine Signatur ändern,
  ein Overload hätte bei einem alten Client still die *erste* Gruppe getroffen
  und damit die falsche gelöscht.
  `group_admins` hat bewusst **null Policies**; der Signup-Trigger überspringt
  Admin-Konten, sonst entstehen Geister-„pending"-Gruppen; die
  Erst-Verknüpfung beweist sich mit dem Gruppen-Login und **rastet ein**
  (bis dahin gewinnt das erste Postfach — der Verwalter verknüpft direkt
  nach dem Release). Das Einrasten hat seit v0.29.0 genau EINEN gewollten
  Ausgang: Der aktuelle Verwalter löst die Verknüpfung selbst
  (`admin_release_group`, Sudo-Muster) — danach rastet das nächste Konto
  über den normalen claim-Weg ein; die E-Mail-Adresse wechselt über
  Supabase-Standard (Links an alte UND neue Adresse). Bewusste Grenze:
  Postfach UND Passwort zugleich verloren heißt Betreiber-SQL — jeder
  Selbstbedienungs-Weg daran vorbei wäre die Übernahme-Lücke, die das
  Einrasten verhindert (jedes Mitglied kennt das Gruppenpasswort!). „Passwort ändern" gibt es
  im Gruppen-Menü nicht mehr — nur die Konsole setzt es neu, damit kein
  Mitglied alle aussperrt und der Verwalter jeden Schaden selbst heilt
  (kein Betreiber-Eingriff). Auth-Mails (Reset, Bestätigung) brauchen
  **eigenes SMTP** in Supabase (Brevo Free) — Supabases Standardversand
  liefert nur an Projekt-Teammitglieder. `test/schema_test.dart` nagelt
  alle vier Annahmen fest.
- **Die Konsolen-Mails tragen einen Code, keinen Link** (Issue #102, seit
  v0.35.0) — betrifft „Passwort vergessen" und die Registrierungs-
  Bestätigung. Grund ist kein Geschmack: `resetPasswordForEmail` legt im
  PKCE-Standardflow einen Code-Verifier im Speicher des **anfordernden**
  Geräts ab (`gotrue_client.dart`, `_generatePKCECodeChallenge`) und
  verlangt ihn beim Einlösen wieder. Wer in der Android-App anfordert und
  die Mail im Handy-Browser öffnet — der Normalfall —, hat ihn dort nicht:
  Der Link stirbt still mit „Code verifier could not be found in local
  storage.", und weil das `passwordRecovery`-Ereignis am selben Eintrag
  hängt, erscheint auch kein Dialog. Keine Landeseite kann das heilen.
  `verifyOTP(type: recovery)` ist gerätefrei, braucht weder `redirectTo`
  noch einen `uri_allow_list`-Eintrag. Drei Dinge hängen zusammen und
  dürfen nicht einzeln „aufgeräumt" werden:
  - **Verify und `updateUser` sind EIN Repository-Aufruf**
    (`resetAdminPasswordWithCode`). `verifyOTP` erzeugt eine gültige
    Sitzung, *bevor* das neue Passwort existiert — bliebe es dazwischen
    stehen, wäre jemand angemeldet, ohne sein Passwort zu kennen.
    Scheitert das Ändern, meldet der Screen die Recovery-Sitzung ab.
  - **Der Router filtert `passwordRecovery` aus dem Refresh-Stream**
    (`core/router.dart` + `isPasswordRecovery`). Ohne den Filter risse der
    Redirect „Admin-Sitzung → /console" den Konsolen-Login mitten im
    Zurücksetzen weg. Erst das Ereignis aus `updateUser` lässt herein.
    `test/flows/console_reset_flow_test.dart` wird ohne den Filter rot.
  - **Die Mail-Vorlagen zeigen `{{ .Token }}` und KEINEN
    `{{ .ConfirmationURL }}`.** Bleibt der Link stehen, ist der kaputte Weg
    weiter erreichbar. Wirksam sind die Vorlagen im **Dashboard**
    (Authentication → Emails → Templates → Reset Password / Confirm sign
    up); `supabase/templates/*.html` ist die versionierte Kopie, die
    zugleich den lokalen Teststack versorgt (`config.toml`). **Änderungen
    immer an beiden Stellen.** Weil CI das Dashboard nie sieht, prüft
    `tool/config_drift.sh` beide Prod-Vorlagen täglich — auch darauf, dass
    dort nicht mehr „RideBuddy" steht (bei der Umbenennung übersehen, weil
    Dashboard-Texte in keinem Diff auftauchen).
  Der **E-Mail-Wechsel** bleibt bewusst beim Link: `updateUser` erzeugt
  keinen Verifier, die Bestätigung passiert serverseitig — er ist nicht
  betroffen. Deshalb bleiben `site_url`/`uri_allow_list` nötig.
  Der Rundlauf gegen echtes GoTrue steht in `test/e2e/auth_mail_e2e_test.dart`
  (auch: falscher Code → `otp_expired`); dass die Vorlage keinen Link führt,
  bewacht `firstCode` in `test/e2e/e2e_env.dart` und `mailCode` im
  Browser-E2E. Dasselbe Muster fährt PilzBuddy (pilzbuddy#128).
- **Mehrere Autos je Tag plant der Planer nur, wenn eines nicht reicht**
  (Issue #62). Die Invarianten, in dieser Reihenfolge: `planWeek` bestimmt
  zuerst die **minimale** Autozahl k (die k größten Autos müssen alle
  fassen — ein 7-Sitzer schlägt zwei Kleine), dann entscheiden exakt die
  Punkte, **wer** die k Autos stellt (slotweise die fairness-erste noch
  machbare Teilmenge). Reicht selbst alles zusammen nicht, fahren alle
  Kandidaten — ein Tag ohne Fahrer wäre schlechter als einer mit zu wenig
  Plätzen; diese Rückfalllinie darf nicht wegoptimiert werden. Der
  Fahrer-**Vorschlag** wird nie gespeichert; `plan_overrides` hält eine
  Zeile je von Hand gesetztem Fahrer (PK `group_id, plan_date, driver_id`).
  Die Simulation bucht eine Pseudo-Fahrt **je Auto** — ein Auto ohne
  Mitfahrer ist eine Solo-Fahrt und zählt nichts (#61), genau wie beim
  echten Eintrag. „Eintragen" öffnet den Fahrten-Editor je Auto, fertig
  vorbelegt — gebucht wird erst mit jedem Speichern, nie still; ein
  Abbruch lässt die restlichen Autos ehrlich ungebucht (von Hand
  nachtragen). Sitzplätze speichert `persons.seats` **inklusive Fahrer**
  (Fahrzeugschein), Vorgabe `defaultSeats` = 5 (`not null` in der DB):
  So wirkt die Prüfung ohne Pflegeaufwand; Mitfahrer-Plätze zu speichern
  erzeugte Off-by-one-Fehler, die später niemand mehr erklären kann.
  Festgenagelt in `test/plan_test.dart` und
  `test/flows/plan_flow_test.dart`. Langzeitverhalten (2000-Tage-
  Simulation, `test/plan_soak_test.dart`, Designentscheidung in
  `doc/entscheidung-mitfahrer-verteilung.md`): Punkte konvergieren nur
  **innerhalb** vergleichbarer Autogrößen; bei dauerhaftem Kapazitäts-
  Gefälle driften sie ehrlich, aber unbegrenzt — dokumentierte Grenze,
  keine zu „reparierende" Formel. Auf der realen Zielflotte
  (DaciaRacing-Empirie: 1×4/6×5/1×7 Sitze, große Tage die Ausnahme)
  erfüllt die Automatik Punkte ±2 und Fahrraten im Mittel ±2 pp; der
  Worst-Case ±2,2 pp ist der **Anwesenheits-Boden** (selten Anwesende
  sind eher an großen Tagen dabei und fahren voller), den keine Fahrerwahl
  unterschreiten kann — Zerlegung und Mechanismen-Vergleich im Report. Die Mitfahrer-Verteilung (meiste freie
  Plätze, Gleichstand → bedürftigster Fahrer) bleibt bewusst: Ein
  Anti-Solo-Tie-Break bewegte im A/B-Vergleich eine Fahrt in acht Jahren.
- **1-way im Planer schließt das Fahren aus.** `plan_availability.one_way`
  (Boolean, kein Status-Enum — der Fahrer wird im Plan nie gespeichert) macht
  aus der Verfügbarkeit einen Dreizustand. `planWeek` nimmt 1-way-Personen aus
  den Fahrer-Kandidaten, lässt ein Übersteuern auf sie verfallen und bucht sie
  in der Simulation als `oneWay` — als volle Mitfahrt gebucht rechnete der
  Vorschlag der Folgetage mit doppelten Punkten. Festgenagelt in
  `test/plan_test.dart`.
- **Nichts wird in der Zukunft eingetragen** (entschieden 2026-07-21). Der
  Datumswähler im Fahrten-Editor endet bei heute, der Schnellwahl-Chip heißt
  „Gestern" statt „Morgen", und `_save` bricht bei einem künftigen Datum ab —
  eine ältere Fahrt kann eines tragen. Ein Eintrag im Voraus verschiebt die
  Punkte aller anderen für etwas, das nicht passiert ist; dafür gibt es den
  Wochenplaner. `KONZEPT.md` 5.2 ist an der Stelle überholt und trägt einen
  Korrekturhinweis.
- **Eine eingetragene Fahrt ist im Planer gesperrt** (blass, nicht antippbar)
  und trägt statt „Eintragen" einen andersfarbigen „Bearbeiten"-Knopf, der
  über `PlannedDay.tripId` direkt in den Fahrten-Editor springt. Das Ändern
  einer bestehenden Fahrt fragt nach — es verschiebt die Punkte aller
  Beteiligten rückwirkend.
- **Geplantes darf die Punkte nie berühren.** `plan_availability` und
  `plan_overrides` speichern nur, was Menschen entschieden haben. Der
  vorgeschlagene Fahrer wird **nicht** gespeichert (berechnete Kennzahl, wie
  Punkte und Quote), und es gibt **kein „bestätigt"-Kennzeichen**: Die
  Bestätigung erzeugt eine Zeile in `trips`, deren Existenz am Tag *ist* die
  Bestätigung. Dadurch sieht `computeStats` ausschließlich gefahrene Fahrten.
  Wer hier ein Statusfeld ergänzt, baut sich zwei Wahrheiten.
  - **Eine Ausnahme, seit v0.49.0 und mit Riegel: `push_outbox`** (#132).
    Dort steht der vorgeschlagene Fahrer im Klartext — als fertiger
    Nachrichtentext, damit der Versand ihn nicht ausrechnen muss und
    `planWeek` nicht nach TypeScript wandert. Die Ausnahme ist nur haltbar,
    weil sie **erzwungen** ist und nicht versprochen: Die Tabelle hat **null
    Policies**, ausdrücklich `revoke all` für `anon`/`authenticated` (der
    Sammel-Grant gäbe sonst Rechte auf jede neue Tabelle), und geschrieben
    wird allein über `publish_push_outbox` (SECURITY DEFINER). Der Client
    kann nichts zurücklesen, also kann daraus keine zweite Wahrheit werden;
    `fairness.dart` und `computeStats` sehen die Tabelle nie.
    Wer hier eine SELECT-Policy ergänzt — und sei es „nur zum Debuggen" —,
    macht aus dem Riegel eine Absichtserklärung. `test/schema_test.dart` und
    `test/e2e/push_e2e_test.dart` prüfen beide Hälften.
- **Der Wochenvorschlag simuliert vorwärts** (`planWeek` in
  `core/fairness.dart`): Jeder Tag wird gegen die Statistik *inklusive* der
  bereits vorgeschlagenen Vortage gerechnet. Ohne das ändert sich nichts, bis
  eine Fahrt eingetragen ist — und alle fünf Tage schlagen dieselbe Person
  vor. Tage mit echter Fahrt werden nicht zusätzlich simuliert, sonst zählen
  sie doppelt. Beides ist in `test/plan_test.dart` festgenagelt.
- **Der Planer trimmt die Fahrrate — begrenzt auf ±12 Punkte** (Muster
  entschieden 2026-07-22 mit Deckel 2; auf 6 gehoben 2026-07-24 nach dem
  Zielflotten-Soak, **auf 12 gehoben 2026-08-09**, `suggestPlanDriver`):
  Wer selten fährt, bekommt bei fast gleichem Punktestand eher die kleinen
  Tage, Vielfahrer die vollen — so gleichen sich die Fahranteile an. Das ist
  eine Kaskadenregelung mit begrenzter Autorität: reiner P-Regler auf der
  Raten-Abweichung (bewusst **kein** I-Anteil — die Rate ist selbst ein
  integrierender Zustand, ein Integrator darauf schwänge), Verstärkung
  `kRateBalance` ist zugleich der harte Deckel. Jenseits des Bandes
  entscheiden exakt die Punkte; Dashboard/„Wer ist dran?" (`rankPresent`)
  bleiben unberührt. Wer den Trim „vereinfacht" (Deckel raus, I-Anteil rein,
  auch fürs Dashboard), bricht den Punkte-Vorrang oder baut Schwingen ein —
  `test/plan_test.dart` nagelt Deckel und Zuordnung fest.
  - **Der Hub auf 12 ist an EUREN echten Daten gemessen**, nicht nur
    simuliert: Auf der 401-Tage-Historie halbiert er die Abweichung der
    Stammfahrer vom mittleren Fahranteil (18,7 → 10,6 ‰) und schlägt damit
    auch die von Hand geplante Praxis (14,1 ‰).
  - **Nach oben ist bei 12 Schluss, obwohl 40 minimal besser misst**
    (9,9 ‰). Ab k≈20 kippt die Auslegung: Im Extremfall schickt der Planer
    am **kleinen** Tag den Vielfahrer statt den Wenigfahrer — umgekehrt zur
    Absicht. Grund ist die Δ-Rate: unter Stammfahrern 0,03 (Autorität 1,2
    Punkte), bei unregelmäßiger Teilnahme aber 0,2 (Autorität 8 Punkte), und
    das überstimmt die beobachtete Punkte-Spanne von ±2,5. Die zwei
    Trim-Tests kippen bei 20 und 40, nicht bei 12 — **wer erhöht, sieht sie
    fallen und weiß dann, was er tut.**
  - **Die Soak-Punkte-Schranke durfte auf ±7, blieb aber bei ±5.** Bei 12
    liegt der gemessene Höchstwert bei 3,5; ein Grenzwert, der lockerer ist
    als nötig, fängt nichts mehr. Zahlen in
    `doc/entscheidung-mitfahrer-verteilung.md`, Nachtrag 2026-08-09 (3).
  - **Replays der echten Historie laufen wochenweise, nie tageweise.**
    `dayFactorOf` normiert gegen das Wochenmittel; bei einer Ein-Tages-Woche
    ist `maxDeviation` null, `dayFactor` null — und der Trim fällt komplett
    aus. Ein tageweiser Replay misst also stillschweigend `k = 0` und
    liefert für JEDEN Wert dieselben Zahlen.
- **Der Wochenplan schreibt optimistisch** (`WeekPlanNotifier` in
  `data/providers.dart`): Ein Tap wird lokal eingerechnet und sofort
  gezeigt, der Netz-Schreib läuft hinterher; scheitert er, holt
  `invalidateSelf` die Server-Wahrheit zurück und der Screen meldet es.
  Wer hier wieder „erst speichern, dann neu laden" einbaut, macht aus
  jedem Tap zwei serielle Roundtrips — genau die Trägheit, die 2026-07-22
  behoben wurde.
- **Push-Benachrichtigungen (Issue #101, seit v0.36.0) — vier Dinge, die
  zusammengehören.** Der Versand entscheidet `tool/notify.dart` auf GitHub
  Actions, nicht eine Edge Function: Der Text nennt, **wer morgen fährt**,
  und das ist eine berechnete Kennzahl. `fairness.dart` und `models/` sind
  reines Dart ohne Flutter-Import, der Job importiert also den echten
  `planWeek`. Wer den Entscheider nach TypeScript verschiebt, baut die
  zweite Wahrheit über die Fairness-Regel — und merkt es nicht, solange
  beide zufällig gleich rechnen. Verschickt wird über
  `supabase/functions/send-push/`, damit das FCM-Dienstkonto bei den
  übrigen Server-Geheimnissen bleibt.
  - **`push_log` speichert einen Hash, keinen Plan.** Es ist ein
    Versand-Gedächtnis, keine zweite Wahrheit über den Tag; der
    vorgeschlagene Fahrer bleibt ungespeichert wie bisher. Der feste Wert
    `removedDigest` ist der Trick am Austrag: Wer raus ist, bekommt genau
    **eine** Nachricht, egal wie oft die anderen den Tag noch umbauen.
    Der Digest hängt bewusst **nicht** an den Punkten — sonst löste jede
    eingetragene Fahrt eines Vortages eine Meldung aus.
  - **Die Personen-Zuordnung eines Geräts ist kein Login.** Jeder kann
    jeden wählen, wie im Planer jeder für jeden einträgt. Sie ist eine
    Zustelladresse; `group_id = auth.uid()` bleibt unangetastet. Das Token
    kommt bei jedem Start frisch von FCM und wird serverseitig
    nachgeschlagen — deshalb schreibt `lib/` weiterhin **nichts** in
    SharedPreferences, und die Begründung der Backup-Regeln bleibt gültig.
  - **`push_devices` hat den Token als Primärschlüssel**, nicht
    `(group_id, token)`. Bewusste Ausnahme von der group_id-Regel: FCM-Token
    sind global eindeutig, und ein Gerät gehört zu genau einer Gruppe —
    beim Wechsel muss die alte Zeile weichen, nicht danebenstehen. Deshalb
    läuft die Registrierung über `register_push_device` (SECURITY DEFINER):
    Die alte Zeile liegt unter fremder `group_id`, die RLS zeigt sie nicht,
    ein blanker Upsert liefe in eine Unique-Verletzung auf einer
    unsichtbaren Zeile. `push_log` hat wie `group_admins` **null Policies**.
  - **Ereignisgetrieben, nicht gepollt** (revidiert 2026-07-29, #132 —
    ersetzt „Gepollt, nicht getriggert" vom 26.07.). Die alte Entscheidung
    hatte drei Gründe; zwei sind beantwortet, einer gilt weiter:
    - „Feuert mitten in der Bearbeitung, fünf Taps sind fünf Aufrufe" →
      gelöst durch das Entprellen in der DB (`due_at = now() + 60s`, bei
      jeder Inhaltsänderung neu). **Nicht in der App entprellen:** Ein
      Timer dort stirbt mit dem Tab, und die Änderung wäre still verloren.
    - „Die Function müsste `planWeek` rechnen" → beruhte darauf, *auslösen*,
      *entscheiden* und *senden* für dasselbe zu halten. Den **Text** rechnet
      der Client mit dem echten `planWeek` und legt ihn in `push_outbox` ab;
      die DB entscheidet nur noch *ob* und *wann* (`push_due()` — Fenster,
      Digest, Sperre). Die Fairness-Regel verlässt Dart nie.
    - **Kein Repo-Token in der Datenbank** — gilt unverändert und wird nie
      berührt: Dieser Weg ruft GitHub nicht, sondern `flush-push`.
    Der Auslöser war #115: GitHub verwirft geplante Läufe unter Last und holt
    sie nicht nach (gemessen 15:14, 16:27, 17:38 UTC statt alle zehn
    Minuten). Für den Abend-Blick belanglos, für eine Änderung um 7:05
    fatal — die Meldung kam nach der Abfahrt, also nie.
  - **Die Abfahrts-Erinnerung hat ein EIGENES Fenster** (#164, seit
    v0.58.0). `push_due()` ist deshalb ein `union all` aus zwei Zweigen —
    das ist kein Aufräumen, sondern die einzige Bauform, die trägt: Das
    Plan-Fenster endet an der persönlichen `departure_time` (Vorgabe 7:30),
    die Rückfahrt-Erinnerung um 16:20 läge dahinter und wäre nie fällig
    geworden. Der Erinnerungs-Zweig kennt kein `due_at` und keinen
    Digest-Vergleich; sein Riegel ist der Eintrag in `push_log`
    (`sent.person_id is null`). Ohne ihn feuerte sie in **jedem**
    Minutentakt des Fensters neu — bei 15 Minuten Vorlauf fünfzehnmal.
    Bewiesen am echten Postgres (`test/e2e/push_e2e_test.dart`, gegen die
    Berlin-Uhr), Dart-Spiegel in `dueMessages`.
    - **Deshalb quittiert `flush-push` nur `evening`/`change`.** Liefe
      `due_at = null` nach jedem Versand, verschluckte eine Erinnerung um
      07:15 eine Planänderung, die um 07:14 entprellt wurde: Die Zeile wäre
      erledigt, ohne dass die Änderung je rausging — und der Digest ändert
      sich danach nicht mehr. Dieselbe Klasse wie ein optimistisch
      geschriebenes Protokoll.
    - **`title_out`/`title_return` stehen NICHT im Entprell-Vergleich.** Ein
      Client von vor v0.58.0 schreibt sie als NULL, der Stundenjob gefüllt;
      im Vergleich wechselte der Inhalt zwischen beiden Schreibern hin und
      her und schöbe `due_at` endlos vor sich her — für **alle** Meldungen
      dieser Person. Damit ein Alt-Client eine gefüllte Kopfzeile nicht
      ausleert, hält `publish_push_outbox` sie mit `coalesce` fest; eine
      wirklich entfernte Gruppenzeit macht das nicht rückgängig, denn ohne
      `outbound_time` gibt es kein Fenster.
    - **Seit v0.62.0 hat jede Richtung ihren eigenen Vorlauf** (#168). Die
    ursprüngliche Begründung für den einen Wert („wer morgens fünf Minuten
    braucht, braucht sie abends auch") ist widerlegt: Hin- und Rückweg starten
    nicht am selben Ort. `reminder_lead_minutes` **behält seinen Namen** und
    ist ab hier die Hinfahrt — umbenennen hieße, eine Spalte zu entfernen, die
    ein veröffentlichter Client liest, und damit die Mindestversion zu heben.
    Der Vorlauf reist im `values`-Paar von `push_due()` als vierte Spalte mit
    (`leg.lead_minutes`), damit es bei EINER Rechnung für beide Beine bleibt;
    ein direkter Bezug auf `prefs` an der `make_interval`-Stelle gäbe beiden
    wieder denselben Wert. Im Screen bleibt es bewusst bei **einer** Zeile mit
    beiden Werten — zwei Zeilen wären dieselbe Frage, zweimal gestellt.
  - **Opt-in, Vorgabe AUS** — anders als der Abend-Blick meldet sie sich
      an einem Tag, an dem gar nichts passiert ist. Und sie hängt bewusst
      **nicht** am Abend-Blick (anders als die Änderungs-Meldung): Sie
      braucht keine `push_log`-Zeile als Bezug, nur die Uhr der Gruppe.
    - **`keep_from` darf nie über heute hinauswandern** (#177, seit v0.63.1;
      `outboxKeepFrom` in `core/push_outbox.dart`). Ab Freitagmittag liefert
      `planningWeek` die kommende Woche — richtig für den Planer, verheerend
      als Löschgrenze: `publish_push_outbox` räumt alles vor `keep_from` weg,
      Freitag liegt vor dem nächsten Montag, und die Rückfahrt-Erinnerung um
      16:20 hatte danach keine Zeile mehr. **Der Planer darf vorausblicken,
      der Korb darf nicht den Tag wegwerfen, über den er noch meldet.** Bis
      #164 war das folgenlos: Abend-Blick und Änderung sind mit dem Freitag
      an dessen `departure_time` durch. Eine **Rückfahrt** ist das Erste, was
      die Zeile über den eigenen Mittag hinaus braucht — und die
      Sofort-Meldungen (#163) hingen mit dran, sie reisen als `plan`-Zeilen.
      Die Grenze steht an **einer** Stelle, weil beide Schreiber denselben
      Korb räumen (`data/providers.dart` **und** `tool/notify.dart`).
      - **Das Fake musste dafür erst ehrlich werden.** Es *ersetzte* den Korb,
        die echte Funktion löscht vor `keep_from` und upsertet dann — eine
        Zeile ab `keep_from`, die in den neuen Einträgen fehlt, überlebt dort.
        Gegen das alte Fake wäre der Flow-Test grün gewesen und hätte nichts
        bewiesen. Wer einen Fake baut, spiegelt die Schrittfolge, nicht das
        Ergebnis des Normalfalls.
  - **Ein eingetragener Tag hat seit v0.58.0 den festen Digest `'fix'`**
    (`confirmedDigest`), statt aus dem Korb zu fallen. Vorher ließ
    `outboxEntries` ihn aus, und die alte Zeile blieb mit ihrem Plan-Hash
    stehen — ein Zustand, der zu nichts mehr passte; die Erinnerung braucht
    die Zeile aber gerade dann. Der Wert trägt zwei Riegel: Der Weg **in**
    ihn hinein löst nichts aus (Abend- und Änderungs-Zweig schließen ihn
    aus — sonst bekäme beim Eintragen die halbe Gruppe eine „Änderung"),
    der Weg **heraus** meldet sich (gelöschte Fahrt = wieder Planung). Die
    Erinnerung schließt nur `'raus'` aus, nie `'fix'`. Wer an einem
    bestätigten Tag verfügbar war, aber in keinem Auto steht, bekommt
    `'raus'` — und `composeBody` sagt dasselbe, sonst stünde über einer
    Fahrtbeschreibung die Kopfzeile „Ausgetragen".
  - **Sofort-Meldungen (#163, seit v0.59.0) sind der erste Push ohne
    Fenster** — Ein-/Ausgetragen-Werden durch andere und geänderte oder
    gelöschte Fahrten. Sie hängen deshalb an einem **eigenen** Schalter
    (`instant_enabled`, Vorgabe AN) und nicht am Abend-Blick: Ihn zu koppeln
    hieße, sie genau dann abzuschalten, wenn sie gebraucht werden.
    - **`push_outbox.kind` gehört IN den Primärschlüssel.** Zum selben Tag
      können eine Plan-Zeile und eine Fahrt-Meldung gleichzeitig offen sein;
      ohne die Spalte im Schlüssel überschriebe die eine die andere. Und
      **der Purge in `publish_push_outbox` fasst nur `kind='plan'` an** —
      ohne den Filter nähme der nächste Plan-Schreib jede Meldung über eine
      ältere Fahrt mit, bevor sie eine Minute später rausginge. Dasselbe im
      Stundenjob (`kind=eq.plan`). Der Fehler ist im selben Aufruf unsichtbar
      (der Purge läuft vor dem Insert) — erst der ZWEITE Schreibvorgang
      zeigt ihn, und genau so prüft ihn `test/e2e/push_e2e_test.dart`.
    - **Der Roster-Detektor sitzt im Entprell-Trigger und feuert nur bei
      `tg_op='UPDATE'`.** Die erste Korb-Füllung legt Zeilen für jede Person
      an (neue Gruppe, Wochenwechsel, erstes Gerät); ohne den Riegel weckte
      das die halbe Gruppe. **Der Riegel ist doppelt und die zweite Hälfte
      unsichtbar:** Beim INSERT ist `old` unbelegt, `old.digest <> 'fix'`
      ergibt NULL, die Bedingung wird NULL. Wer sie „null-sicher" macht,
      nimmt diese Hälfte weg — dann trägt `tg_op` allein. Beides zusammen
      ist am echten Postgres rot verifiziert.
    - **`roster_due_at` ist eine zweite Fälligkeit neben `due_at`**, und das
      muss so sein: Der Abend-Blick quittiert `due_at = null`, eine noch
      offene Eintrag-Meldung wäre damit stillschweigend erledigt. `push_log`
      kennt `roster`, aber bewusst **kein** `trip`: Trip-Zeilen werden nach
      dem Versand gelöscht statt quittiert.
    - **Der Fahrt-Diff ist ein Zuhörer** (`core/trip_push.dart` +
      `tripPushSyncProvider`), keine Haken am Editor — dieselbe Begründung
      wie beim Ausgangskorb. Eine **neue** Fahrt meldet niemandem etwas: Das
      Anlegen *ist* die Bestätigung des Tages. Der vorige Stand wird selbst
      gemerkt, nicht aus dem `previous` des Listeners genommen (ein
      `invalidate` schickt den Provider über `AsyncLoading` und feuert
      mehrfach).
    - **Ehrliche Grenze: Trip-Meldungen haben keinen Stundenboden.** Der Job
      kann einen Diff nicht rekonstruieren — stirbt der Tab zwischen
      Speichern und Schreiben, entfällt die Meldung. Dafür räumt er
      liegengebliebene Trip-Zeilen nach sieben Tagen ab.
    - Die Selbst-Unterdrückung (`suppress_roster`) hängt an „Ich bin" und ist
      **best effort, keine Zugriffskontrolle** (#121). Der Stundenjob
      schreibt `false` und überstimmt im Reparaturfall.
  - **Nach jedem Merge, der `supabase/functions/` anfasst, den Deploy
    nachweisen** — und zwar am Bundle-Hash, nicht an der Versionsnummer:
    `supabase functions list --project-ref <ref>` zeigt `ezbr_sha256`. Die
    GitHub-Integration deployt bei **jedem** Push auf `main` alle in
    `config.toml` deklarierten Functions; `version` und `updated_at` bewegen
    sich also auch dann, wenn sich am Code nichts geändert hat. Nur der Hash
    beweist, dass die neue Fassung läuft (belegt am 03.08.2026: flush-push
    v20 `ac1883b6…` → v21 `c55f5f69…`).
  - **`tool/notify.dart` verschickt seit #132 nichts mehr — und seit dem
    30.07.2026 läuft es überhaupt nicht mehr.** Der Workflow
    „Push-Benachrichtigungen" steht auf `disabled_manually` (nachgemessen am
    05.08.2026 bei #175). Gedacht war er als Boden: stündlich den Korb neu
    rechnen und reparieren, was ein Gerät ohne Netz oder ein geschlossener
    Tab hinterlassen hat — „der Ereignis-Weg ist ein Beschleuniger, keine
    Garantie". An dieser Beschreibung stimmten zwei Dinge nicht:
    - **„Stündlich" war er nie.** Die letzten vier Läufe lagen bei 00:12,
      03:32, 06:43 und 09:44 UTC — gut drei Stunden auseinander auf einem
      stündlichen Cron. Das ist derselbe Befund wie #115, der die Umstellung
      überhaupt ausgelöst hat: GitHub verwirft geplante Läufe unter Last und
      holt sie nicht nach. Ein Boden, der alle drei Stunden trägt, ist für
      eine minutengenaue Erinnerung keiner.
    - **Der schnelle Weg trägt allein.** Am 05.08.2026 gingen der
      Abend-Blick und **beide** Abfahrts-Erinnerungen auf die Minute raus —
      sechs Tage nach dem Abschalten. Der Takt kommt aus `pg_cron`
      (`flush-due-push`, `* * * * *`) → `flush_due_push()` → `flush-push`,
      der Inhalt aus dem Client (`pushOutboxSyncProvider`). GitHub steht auf
      keinem dieser beiden Pfade, und die Erinnerung hat diesen Boden nie
      gehabt: Sie kam mit v0.58.0 vier Tage nach dem Abschalten.
    Was ohne den Job wirklich fehlt, ist enger als die alte Zusage klang:
    Schreibt **niemand** den Korb — keine App offen, eine ganze Woche lang —,
    entsteht keine Zeile, und dann meldet sich auch nichts. Solange jemand
    die App öffnet, fällt das nicht auf. **Ob der Job zurückkommt, ist offen**
    (Stand 05.08.2026); zurück käme er ehrlich als „alle paar Stunden", nicht
    als Zusage über Minuten. Wo unten „der Stundenjob" steht, ist das seine
    gebaute Aufgabe — solange er ruht, erledigt sie niemand.
  - **Zustellen ist nicht Anzeigen** (v0.40.0, teuer gelernt). Android und
    der Web-Service-Worker zeigen eine `notification`-Payload **nur an,
    solange die App nicht im Vordergrund ist**. Ist sie vorne, liefert FCM
    sie ausschließlich an `FirebaseMessaging.onMessage` — hörte dort niemand
    zu, verschwand sie spurlos. Das war kein Schönheitsfehler am Test-Knopf:
    Auch der **echte Abend-Versand** verpuffte, wenn jemand die App zufällig
    offen hatte, und weil der Job ihn als zugestellt verbucht und `push_log`
    den Tag als erledigt führt, kam er **nie wieder** (beobachtet
    26.07.2026, 17:14). Der Handler gehört global in `app.dart` an
    `scaffoldMessengerKey` — in einem einzelnen Screen verdrahtet zeigte er
    nichts, sobald man woanders steht.
  - **Der Service-Worker-Pfad ist relativ** (`webServiceWorkerPath`). Das
    FCM-Web-SDK registriert ohne Angabe `/firebase-messaging-sw.js` am
    **Origin-Root**; die App liegt aber unter `/MitFahrBar/`, dort steht 404
    und `getToken` scheitert dauerhaft — die PWA bekam nie ein Token. Ein
    relativer Pfad löst der Browser gegen das `<base href>` auf, das Flutter
    aus `--base-href` setzt; ein absoluter wäre eine zweite Stelle, die mit
    `release.yml` synchron bleiben müsste. `test/push_service_worker_test.dart`
    hält Pfad und Datei zusammen.
  - **Ein Knopf meldet keinen Erfolg, den er nicht geprüft hat.** Die Edge
    Function antwortet auch bei gescheitertem Versand mit 200 und meldet den
    Ausgang je Gerät im Rumpf; `sendTest` wertet ihn aus. Dieselbe Klasse
    Fehler wie der tote Update-Knopf in 0.37.0 — und der Regressionstest
    **tippt**, statt nur zu finden.
  - **Und eine Ebene tiefer: Zugestellt ist nicht Erlaubt** (#180, seit
    v0.63.0). Ein gültiges FCM-Token sagt nichts darüber, ob Android etwas
    **anzeigt**. Am 05.08.2026 stand in `push_log` beides als verschickt, FCM
    hatte `ok` gemeldet, und auf dem Gerät kam nichts an: Die Berechtigung war
    aus (#175). Geprüft wurde sie bis dahin genau einmal — beim Einschalten.
    - **Vier Achsen, die einander nicht ersetzen** (`core/notification_health
      .dart`, reine Auswertung): Berechtigung, Kanal, „Nicht stören", und der
      Akku-Zustand **„Eingeschränkt"** — letzterer unterbindet *jede*
      FCM-Zustellung. Die **normale** Akkuoptimierung tut das nicht:
      `priority: 'high'` weckt aus Doze, und das steht in `send-push` bereits
      richtig. Wer hier „Akkuoptimierung abschalten" empfiehlt, kuriert ein
      Symptom, das es nicht gibt.
    - **Nicht über `firebase_messaging.getNotificationSettings()`.** Das
      meldet auf Android `authorized`, obwohl die Systemeinstellung aus ist
      (flutterfire#4492), und `denied` vor der ersten Frage auf API 34
      (#12839). Darauf gebaut wäre die Überwachung genau so unzuverlässig wie
      der Zustand, den sie aufdecken soll. Gefragt wird Android selbst über
      `MainActivity.kt` — `areNotificationsEnabled()` ist der einzige Aufruf,
      der Berechtigung UND Schalter abbildet; `checkSelfPermission` meldet vor
      Android 13 immer „verweigert".
    - **Unbekannt ist keine Blockade.** Jedes Feld ist `null`, wo die
      Plattform es nicht kennt (Web, ältere Androids), und `fromMap` verträgt
      auch falsche Typen. Ein Schirm, der ohne Wissen warnt, ist Lärm — und
      diese Abfrage ist Diagnose, sie darf den Schirm nie kaputt machen.
    - **Bei jedem `resumed` neu lesen.** Der Ablauf schickt Leute in die
      Systemeinstellungen und erwartet sie zurück; ohne das stünde die alte
      Warnung noch da. Es ist auch der Grund, warum „einmal bei der
      Einrichtung klären" nicht trägt: Android entzieht die Berechtigung nach
      Monaten der Nichtnutzung von selbst und erteilt sie beim Aufwachen
      **nicht** neu.
    - **Der Kanal ist ein Parameter, kein fester Wert.** Bekommt die
      Erinnerung ihren eigenen Kanal (#180 B), ist das eine Ergänzung und
      kein Umbau. „Nicht stören ignorieren" ist eine Eigenschaft des
      **Kanals**: Solange alles auf `plan` liegt, lässt man die Erinnerung
      nur durch, indem man den Abend-Blick gleich mit durchlässt. Und
      `setBypassDnd` wirkt nur mit Policy-Zugriff **und** nur, solange der
      Nutzer den Kanal seit seiner Erstellung nicht angefasst hat — für
      `plan` ist der Zug abgefahren, es **muss** ein neuer Kanal sein.
    - **Wo die App nichts ausrichtet, sagt sie das.** Bei völliger Stille
      (`INTERRUPTION_FILTER_NONE`/`ALARMS`) kommt nichts durch, auch kein
      Ausnahmekanal — diese Karte bekommt bewusst **keinen** Knopf. Ein
      Knopf, der nichts löst, ist ein Versprechen.
    - Der Flow-Test **tippt** den Knopf und ist rot verifiziert; Kanalnamen
      und die Kennung aus `strings.xml` hält `test/android_manifest_test.dart`
      zusammen. Dessen „kommt nicht vor"-Prüfung liest den Dart-Code **ohne
      Kommentare** — dieselbe Lehre wie `sqlOnly`: Ein File, das seine eigene
      Entscheidung begründet, nennt den verbotenen Namen zwangsläufig.
  Push-Texte gehören nie ins Log (sie enthalten Personennamen), und der Job
  loggt nur Zahlen. Festgenagelt in `test/push_digest_test.dart`,
  `test/notify_workflow_test.dart`, `test/schema_test.dart`,
  `test/push_service_worker_test.dart` und
  `test/flows/notifications_flow_test.dart`.
- **Anmerkungen am Plantag heißen `plan_notes` und sind kein Chat**
  (Issue #127, seit v0.46.0; deckt #120 mit ab). Der Wunsch kam zweimal in
  derselben Woche: als „Uhrensymbol für abweichende Zeiten" und als „Chat an
  der Wer-fährt-Kachel" mit dem Beispiel „falls jemand erst ab 9 mitfahren
  kann". Gebaut wurde freier Text — ein Symbol ohne Uhrzeit sagt nichts, mit
  Uhrzeit bräuchte das Raster einen Zeitwähler, wo heute ein Tap steht.
  `KONZEPT.md` §1 („Kein Chat: Kommunikation bleibt in WhatsApp") gilt
  weiter und trägt dort einen Ergänzungshinweis: **kein Thread, keine
  Antwort, kein Gelesen-Status, keine Echtzeit.** Wer den Umfang wachsen
  lässt, kippt die Begründung, mit der das Feature überhaupt entstand.
  - **Die Punkte bleiben unberührt.** `fairness.dart` und `PlannedDay` sehen
    die Anmerkungen nie; `dueMessages`/`dayDigestFor`/`composeBody` bekommen
    sie als eigenen Parameter. Wer sie stattdessen in `PlannedDay` legt,
    bricht „Geplantes darf die Punkte nie berühren" von der anderen Seite.
  - **Der Digest sortiert die Notiz-Kennungen — das ist der Kern, nicht
    Kosmetik.** PostgREST sichert ohne `order` keine Reihenfolge zu;
    ungesortiert unterschiede sich der Hash zwischen zwei Läufen ohne jede
    Datenänderung, und jeder Anwesende bekäme dauerhaft „Änderung"-Meldungen
    über eine Planänderung, die es nie gab. Deshalb **beide** Hälften:
    `order=created_at` in `tool/notify.dart` UND `..sort()` in
    `dayDigestFor`. Der Test dazu wurde scharf gestellt (Sortierung raus →
    rot). Im Digest steht nur die Kennung, nicht der Text: Es gibt kein
    Bearbeiten.
  - **Keine eigene `PushKind`** — die Anmerkung reist als `change` mit. Eine
    eigene Art müsste die Empfängerfrage neu beantworten und bräuchte ein
    Gegenstück zu `removedDigest`, sonst bekäme ein Ausgetragener weiter
    Meldungen. Der Preis ist ausgesprochen statt still: Wer den Abend-Blick
    abschaltet, bekommt auch keine Anmerkungs-Meldung — der
    Benachrichtigungs-Screen sagt das.
  - **Der Verfasser ist ein Feld, keine Sperre.** Eine Schreibsperre an
    `myPersonProvider` wäre doppelt falsch: Sie hielte die Geräte-Zuordnung
    für eine Zugriffskontrolle (siehe #121), und weil
    `identityEnabledProvider` im Demo-Modus **aus** ist, stellte sie den
    Schirm genau dort tot, wo die README-Screenshots entstehen. Löschen darf
    jeder — Vertipper-Schutz, keine Zugriffskontrolle.
  - **Der Text steht im Push, nicht nur ein Zähler.** Als das entschieden
    wurde, kam die Meldung real erst nach ~70 Minuten (#115) — eine späte
    Meldung, die nur „1 Anmerkung" sagt, wäre zweimal wertlos gewesen. Seit
    #132 ist sie binnen einer Minute da; die Begründung trägt trotzdem
    weiter, denn ein Zähler ohne Text zwingt immer zum Nachsehen. Gekürzt
    wie die Namensliste.
    Der Text darf **nie** ins Log — dieselbe Regel wie beim Einladungstext,
    auch im Fehlerpfad (Meldungen ohne Fehlertext).
  Festgenagelt in `test/push_digest_test.dart`, `test/schema_test.dart`,
  `test/notify_workflow_test.dart`, `test/flows/notes_flow_test.dart`,
  `test/flows/banner_flow_test.dart` und `test/e2e/rls_e2e_test.dart`.
- Kein `print` in `lib/` — zentraler Logger `core/log.dart`.
- **Der Einladungstext darf nie ins Log.** „Jemanden einladen"
  (`features/invite/`) kann auf Wunsch das **Gruppenpasswort** enthalten —
  bewusste Entscheidung, damit eine Einladung ein Schritt bleibt. Deshalb:
  nicht speichern, nicht loggen, und im Fehlerfall **ohne** den Fehlertext
  melden (der trägt sonst die Nachricht mit). Käme der Text in `logRing`,
  stünde der Gruppenzugang im nächsten öffentlichen Feedback-Issue.
  `test/flows/invite_flow_test.dart` prüft genau das am Fehlerpfad.
- **Was geloggt wird, kann öffentlich werden.** `core/log.dart` hält die
  letzten 50 Zeilen in `logRing` (nur im Speicher, nie auf Platte), und die
  Nutzerin kann sie einer Rückmeldung anhängen — die der Feedback-Bot in ein
  **öffentliches** GitHub-Issue verwandelt. Deshalb gehören in `log`-Aufrufe
  niemals Personennamen, Handles oder Fahrtdaten. Der Anhang ist bewusst
  standardmäßig abgewählt und wird vor dem Senden im Klartext angezeigt.
  Absichtlich kein Sentry: eine Gruppe von wenigen Leuten, die den Betreiber
  kennt, braucht keine Fremd-Pipeline (Issue #18).
- Nach jedem `await` in Widgets `mounted`/`context.mounted` prüfen.
- Server-/App-State in Riverpod-Providern, Formular-State in StatefulWidgets.
- **Riverpod 2 (kein Codegen)** — bewusst gepinnt. Unter 3.x pausiert/resumed
  Riverpod Subscriptions beim Seitenwechsel und stößt dabei Provider-
  Invalidierungen mitten in der Build-Phase an („setState during build").
- **Daten-Provider hängen an `currentUserIdProvider`**, nie direkt am
  Auth-Event-Stream: Sonst lädt bei jedem Ereignis (auch Token-Refresh)
  alles neu und invalidiert im schlechtesten Moment.
- Tests: `test/fakes/` enthält ein In-Memory-Backend, das die Mandanten-
  trennung nachbildet; `pumpApp` startet die echte App dagegen. Neue Abläufe
  bekommen einen Flow-Test in `test/flows/`. Netzzugriffe (Update-Check) in
  Tests immer per Override stilllegen.
- **Release-only-Fallen bekommen einen Konfigurations-Regressionstest.**
  `test/android_manifest_test.dart` prüft INTERNET-Permission,
  `REQUEST_INSTALL_PACKAGES`, die `<queries>`-Sichtbarkeit, die exakte
  FileProvider-Authority, `filepaths.xml` und die Desugaring-Flags. Solche
  Fehler kompilieren sauber und fallen sonst erst auf dem Gerät des Nutzers
  auf. Jede neue Manifest-/Gradle-Voraussetzung kommt dort mit einer
  `reason:` dazu, die den echten Ausfall beschreibt.
  `test/release_workflow_test.dart` gehört zur selben Klasse: Er hält die
  APK-Namen in `release.yml` zusammen (cp-Ziel, upload-Pfad,
  Release-Dateiliste). Genau daran riss der v0.34.1-Lauf NACH dem Taggen
  ab — übrig blieb ein Tag ohne Release, den die Tag-Entscheidung fortan
  als „schon veröffentlicht" wertete; heilbar nur von Hand (Tag löschen,
  Fix mergen, der Push released neu). Grün in jeder PR-CI heißt bei
  release.yml nichts: Der APK-Pfad läuft nur im echten Release.
- Charts sind **bewusst selbst gebaut** (`core/chart_data.dart` = reine
  Aggregationsfunktionen, `core/widgets/charts.dart` = CustomPainter) —
  keine Chart-Library als Dependency. Aggregation bleibt testbar getrennt
  vom Zeichnen (`test/chart_data_test.dart`).
- **Die Statistik-Seite ist seit v0.56.0 die Chart-Seite** (Design-Konzept
  „MitFahrBar Statistik Konzept" im Claude-Design-Projekt
  `63ffe2c1-977d-4d77-acc3-50cc83e3a57a`; das Dashboard blieb bewusst
  unverändert — Übersicht kompakt, Statistik tief). Pure Schicht in
  `core/stats_data.dart` + `core/stats_insights.dart`. Vier Entscheidungen
  daran sind nicht beliebig:
  - **Der Rekord bleibt ehrlich:** `weeklyTripBars` rechnet die Rekordwoche
    über die ganze Historie. Liegt sie vor dem 12-Wochen-Fenster, wird KEIN
    Balken markiert — der höchste Balken im Ausschnitt wäre nicht der
    Rekord, ihn einzufärben behauptete es; der Untertitel nennt sie. Und
    Zukunfts-Fahrten zählen nicht (dieselbe Lehre wie #160).
  - **CO₂ nur aus echten Angaben** (entschieden 2026-08-03): je Person
    Verbrauch × kg/l ihrer Spritart (Diesel 2,65, Benzin 2,37), E-Autos
    zählen 0 — exakt die Form von `savedCostsFor`, keine kg/km-Pauschale.
    Konstanten beim Lesen eingesetzt, nie gespeichert.
  - **Der Ersparnis-Ring summiert sichtbar zur Kachel-Zahl:** Die Mitte ist
    `chart.total` (dieselbe Quelle wie die Übersicht), ein Übertrag bekommt
    ein eigenes neutrales Segment in `outline` — `outlineVariant` sähe
    besser aus, trägt gemessen aber nur 1,53:1 und wäre unsichtbar; der
    Ring summierte dann sichtbar falsch. Personen-Farben kommen aus
    `personLineColor` über `savingsOrder` — dieselbe Person trägt in Linie
    und Ring EINE Farbe.
  - **„Fahrten pro Woche" und CO₂ hängen NICHT am Preisarchiv**
    (`weeklyTripBarsProvider` bzw. reine `stats`-Rechnung): Sie dürfen
    nicht mit dem Preisabruf verschwinden — genau dafür sind sie eigene
    Aggregationen statt Ableger von `SavingsChart`.
  Alle neuen Farbpaare sind gemessen (`test/stats_contrast_test.dart`): Die
  Insight-Karten holen den einst abgelehnten Verlaufs-Endpunkt `#22D3EE`
  legal zurück (dunkle Marken-Tinte statt Weiß darauf), und die
  Heatmap-Skala endet bei VOLLER Deckung (Restdeckung 0,9 fiele hell mit
  2,94:1 durch). Die Preis-Verläufe stehen als Sektion auf `/stats` über
  das geteilte Widget `PriceHistoryCharts`; die Verwaltung (Region, Abruf)
  bleibt auf `/prices`.

## Workflow

- **Kein direkter Push auf `main`** (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge.
- **Zwei Kanäle seit v0.76.0 (#217): jeder Merge baut, aber nur eine
  Beförderung veröffentlicht.**
  - Ein Merge mit Bump erzeugt Tag, APK und ein **Prerelease**. Die Gruppe
    sieht davon **nichts**: `update_check.dart` fragt `/releases/latest` ab,
    und GitHub liefert dort grundsätzlich keine Prereleases — weder den
    Hinweis noch das APK fürs In-App-Update.
  - **`prerelease: true` UND `make_latest: false` gehören zusammen.** Ohne
    die zweite Zeile setzt GitHub das neueste Release trotzdem als „latest",
    und die ganze Trennung wäre wirkungslos.
  - Freigegeben wird von Hand über den Workflow **Promote** (gedacht alle
    zwei bis drei Wochen). Er schaltet das Release stabil, setzt die
    **gesammelten** CHANGELOG-Abschnitte seit dem letzten stabilen Stand als
    Notizen ein und deployt Pages **aus dem beförderten Tag**.
  - **GitHub Pages hängt am stabilen Kanal, nicht an `main`.** Das Web hat
    eine einzige URL; deployte weiter jeder Merge, bekäme die PWA jede
    Zwischenversion und die Trennung gälte nur für Android. Der Preis ist
    gewollt: Zwischen zwei Beförderungen steht auf der Web-Adresse der
    stabile Stand.
  - Wer den neuesten Stand testen will, lädt das Prerelease-APK von der
    Releases-Seite — der In-App-Weg führt bewusst nur zu stabilen Ständen.
  - **`min_supported_version` darf nie über den STABILEN Stand steigen**,
    sonst sperrt der Schirm genau die aus, die auf stabil sind.
  - Festgenagelt in `test/release_workflow_test.dart`: Die Riegel sind je
    eine Zeile YAML, und ihr Verlust fällt sonst erst auf, wenn die Gruppe
    wieder mehrmals täglich einen Hinweis bekommt.
- **Wer mergen darf, entscheidet weiterhin der Versions-Bump:**
  - **Ohne Bump** (nur `*.md`, `.github/`, `test/`, `tool/`, `LICENSE`):
    Claude darf nach grüner CI selbst squash-mergen.
  - **Mit Bump**: **Der Merge gehört dem Menschen.** Die ursprüngliche
    Begründung („der Merge ist die Veröffentlichung") gilt seit den zwei
    Kanälen allerdings nicht mehr — ein Merge erreicht die Gruppe nicht,
    veröffentlicht wird erst mit der Beförderung. Ob die Regel deshalb
    gelockert wird, ist **Marcus' Entscheidung** und hier bewusst offen
    gelassen, statt sie stillschweigend nachzuziehen.
- Commit-/PR-Titel: Conventional Commits. GitHub-Kommunikation Englisch,
  UI-Strings und Nutzer-Doku Deutsch.
- Release = Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen,
  z. B. `0.2.0+3`). Der Release-Workflow taggt `v<version>` und baut das APK.
  Kein Bump = kein Release.
- Version Guard in CI: Code-Änderung ohne Versions-Bump blockiert den Merge.
  Ausgenommen sind `*.md`, `.github/`, `test/`, `tool/` und `LICENSE` — reine
  Doku-, CI-, Test- oder Tooling-Arbeit soll kein Release auslösen.
- **Zu jedem Versions-Bump gehört ein `CHANGELOG.md`-Eintrag** (Nutzersicht,
  Deutsch: was ändert sich für die Gruppen — nicht die Commit-Liste).
- Flutter-Version in CI gepinnt (3.44.8) — bei lokalem Upgrade auch
  `.github/workflows/*.yml` anpassen. Lokales SDK:
  `/Volumes/MacStore/Programming/Flutter/SDK/flutter`.
  **Es sind SECHS Dateien** (`ci`, `release`, `notify`, `screenshots`,
  `security`, `usage-report`), und alle sechs halten den Wert jetzt als
  `env: FLUTTER_VERSION`. In `security.yml` stand er bis 08.08. als Literal
  am Job — genau so entsteht ein halber Drift: Wer nach dem Muster der
  anderen fünf sucht, findet die sechste nicht. Am 08.08. war der Abstand
  auf drei Minor angewachsen (lokal 3.44.8, CI 3.41.2); getestet wurde
  damit auf einer anderen Toolchain als ausgeliefert. **Der Pin ist
  release-frei** (`.github/` steht in den Guard-Ausnahmen) — er kostet also
  nichts außer dem Nachziehen, und liegen zu bleiben ist der eigentliche
  Preis. Der `android/gradle.properties`-Migrator hängt daran: Auf der
  neueren Toolchain schreibt `flutter build` dort
  `android.builtInKotlin=false` und `android.newDsl=false` zurück, sobald
  sie fehlen.
- **Zum Ausprobieren in der echten App:** `.claude/skills/run-web/SKILL.md`
  (Demo-Build → lokal ausliefern → Playwright). Flutter-Web zeichnet auf
  Canvas, es gibt also keinen DOM-Text — geprüft wird über Screenshots, die
  man sich ansieht. Hat mehrfach Fehler gefunden, die alle Tests durchgelassen
  hatten: den globalen Schlüssel in `plan_overrides`, „Noch niemand verfügbar"
  trotz eingetragener 1-way-Person und einen Datei-Dialog, der an einem alten
  Plugin-Registrant scheiterte. Automatisiert existiert derselbe Ansatz als
  Browser-E2E der Konsole (`tool/browser_e2e.sh`, CI-Job „Browser E2E
  (Konsole)", Details in `doc/testbackend.md`).
- **Vor jedem Push `dart format .` laufen lassen.** Die CI prüft mit
  `--set-exit-if-changed` und wird sonst rot — der häufigste vermeidbare
  Fehlschlag. Danach `flutter analyze` und `flutter test`.
- **Die Required Checks hängen an den `name:`-Feldern der CI-Jobs**
  („Analyze & Test", „Build Web", „Build Android APK", „Version Guard").
  Wird ein Job umbenannt, greift die Branch Protection stillschweigend nicht
  mehr — Umbenennung immer zusammen mit den Repo-Einstellungen.

## Technik-Notizen

- Supabase-Zugang: `lib/core/supabase_config.dart`. Solange dort Platzhalter
  stehen, läuft die App im Demo-Modus (In-Memory-Daten, kein Login). Der
  Publishable-Key ist bewusst öffentlich; NIEMALS den service_role-Key
  einchecken.
- DB-Änderungen: Supabase ist per GitHub-Integration mit dem Repo verbunden —
  neue Migration als `supabase/migrations/<YYYYMMDDHHMMSS>_<name>.sql` anlegen,
  sie wird bei Push auf `main` automatisch eingespielt (kein manuelles
  Patchen). `supabase/schema.sql` bleibt das gepflegte Gesamtbild (Doku).
- Repo: `github.com/MacBuchi/MitFahrBar`, Default-Branch `main`.
  Web-Builds für Pages brauchen `--base-href /MitFahrBar/`
  (Groß-F, case-sensitiv!) und eine `404.html` (Kopie von `index.html`)
  als SPA-Fallback. Live-URL: `https://macbuchi.github.io/MitFahrBar/`
- Echte Namen/Daten der Gruppe liegen NUR in `.donotsync/` (gitignored):
  `Fahrgemeinschaft.xlsx` (Original) und `seed/seed.json` (extrahiert).
  Einmal-Import in eine leere DB: `tool/import_seed.py`. Der Excel-Backtest
  in `test/fairness_test.dart` überspringt sich selbst, wenn `seed.json`
  fehlt (z. B. in CI).
- Status-Werte in der DB: `driver` / `passenger` / `one_way`
  (Dart-Enum `ParticipationStatus.driver/passenger/oneWay`).
- **Android:** Bundle-ID `de.macbuchi.mitfahrbar` — mit v0.34.0 von
  `de.macbuchi.fahrgemeinschaft` umgezogen (Issue #87). Android sieht darin
  eine **andere App**: Die alte bleibt installiert und bekommt nie wieder
  ein Update, jeder installiert einmal neu. Das war die bewusste
  Entscheidung; wer die ID künftig anfasst, löst dasselbe wieder aus.
  Release-Signing kommt
  aus `android/key.properties` (gitignored, in CI aus Secrets erzeugt). Ohne
  hinterlegten Keystore erscheint das Release bewusst **ohne APK** — nie still
  debug-signieren, sonst bricht jedes Update an der Signatur. Nötige Secrets:
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. **Keystore sichern** —
  Verlust bricht In-Place-Updates dauerhaft.
- **Update-Hinweis** (`core/update_check.dart`) pollt das neueste
  GitHub-Release (tokenlos). Jeder Fehlerpfad endet in `null` = kein Banner.
- **In-App-Update (Android)** installiert per `ota_update` aus dem
  Release-APK. Dafür müssen zusammenbleiben: `INTERNET` +
  `REQUEST_INSTALL_PACKAGES`, der FileProvider mit Authority **exakt**
  `${applicationId}.ota_update_provider`, `res/xml/filepaths.xml` mit
  `files-path ota_update/`, der `<queries>`-Eintrag VIEW/https für den
  Browser-Fallback und Core Library Desugaring in `build.gradle.kts`.
  Fehlt der FileProvider, stirbt die App direkt nach dem Download.
  Abgesichert durch `test/android_manifest_test.dart` — Änderungen daran
  zusätzlich auf einem echten Gerät verifizieren.
- **Android-Backup schließt die Sitzung aus** (`res/xml/backup_rules.xml` für
  Android ≤ 11, `res/xml/data_extraction_rules.xml` ab 12, beide am
  `<application>` verdrahtet). Grund: Eine Gruppe = ein Login, das
  Sitzungs-Token ist also das gemeinsame Zugangsmerkmal der Gruppe und darf
  nicht über das Google-Konto eines Mitglieds auf fremde Geräte wandern.
  Zwei Fallen dabei: Backup-Regeln adressieren **ganze Dateien**, nie
  einzelne Schlüssel — deshalb steht dort `FlutterSharedPreferences.xml`. Und
  ab Android 12 braucht der Ausschluss **beide** Blöcke (`cloud-backup` *und*
  `device-transfer`), sonst reist das Token beim Gerätewechsel doch mit.
  **Seit v0.44.0 ist diese Datei nicht mehr leer außer der Sitzung:** Die
  Geräte-Zuordnung (#121) liegt daneben. Der Ausschluss bleibt trotzdem — das
  Token wiegt schwerer —, und der Preis ist bewusst: Die Zuordnung überlebt
  keinen Gerätewechsel, das neue Gerät fragt erneut. Das ist der richtige
  Ausgang, ein neues Gerät gehört oft einer anderen Person. Wer künftig etwas
  ablegt, das eine Sicherung überstehen **muss**, braucht eine eigene Datei.
- **CSV-Export** ist die einzige Sicherung, die die Gruppe selbst in der Hand
  hat — alles seit dem Erst-Import lebt nur in Supabase (Free Plan, kein
  Point-in-Time-Recovery). `core/csv_export.dart` ist reine Aufbereitung
  (testbar, `test/csv_export_test.dart`), `core/export_file.dart` die
  Plattform-Weiche: Web lädt über einen Blob-Link herunter, Android reicht die
  Datei per `share_plus` ans Teilen-Menü (`XFile.fromData`, deshalb kein
  `path_provider`). Drei Formatdetails sind nicht kosmetisch, sondern
  entscheiden, ob die Datei in deutschem Excel per Doppelklick aufgeht:
  `;` als Trenner, CRLF als Zeilenende und ein UTF-8-BOM. Der Export **ist**
  die Import-Vorlage (Issue #34) — ein zweiter Template-Generator wäre eine
  zweite Wahrheit über das Format.
- **CSV-Import** (`core/csv_import.dart` = reines Parsen,
  `features/import/import_screen.dart` = Ablauf) liest genau das Format, das
  der Export schreibt; `test/csv_import_test.dart` prüft den **Rundlauf**
  Export → Import. Zwei Regeln sind der eigentliche Inhalt, nicht Komfort:
  Der Import legt **nie** still Personen an — aus „Bernd"/„Bernnd" würden
  zwei Personen und das verschiebt rückwirkend die Punkte *aller anderen*
  (Issue #34). Die Eindeutigkeit des Namens (seit v0.41.0, siehe unten) hilft
  dagegen **nicht**: Ein Vertipper ist ein anderer Name, kein doppelter. Und
  eine Fahrt, an der
  eine weggelassene Person beteiligt war, wird **ganz** übersprungen statt
  ohne sie angelegt; sonst änderten sich still die Punkte der übrigen an dem
  Tag. Tage mit vorhandener Fahrt bleiben unberührt.
- **Dateiauswahl: `file_selector`, nicht `file_picker`.** Letzteres verlangt
  ab 8.3.3 `win32 ^5.9`, `package_info_plus` aber `win32 ^6` — auflösbar wäre
  nur eine file_picker-Version von 2021. `file_selector` kommt von der
  Flutter-Foundation und deckt Web und Android mit einem Aufruf ab.
- **Die Bedienungsanleitung ist ein Screen** (`features/help/help_screen.dart`,
  Route `/help`, Menüpunkt „So funktioniert MitFahrBar"). Bewusst in Flutter
  statt als externe Seite: Sie erbt Theme und Schriften und zeigt die echten
  Widgets (`MoodFace`, `MitFahrBarMark`) — sie kann nicht wegdriften. Dafür
  gilt die Paar-Regel: **Wer die Bedienung ändert, pflegt die Anleitung mit.**
  `test/flows/help_flow_test.dart` nagelt die Kernaussagen fest, nicht den
  Wortlaut.
- **Feedback** landet in der Tabelle `feedback`; der Bot
  (`tool/feedback_bot.py`, `.github/workflows/feedback.yml`) macht daraus
  Issues. Er ruht, solange `SUPABASE_SERVICE_ROLE_KEY` nicht gesetzt ist.
  Die Issue-Templates unter `.github/ISSUE_TEMPLATE/` und die Felder im
  Feedback-Dialog gehören zusammen — Änderungen immer paarweise.
- **Stimmungs-Gesichter** kommen aus dem Design-Set „MitFahrBar Smiley Set"
  (Claude-Design-Projekt `ae532219-705e-4cdb-becd-cf734e17215a`). Sie sind
  **gezeichnet, nicht eingebunden** (`core/widgets/mood_face.dart`,
  CustomPainter) — dieselbe Linie wie bei den Charts, ein SVG-Renderer nur
  für acht Gesichter wäre eine Dependency zu viel. Die Geometrie steht 1:1
  im Koordinatensystem der Vorlage (viewBox 100×100) und wird erst beim
  Zeichnen skaliert, damit sie mit dem Design vergleichbar bleibt. Die
  Farben in `AppFace` sind aus **oklch** umgerechnet (Flutter kennt oklch
  nicht) — bei einer Änderung im Design-Set neu umrechnen, **nie von Hand
  nachjustieren**, sonst driftet die Skala auseinander. `Mood.celebrating`
  steht bewusst außerhalb der Bewertungsskala und kann von `driveMoodOf`
  nicht zurückgegeben werden; es zeichnet einen Erfolg aus, keine Stufe.
  Seit dem Design-Stand „Animated versions" (2026-07-22) sind die Gesichter
  **animiert**: Die CSS-Keyframes stehen 1:1 als Stützstellen in
  `mood_face.dart` — bei Änderungen im Design-Set neu übernehmen, nicht
  nachempfinden. Bei `disableAnimations` (Systemeinstellung „Bewegung
  reduzieren") ruhen sie; `pumpApp` setzt genau diese Flagge, sonst käme
  kein `pumpAndSettle` je zur Ruhe — wer sie dort entfernt, hängt jeden
  Flow-Test auf.
- **Branding:** `tool/brand/mark.svg` ist die einzige Quelle der Bildmarke.
  `tool/brand/build_icons.sh` (braucht `rsvg-convert` + python3) erzeugt
  daraus Web-Icons (normal + maskable), Favicon und die Android-Mipmaps
  inklusive Adaptive-Icon-Vordergrund. Icons nie von Hand bearbeiten.
  Schrift: Space Grotesk (Display) + Manrope (Body) als Variable Fonts.
- **Die README-Screenshots sind Erzeugnisse, keine Bilder.**
  `tool/screenshots.sh` baut die App im Demo-Modus, fährt sie mit Playwright
  durch und schreibt `doc/screenshots/*.png` — nie von Hand nachbauen oder
  zuschneiden, dieselbe Linie wie bei den Icons. Der Workflow
  „Screenshots" (`.github/workflows/screenshots.yml`) macht das bei jedem
  PR, der `lib/`, `assets/` oder `web/` anfasst, selbst und committet das
  Ergebnis in den Branch. Zwei Dinge daran sind nicht verhandelbar: Der
  Job überspringt sich, wenn die Branch-Spitze schon sein eigener Commit
  ist (`docs: refresh README screenshots`) — der Pfadfilter allein
  genügt dafür **nicht**, weil bei `pull_request` der ganze PR-Diff zählt
  und nicht der neue Commit; ohne den Riegel liefe es im Kreis, sobald
  zwei Läufe verschiedene Bilder erzeugen (im Screenshot steht ein
  Datum). Und nach dem Push muss die CI per `workflow_dispatch`
  angestoßen werden — ein Push mit dem `GITHUB_TOKEN` erzeugt bewusst
  keine Ereignisse, der PR hinge sonst ohne Required Checks fest. Weil die
  Bilder in `doc/` liegen, nimmt der Version Guard `doc/` ausdrücklich aus:
  Ein neuer Screenshot ist kein Release.
  **Der Dispatch-Lauf allein macht den PR aber nicht mergebar** (beobachtet
  am 26.07.2026, PR #103): Der Bot-Push erzeugt zusätzlich `pull_request`-
  Läufe, die auf `action_required` stehen bleiben und nie starten. Deren
  Namen sind die Required Checks, also bleibt der PR `BLOCKED` — obwohl
  `.../commits/<sha>/check-runs` alle sechs grün zeigt, denn das sind die
  des Dispatch-Laufs, und die zählt die Branch Protection nicht.
  Auflösung: die hängenden Läufe freigeben
  (`gh api -X POST repos/<owner>/<repo>/actions/runs/<id>/approve`,
  Kandidaten über `gh run list --branch <branch>` an
  `action_required` erkennbar) — danach laufen sie normal durch und der PR
  wird grün. Ein eigener Push (nicht vom Bot) hat das Problem nicht.
  **Das Freigeben allein genügt aber nicht immer** (nachgemessen 05.08.2026,
  PR #170): Die freigegebenen Läufe können von der `concurrency`-Gruppe
  sofort abgebrochen werden. Dann liegen auf demselben Commit je Check-Name
  **zwei** Läufe — ein abgebrochener und ein erfolgreicher — und die Branch
  Protection wertet nicht den zeitlich letzten, sondern den der **jüngsten
  Check-Suite**. Bei #170 war die abgebrochene Suite drei Sekunden jünger
  angelegt und gewann, obwohl ihre Läufe eine Minute *früher* endeten; der
  PR blieb `BLOCKED`, und `gh pr checks` zeigte `fail` mit Links in genau
  diesen Lauf. Ein `gh run rerun` des **erfolgreichen** Laufs half deshalb
  nicht — er liegt in der älteren Suite. Neu gestartet wird der
  **abgebrochene** Lauf; erst dessen Ergebnis zählt. Zum Erkennen taugt
  `.../check-runs` mit `check_suite.id` und `completed_at` nebeneinander:
  Weichen die beiden Reihenfolgen voneinander ab, ist genau das der Fall.
  **Zwei Läufe sind nie bitgleich** — die Stimmungs-Gesichter animieren,
  und jeder Lauf erwischt eine andere Phase (gemessen 5–281 abweichende
  Pixel, die Bounding-Box jedes Mal exakt auf einem Smiley).
  `reducedMotion` im Browser hilft nicht: Flutter-Web reicht
  `prefers-reduced-motion` nicht bis `disableAnimations` durch — der
  Hebel, den `pumpApp` in Tests benutzt, existiert dort nicht. Deshalb
  entscheidet `tool/screenshot_changed.mjs` über einen Pixel-Schwellwert,
  ob der neue Stand überhaupt übernommen wird; ohne ihn committete die CI
  bei jedem Lauf. Wer den Schwellwert anfasst, misst nach (zweimal
  `tool/screenshots.sh` laufen lassen), statt zu schätzen.
  **Der Workflow committet über die Contents-API, nicht mit `git commit`.**
  `main` verlangt signierte Commits (`required_signatures`), und ein
  Commit aus dem Runner trägt keine Signatur — er blockiert den PR mit
  „base branch policy prohibits the merge", obwohl jeder Check grün ist.
  Über die API committet GitHub selbst und signiert dabei. Das kostet
  einen Commit je Datei; beim Squash-Merge bleibt ohnehin einer übrig.
  Dieselbe Falle trifft jeden künftigen Workflow, der etwas ins Repo
  zurückschreibt. Und der Payload geht per `--input` über stdin, **nie
  als Argument**: Linux deckelt ein einzelnes Argument bei 128 KB —
  das Base64 einer PNG über ~96 KB riss den Lauf mitten in der Schleife
  ab (25.07.2026), zurück blieben ein halb committeter Bildersatz und
  ein PR ohne Checks auf dem neuen Head, weil auch der CI-Dispatch
  danach nie lief.
  Die Bildinhalte hängen an Koordinaten im 430×900-Viewport — verschiebt
  sich das Layout, zeigen die Bilder im PR sofort das Falsche.
- **Lizenz:** `LICENSE` ist MIT. Die Bildmarke und die gebündelten Schriften
  hängen nicht daran — Space Grotesk und Manrope stehen unter der SIL OFL,
  die verlangt, dass ihr Lizenztext mitgeliefert wird. Neue Assets deshalb
  immer mit ihrer Lizenz zusammen einchecken.
- **Der Release-Workflow prüft selbst.** `release.yml` entscheidet erst über
  den Tag, lässt dann `flutter analyze` + `flutter test` laufen und taggt erst
  danach. Grund: Der Merge ist die Veröffentlichung, aber `enforce_admins` ist
  aus — ein direkter Push auf `main` käme sonst am Branch-Schutz vorbei
  ungeprüft bis in Tag, APK und Pages-Deploy. Das Gate darf nie hinter das
  Taggen rutschen.
- **Der Release-Body ist der CHANGELOG-Auszug der Version** (seit v0.21.0).
  Die App zeigt ihn wortwörtlich unter „Was ist neu" im Update-Dialog —
  auto-generierte englische PR-Titel standen sonst roh vor der Gruppe.
  Fehlt der Abschnitt, setzt der Workflow einen Link statt Leere; die
  Anzeige glättet Markdown-Reste über `core/release_notes.dart`
  (`test/release_notes_test.dart`). Keine zweite Notes-Quelle einführen.
- **Der Start-Splash** (`features/splash/splash_overlay.dart`) liegt im
  `builder` der MaterialApp über allem und zeichnet die Bildmarke über
  `paintMitFahrBarMark` + `MitFahrBarPose` — Geometrie nur in
  `core/widgets/mitfahrbar_mark.dart`, die Animation ist reine
  Choreografie. Tipp überspringt, `disableAnimations` unterbindet ihn,
  und in Tests ist er über `splashEnabledProvider` standardmäßig aus
  (`pumpApp(splash: …)`) — sonst wartete jeder Flow-Test 3 Sekunden.
- **Config-Drift-Wache** (`.github/workflows/config-drift.yml` +
  `tool/config_drift.sh`, Issue #70): prüft täglich die Prod-Auth-Config
  über die Management-API gegen die Erwartungen des Codes (Bestätigungs-
  pflicht, Brevo-SMTP, Signup offen). Grund: Dashboard-Klicks sind für
  Repo und Teststack unsichtbar — genau so brach am 23.07.2026 die
  Gruppen-Registrierung. Bewusst NUR lesend: nie `supabase config push`
  einbauen, der könnte die Brevo-SMTP-Zugangsdaten im Dashboard
  überschreiben. Braucht das Repo-Secret `SUPABASE_ACCESS_TOKEN`
  (PAT, läuft jährlich ab — roter Lauf heißt auch: Token erneuern).
  Ändert sich eine Einstellung ABSICHTLICH, gehören Skript-Erwartung
  und Code-Abhängigkeiten im selben PR nachgezogen.
- **Dependabot läuft monatlich und gebündelt** (`.github/dependabot.yml`).
  Die Bündelung über `groups:` ist kein Kosmetik-Detail: `pubspec.yaml` ist
  nicht vom Version Guard ausgenommen, jeder pub-PR verlangt also einen
  Versions-Bump und veröffentlicht ein Release. Einzeln wären das bis zu fünf
  Releases im Monat nur für Abhängigkeiten. Die Guard-Regel bleibt trotzdem
  wie sie ist — ein Dependency-Wechsel geht wirklich an die Gruppen raus.
  Riverpod-Majors sind per `ignore` ausgenommen (2.x ist bewusst gepinnt).
- **`analysis_options.yaml` trägt die Leitplanken dieser Datei**: `avoid_print`
  und `use_build_context_synchronously` auf `error` hochgestuft, dazu
  `unawaited_futures`, `prefer_const_constructors`, `prefer_final_locals` und
  `strict-casts`/`strict-raw-types`. Abgesichert durch
  `test/analysis_options_test.dart` — wird eine Regel entfernt, bleibt
  `flutter analyze` grün und die Leitplanke verschwindet lautlos.
  **`require_trailing_commas` nie eintragen**: Die Regel gibt es seit Dart 3.7
  nicht mehr, ein Eintrag erzeugt eine „undefined lint rule" und damit rote CI.

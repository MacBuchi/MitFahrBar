# Plattform- und Kostenvergleich: Was tun, wenn die kostenlosen Kontingente nicht mehr reichen

**Status:** recherchiert am 2026-08-17 · **Gilt für:** MitFahrBar, PilzBuddy und
Mixstack gemeinsam · **Ablageort:** hier, weil MitFahrBar der einzige der drei
Mandantenbetriebe ist — die App-eigenen Teile stehen in
`doc/finanzierung-und-skalierung.md` (MitFahrBar),
`docs/finanzierung-und-skalierung.md` (PilzBuddy) und `docs/FINANZIERUNG.md`
(Mixstack) und verweisen hierher.

Dies ist **keine Steuer- oder Rechtsberatung.** Alle Preise sind Stand
2026-08-17 und veralten; jede Zahl steht mit Quelle da, damit man sie
nachprüfen kann statt sie zu glauben.

## Die Frage

Alle drei Apps laufen heute auf kostenlosen Kontingenten. Was passiert, wenn
die Nutzerzahlen steigen — und gibt es Plattformen, die besser skalieren als
das, was wir benutzen?

## Die Antwort in einem Satz

**Die Reihenfolge der Hebel ist: erst Kostenvermeidung, dann Supabase Pro,
dann Selbsthosting, und erst danach Einnahmen.** Eine App, die ihr
Egress-Kontingent durch eine Abfrage verbrennt, die niemand braucht,
finanziert man nicht — man repariert sie. Das ist keine Sparsamkeitsprosa: In
PilzBuddy liegt der größte Einzelposten heute in einer Schleife, die alle 15
Sekunden fragt, ob Freunde ihren Standort teilen, auch wenn man gar keine
Freunde hat.

## Stufe 0 — Kostenvermeidung

Das ist der einzige Hebel, der **nichts kostet und nichts verspricht**. Er
gehört vor jede Plattformentscheidung, weil er die Grundlast senkt, gegen die
alle folgenden Stufen gerechnet werden.

Die konkreten Posten stehen in den beiden App-Dokumenten. Das Muster dahinter
ist projektübergreifend und wichtiger als die Einzelfälle:

- **Massendaten gehören nicht in die Datenbank.** PilzBuddy macht das
  vorbildlich: Kartenkacheln, Regengitter, Waldgitter und die APK liegen auf
  **GitHub Releases** — Supabase trägt ausschließlich JSON-Zeilen. GitHub nennt
  für Release-Assets ausdrücklich *keine* Bandbreitengrenze (anders als bei Git
  LFS, wo 10 GiB/Monat gelten). Das ist der Grund, warum PilzBuddy trotz
  ~26 MB Waldgitter und ~60 MB APK bei 0 € liegt.
- **Eine Schleife ist eine Zusage über Kosten.** Jeder Poll-Takt multipliziert
  sich mit der Nutzerzahl. Bei einem Takt von 15 s sind es 240 Abfragen pro
  Stunde und aktivem Nutzer; bei 60 s sind es 60. Das ist derselbe Dienst zum
  Viertel des Preises.
- **Was nie aufgeräumt wird, wächst.** `public.push_log` in MitFahrBar hat
  keine Retention — dazu mehr im App-Dokument.

## Stufe 1 — Supabase Pro

Der kleinste mögliche Schritt: keine Migration, keine Codeänderung.

| | Free | Pro |
| --- | --- | --- |
| Datenbank | 500 MB | 8 GB je Projekt |
| Egress | 5 GB | 250 GB |
| Monatlich aktive Nutzer | 50.000 | 100.000 |
| Edge-Function-Aufrufe | 500.000 | mehr, verbrauchsabhängig |
| Aktive Projekte je Organisation | **2** | mehr |
| Pausieren bei Untätigkeit | nach ~1 Woche | nein |

Kosten: **25 $/Monat je Organisation**, darin 10 $ Compute-Guthaben — das
deckt genau **eine** Micro-Instanz. Bei zwei Projekten (PilzBuddy und
MitFahrBar) sind also realistisch **~35 $/Monat** zu erwarten, nicht 25.
Egress darüber hinaus kostet 0,09 $/GB.

**Der Punkt, der heute schon zählt:** Der Free-Plan erlaubt nur **zwei aktive
Projekte je Organisation**. PilzBuddy (`tntlujexvdtkynxbrdsn`) und MitFahrBar
(`azrlhlcxhpwmxcinjovp`) belegen sie vermutlich beide. **Das ist zu
verifizieren** — liegen sie in derselben Organisation, ist das Kontingent
bereits ausgeschöpft, und eine dritte Backend-App erzwingt Pro, ganz ohne
Nutzerwachstum. Liegen sie in zwei Organisationen, ist Luft, aber Pro würde
dann auch zweimal fällig (25 $ je Organisation).

Ein Nebeneffekt von Pro, der leicht übersehen wird: **Das Pausieren entfällt.**
Beide Projekte halten sich heute durch Cron-Jobs wach — in PilzBuddy sind der
Feedback-Bot (alle 2 h) und der Backup-Job ausdrücklich als bewusste Zusage
dokumentiert (`CLAUDE.md`), in MitFahrBar erledigt das der Minutentakt von
`flush-due-push` nebenbei. Auf Pro wäre diese Kopplung aufgelöst, und man
könnte die Takte nach Bedarf statt nach Überlebensnotwendigkeit wählen.

## Stufe 2 — Supabase selbst hosten

Deutlich billiger, und — das ist das eigentliche Argument — **im Haus bereits
erprobt.** FWApp fährt genau dieses Muster: Proxmox-VM, Docker-Supabase-Stack
hinter Kong, nginx für den Web-Build, öffentlich erreichbar über einen
Cloudflare Tunnel ohne Portfreigabe (`FWApp/docs/SERVER-SETUP.md`). Das
Betriebswissen ist also da, inklusive Backup- und Restore-Übung.

Kosten: ein Hetzner CPX21 (3 vCPU, 4 GB RAM) liegt bei ~8,40 €/Monat, ein
CX33 plus separate DB-VM bei ~12 $. Auf eigener Hardware — wie bei FWApp —
sind es Strom und die schon vorhandene Maschine.

Was man dafür bezahlt, steht nicht auf der Rechnung: Updates, Zertifikate,
Backups, Erreichbarkeit. Die verbreitete Faustregel lautet, dass sich
Selbsthosting erst ab etwa 200 $/Monat verwaltetem Betrieb wirklich lohnt —
„billig in Euro, teuer in Stunden". Für diese drei Apps heißt das: Stufe 2 ist
der richtige Schritt, **wenn Pro zu eng wird**, nicht um Pro zu vermeiden.

## Stufe 3 — die Alternativen, und warum sie hier nicht passen

### Google Cloud / Firebase

Der naheliegendste Gedanke, und für diese beiden Apps der falsche.

Der Free-Tier ist bei Lesezugriffen großzügiger (50.000 Firestore-Reads pro
**Tag**), und Firebase pausiert nie. Zwei Gründe sprechen trotzdem dagegen:

1. **Firestore hat kein RLS.** PilzBuddy und MitFahrBar setzen ihr
   *vollständiges* Sicherheitsmodell auf Postgres-Row-Level-Security — je rund
   20 Policies, in MitFahrBar dazu Tabellen mit null Policies und `revoke all`
   (`push_outbox`, `push_log`, `price_sample`), deren Unerreichbarkeit für den
   Client erzwungen und getestet ist. Firestore-Security-Rules können das
   nachbilden, aber es wäre keine Migration, sondern eine **Neuimplementierung
   der Sicherheitsgrenze** — mit allen Fehlern, die man beim ersten Mal auch
   gemacht hat. Der Aufwand steht in keinem Verhältnis zu 35 $/Monat.
2. **Der Blaze-Plan hat keine harte Ausgabengrenze.** Man kann ein Budget-Alarm
   setzen, aber nichts hält den Zähler an. Bei einer App, deren größter
   Kostenposten heute eine versehentlich zu schnelle Schleife ist, ist genau das
   die gefährlichere Eigenschaft: Auf Supabase Free bekommt man dann eine
   Fehlermeldung, auf Blaze eine Rechnung.

Was von Google **schon benutzt wird und bleiben soll**: FCM für Push. Das ist
kostenlos und ohne Mengenbegrenzung, und beide Apps hängen bereits daran.

### Neon / Turso

Neon ist Postgres mit Scale-to-zero und Branching, Turso ist SQLite am Rand.
Beide sind gute Datenbanken — aber sie sind *nur* Datenbanken. Auth, Storage
und Edge Functions müsste man daneben bauen; das sind genau die Teile, die hier
die Arbeit machen (GoTrue mit OTP-Flows, RLS-gebundene JWTs, die
Push-Funktionen). Nur als Notiz festgehalten, nicht als Empfehlung.

**Warnendes Beispiel:** PlanetScale hat seinen kostenlosen Tarif 2024
ersatzlos gestrichen. Ein kostenloser Tarif ist kein Vertrag.

### Cloudflare R2

Kein Egress-Entgelt, 0,015 $/GB Speicher, 10 GB frei. Für Massendaten
strukturell die beste Ablage — nur löst PilzBuddy dasselbe Problem heute schon
über GitHub Releases zu 0 €. R2 wird interessant, wenn GitHub die
Release-Bandbreite je einschränkt oder die Abuse-Erkennung anschlägt (was bei
Auslieferung über `raw.githubusercontent.com` vorkommt, bei Release-Assets
aber nicht der übliche Weg ist). **Als Rückfallplan notieren, nicht jetzt
bauen.**

## Der rechtliche Rahmen in Deutschland

Bewusst ohne Entscheidung — das ist der Punkt, an dem der Betreiber wählt.

**Spenden ohne Gegenleistung** sind kein Gewerbe. Wer einen „Kaffee
ausgeben"-Link auf die Projektseite stellt und dafür *nichts* verspricht —
keine Funktion, keinen Vorrang, keine Werbefreiheit —, bleibt im privaten
Bereich. Das ist der Weg mit dem geringsten Reibungsverlust und der einzige,
der die Nicht-kommerziell-Klauseln (siehe MitFahrBar) unangetastet lässt.

**Jede Gegenleistung** — Pro-Version, Abo, Werbeeinblendung — begründet
Gewinnerzielungsabsicht. Dann gilt:

- Gewerbeanmeldung beim Gewerbeamt, etwa 20–50 €.
- **Kleinunternehmerregelung nach § 19 UStG** bis 25.000 € Jahresumsatz: keine
  Umsatzsteuer, kein Vorsteuerabzug. Für die hier realistische Größenordnung
  der passende Rahmen.
- Einkünfte sind einkommensteuerpflichtig, unabhängig von der Höhe.

**Google Play rechnet als Merchant of Record die Umsatzsteuer selbst ab** —
das nimmt einem die Umsatzsteuer-Mechanik gegenüber Endkunden ab, **ersetzt
aber die Gewerbeanmeldung nicht**.

**Spendenfunktionen im Play Store sind gemeinnützigen Organisationen
vorbehalten.** Für eine Privatperson führt der Weg über GitHub Sponsors, Ko-fi
oder PayPal — verlinkt **von der Projektseite**, nicht als In-App-Kauf. Die
Play-Zahlungsrichtlinie nimmt steuerbefreite Spenden ausdrücklich von der
Pflicht zur Play-Abrechnung aus; für alles andere gilt sie. Wer in der App
selbst auf eine Spendenseite verlinkt, sollte damit vorsichtig sein — es gibt
dokumentierte Fälle, in denen Google das beanstandet hat.

**Gebühren, falls doch verkauft wird:** Play Billing nimmt 15 % bei den
Umsätzen, um die es hier geht (der reduzierte Satz für die ersten 1 Mio. $
Jahresumsatz). Seit Januar 2026 sind alternative Zahlungsanbieter breiter
zugelassen, mit Sätzen um 9–20 % — für kleine Beträge lohnt der Aufwand nicht.

## Empfehlung

1. **Jetzt:** Stufe 0 abarbeiten, beginnend mit PilzBuddys Poll-Schleife.
   Prüfen, ob beide Supabase-Projekte in derselben Organisation liegen.
2. **Wenn eine Grenze in Sicht kommt:** Supabase Pro. 35 $/Monat sind gegen den
   Zeitaufwand jeder Alternative billig.
3. **Wenn Pro zu eng wird:** Selbsthosting nach dem FWApp-Muster.
4. **Einnahmen** sind der letzte Schritt, nicht der erste — und je App eine
   eigene Frage, weil die Lizenzen verschieden binden. Siehe die App-Dokumente.

## Quellen

Abgerufen am 2026-08-17.

- [Supabase Pricing 2026 – Free vs Pro vs Team](https://uibakery.io/blog/supabase-pricing)
- [Supabase Pricing 2026 (Kalkulator)](https://makerkit.dev/blog/saas/supabase-pricing)
- [Firebase Pricing 2026: wo die Blaze-Rechnung bricht](https://www.sashido.io/en/blog/firebase-guide-and-pricing-traps-2026)
- [Cloudflare R2 Pricing 2026: 0 $ Egress](https://egresscost.com/cloudflare/)
- [Selbst gehostetes Supabase auf Hetzner mit Coolify](https://community.hetzner.com/tutorials/coolify-supabase-deploy/)
- [Datenbank-Free-Tier-Vergleich 2026 (Neon, Turso, PlanetScale)](https://agentdeals.dev/database-free-tier-comparison-2026)
- [GitHub: Storage und Bandbreite (LFS vs. Releases)](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-storage-and-bandwidth-usage)
- [Google Play: Zahlungsrichtlinie](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en)
- [Kleinunternehmerregelung § 19 UStG](https://www.gruenderlexikon.de/checkliste/informieren/gruendungsstrategie/nebengewerbe/nebengewerbe-aus-hobby/)

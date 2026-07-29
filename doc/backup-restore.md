# Backup und Wiederherstellung

Der Supabase-Free-Plan hat **kein** Point-in-Time-Recovery und keine
automatischen Dumps. Eine missglückte Migration oder ein versehentliches
Löschen trifft die Fahrten aller Gruppen ohne Zwischenstufe. Diese Seite
beschreibt, was dagegen läuft und wie man im Ernstfall zurückkommt.
Das Muster stammt von PilzBuddy (`docs/backup-restore.md` dort); die
Unterschiede sind unten benannt.

## Was gesichert wird

`.github/workflows/backup.yml` zieht montags 03:23 UTC (und auf Zuruf per
`workflow_dispatch`) einen `pg_dump` der Schemata `public`, `auth` und
`supabase_migrations`, verschlüsselt ihn mit age und legt ihn als
Release-Asset im **privaten** Repo `MacBuchi/mitfahrbar-backups` ab.

- `auth` ist mit drin, weil `group_id = auth.uid()` ist: Ohne `auth.users`
  gäbe es keine Gruppen-Logins mehr, und jede Zeile in `public` hinge an
  einer ID ohne Konto.
- `supabase_migrations` ist mit drin, weil die GitHub-Integration dort
  Buch führt: Fehlte die Tabelle nach einem Restore, spielte die
  Integration **alle** Migrationen erneut gegen das fertige Schema — und
  scheiterte an der ersten, die es schon gibt.
- Kein `app_internal` wie bei PilzBuddy: Alle SECURITY-DEFINER-Funktionen
  dieses Projekts liegen in `public` und reisen mit dem Schema mit.
- Vor dem Verschlüsseln prüft `tool/db_backup.sh`, ob **jede** Tabelle aus
  `supabase/schema.sql` wirklich im Dump steht (`test/backup_workflow_test.dart`
  hält die Liste synchron). Ein halber Dump wird nicht hochgeladen — sich
  fälschlich gesichert zu glauben ist schlimmer als kein Backup.
- Aufbewahrt werden die letzten **12** Backups (~3 Monate). Lang genug, um
  einen Schaden zu bemerken; kurz genug, dass eine per `admin_delete_group`
  gelöschte Gruppe nicht unbegrenzt in Backups weiterlebt.

## Der Schlüssel

Verschlüsselt wird **asymmetrisch**: Der öffentliche age-Schlüssel steht im
Klartext in `tool/db_backup.sh`, der private liegt ausschließlich in
`~/mitfahrbar-keys/mitfahrbar-backup.agekey` — **nie** in GitHub. Wer sich
Zugang zu Repo oder Backup-Ablage verschafft, bekommt Chiffrat und sonst
nichts. Eigenes Schlüsselpaar je Projekt: Ein kompromittierter Schlüssel
soll nicht die Backups zweier Apps aufmachen.

> ⚠️ Geht `mitfahrbar-backup.agekey` verloren, sind **alle** Backups
> wertlos. Der Ordner `~/mitfahrbar-keys/` gehört auf dasselbe
> Sicherungsmedium wie der Android-Keystore.

## Einmaliges Setup

1. Privates Repo `MacBuchi/mitfahrbar-backups` anlegen — **mit README**
   (ein leeres Repo hat keinen Standard-Branch, `gh release create`
   scheitert daran). ✓ erledigt 2026-07-29.
2. Fein granulares PAT mit `Contents: Read and write` auf das Backup-Repo —
   das PilzBuddy-PAT wurde auf `mitfahrbar-backups` erweitert.
3. Im App-Repo zwei Secrets hinterlegen:
   - `BACKUP_REPO_TOKEN` — das PAT aus Schritt 2.
   - `SUPABASE_DB_URL` — die **Session-Pooler-URI** inkl. DB-Passwort
     (Dashboard → Connect → Session pooler). Der Job ruht still
     (`::notice::`), solange eines der beiden fehlt.
4. Kalendereintrag zum Ablaufdatum des PAT — läuft es ab, schlägt der Job
   fehl (GitHub mailt bei fehlgeschlagenen geplanten Läufen).

## Der wöchentliche Restore-Drill

Ein nie zurückgespieltes Backup ist kein Backup — PilzBuddys allererster
Drill hat genau so ein „vollständiges" Backup widerlegt. Anders als dort
läuft der Drill hier **in CI, direkt nach jedem Upload**, gegen die
**hochgeladene** Datei (nicht ihre lokale Schwester):

1. Der Workflow erzeugt je Lauf ein Wegwerf-age-Schlüsselpaar und
   verschlüsselt das Backup an **beide** Empfänger. So kann der Drill die
   Datei öffnen, ohne dass der private Betreiber-Schlüssel je zu GitHub
   muss; der Wegwerf-Schlüssel stirbt mit dem Runner.
2. `tool/db_restore_drill.sh` spielt den Dump in einen frischen lokalen
   Supabase-Stack ein (`ON_ERROR_STOP`) und prüft: Zählwerte gegen die
   Quelle, RLS auf jeder Tabelle, `my_group_active()`, GoTrue-Konto-Anlage
   samt Login — und, falls das Testkonto im Dump steht, einen Login mit
   einem **wiederhergestellten** Passwort-Hash.

Was der Drill **nicht** beweist: dass der private Betreiber-Schlüssel zur
Datei passt (ein Tippfehler im Empfänger fiele nicht auf), und den Restore
in ein **echtes** Supabase-Projekt. Beides deckt nur die manuelle Übung
unten ab.

## Wiederherstellung

Voraussetzung: `age` und `psql` (PostgreSQL 17) lokal,
`~/mitfahrbar-keys/mitfahrbar-backup.agekey` zur Hand.

```bash
# 1. Gewünschtes Backup holen
gh release list --repo MacBuchi/mitfahrbar-backups
gh release download backup-2026-08-03 --repo MacBuchi/mitfahrbar-backups

# 2. Entschlüsseln
age -d -i ~/mitfahrbar-keys/mitfahrbar-backup.agekey \
  -o mitfahrbar.sql mitfahrbar-2026-08-03.sql.age

# 3. Plausibilität prüfen, BEVOR irgendwo eingespielt wird
grep -c 'INSERT INTO\|COPY ' mitfahrbar.sql
grep 'CREATE TABLE "public"."trips"' mitfahrbar.sql

# 4. In ein FRISCHES Supabase-Projekt einspielen (nie zuerst in die
#    Produktion). Der Dump bringt CREATE SCHEMA mit — supabase/schema.sql
#    NICHT vorher einspielen.
psql "<session-pooler-uri-des-zielprojekts>" -v ON_ERROR_STOP=1 -f mitfahrbar.sql
```

> ⚠️ Gemessen beim allerersten Drill (2026-07-30): `postgres` ist **nicht**
> Eigentümer des `auth`-Schemas — lokal wie gehostet gehört es
> `supabase_auth_admin`. Der Drill verbindet sich deshalb als
> `supabase_admin` (der Superuser des CLI-Stacks). In einem **gehosteten**
> Zielprojekt gibt es diesen Zugang nicht, und das `auth`-Schema existiert
> dort schon: Der `auth`-Teil des Dumps kollidiert. Wie der gehostete
> Restore damit umgeht, ist Teil der offenen Übung unten — genau deshalb
> steht sie noch aus.

Der entschlüsselte Dump enthält Personennamen und Passwort-Hashes — nach
der Prüfung sofort löschen.

### Was der Dump NICHT enthält — Pflichtschritte danach

Diese vier Dinge leben außerhalb der gesicherten Schemata. Ohne sie läuft
die wiederhergestellte Datenbank, aber nicht das Produkt:

1. **Die drei Vault-Einträge** (`push_functions_url`, `push_job_secret`,
   `push_service_key`). `vault.secrets` ist mit einem projekt-eigenen
   Schlüssel verschlüsselt — in einem anderen Projekt ist das Chiffrat
   unbrauchbar. Neu setzen wie in
   `supabase/migrations/20260729140000_push_dispatch.sql` beschrieben.
2. **Der pg_cron-Job** (minütlich `flush_due_push`). Das Schema `cron`
   wird nicht gesichert, und die Migrationshistorie sagt „schon
   eingespielt" — der `cron.schedule(...)`-Aufruf aus derselben Migration
   muss von Hand laufen. Ohne ihn ist der schnelle Push-Weg **still** tot;
   `tool/notify.dart` repariert stündlich, deshalb fällt es nur am Timing
   auf.
3. **Die Edge Functions** (`request-group`, `send-push`, `flush-push`)
   samt ihrer Secrets (FCM-Dienstkonto). Functions liegen nicht in der
   Datenbank — neu deployen, Secrets im Dashboard neu setzen
   (Hash-Abgleich: `supabase secrets list` zeigt SHA-256).
4. **Die Auth-Konfiguration** (Dashboard, nicht DB): Brevo-SMTP,
   Mail-Vorlagen mit `{{ .Token }}` statt Link, `site_url`/`uri_allow_list`,
   Bestätigungspflicht. `tool/config_drift.sh` prüft danach, ob alles
   wieder den Code-Erwartungen entspricht.

> ⚠️ Ein **neues** Projekt hat eine neue URL und neue API-Keys —
> `lib/core/supabase_config.dart` zeigt dann ins Leere. Die App braucht in
> dem Fall ein Release mit den neuen Werten; der Sperr-Schirm hilft hier
> nicht, denn die alte App erreicht ja nicht einmal `app_config`.

### Ernstfall in der Produktion

1. **Zuerst** einen Dump des aktuellen (kaputten) Zustands ziehen:
   Workflow `Database Backup` manuell starten. Ohne den ist der Schaden
   nach dem Einspielen nicht mehr analysierbar.
2. Backup wie oben in ein Wegwerf-Projekt einspielen und prüfen, ob es den
   gewünschten Stand enthält.
3. Erst dann in die Produktion — `public`, `auth` und
   `supabase_migrations` vorher leeren (der Dump bringt die Schemata mit).
4. Die vier Pflichtschritte oben abarbeiten.
5. `flutter test test/e2e` gegen den lokalen Stack und einen Handy-Login
   gegen die Produktion — erst dann Entwarnung geben.

## Restore-Übung (manuell, ins echte Projekt)

- Wegwerf-Supabase-Projekt anlegen (Free Plan, beliebige Region)
- Neuestes Backup mit dem **Betreiber-Schlüssel** entschlüsseln und
  einspielen — das beweist nebenbei, dass der Schlüssel zur Ablage passt
- Zählwerte mit dem Release-Text vergleichen, Login mit einem Bestandskonto
- Projekt wieder löschen

**Letzter vollständiger Restore in ein echtes Supabase-Projekt: _noch
keiner_.** Datum und Ergebnis hier eintragen, sobald er gelaufen ist —
dieselbe offene Stelle führt PilzBuddy als pilzbuddy#111.

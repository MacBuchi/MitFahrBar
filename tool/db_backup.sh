#!/usr/bin/env bash
# db_backup.sh – verschlüsseltes Backup der Live-Supabase-Datenbank (#135).
#
# Der Free Plan hat kein Point-in-Time-Recovery und keine automatischen
# Dumps: Eine missglückte Migration oder ein versehentliches Löschen trifft
# die Fahrten aller Gruppen ohne Weg zurück. Dieses Skript ist der Weg
# zurück. Muster übernommen von PilzBuddy (tool/db_backup.sh dort),
# angepasst an die Schemata und Tabellen dieses Projekts.
#
# Verschlüsselt wird bewusst ASYMMETRISCH: Unten steht der ÖFFENTLICHE
# age-Schlüssel und darf im Repo liegen. Der private existiert nur in
# ~/mitfahrbar-keys/mitfahrbar-backup.agekey auf dem Rechner des Betreibers
# und erreicht GitHub nie. Wer Repo oder Backup-Ablage aufmacht, bekommt
# Chiffrat und sonst nichts. Eine Passphrase als Actions-Secret hätte genau
# diese Eigenschaft nicht.
#
# BACKUP_EXTRA_RECIPIENT (optional) ist für den Restore-Drill in CI: Der
# Workflow erzeugt je Lauf ein Wegwerf-Schlüsselpaar und verschlüsselt an
# beide Empfänger — so kann der Drill GENAU die hochgeladene Datei öffnen,
# ohne dass der private Betreiber-Schlüssel je zu GitHub muss. Der
# Wegwerf-Schlüssel stirbt mit dem Runner.
#
# Braucht SUPABASE_DB_URL (Session-Pooler-URI inkl. Passwort, GitHub-
# Secret). Hochladen braucht zusätzlich GH_TOKEN mit contents:write auf
# BACKUP_REPO (fein granulares PAT, Secret BACKUP_REPO_TOKEN).
#
# Lokaler Probelauf (Dump + Prüfung + Verschlüsselung, kein Upload):
#     SUPABASE_DB_URL=... bash tool/db_backup.sh --no-upload
#
# pg_dump darf nicht älter sein als der Server (17.x), sonst verweigert es
# den Dienst. Wo das Standard-Binary zu alt ist:
#     PG_DUMP=/opt/homebrew/opt/postgresql@17/bin/pg_dump
set -euo pipefail

PG_DUMP="${PG_DUMP:-pg_dump}"
PSQL="${PSQL:-psql}"

# Öffentlicher age-Schlüssel — Chiffrat, kein Geheimnis. Der private Teil
# liegt ausschließlich in ~/mitfahrbar-keys/mitfahrbar-backup.agekey.
# Eigenes Schlüsselpaar je Projekt: Ein kompromittierter Schlüssel soll
# nicht die Backups zweier Apps aufmachen.
RECIPIENT="${BACKUP_AGE_RECIPIENT:-age1ex89gdtwc5afk5dnv3j9x8gq8850d88egfqh8wnuvq4j9q44dewsfh9x35}"
BACKUP_REPO="${BACKUP_REPO:-MacBuchi/mitfahrbar-backups}"

# Wie viele Backups aufbewahrt werden. Zwölf Wochenläufe sind lang genug,
# um einen Schaden zu bemerken, und kurz genug, dass eine gelöschte Gruppe
# nicht unbegrenzt in Backups weiterlebt — admin_delete_group verspricht
# eine echte Löschung, und die Rotation ist ihr Ablaufdatum in den Backups.
KEEP="${BACKUP_KEEP:-12}"

upload=1
[ "${1:-}" = "--no-upload" ] && upload=0

DB_URL="${SUPABASE_DB_URL:-}"
if [ -z "$DB_URL" ]; then
  echo "::error::SUPABASE_DB_URL fehlt — ohne die Session-Pooler-URI (inkl. DB-Passwort) kann kein Dump gezogen werden."
  exit 1
fi

stamp=$(date -u +%Y-%m-%d)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
dump="$workdir/mitfahrbar-$stamp.sql"

echo "→ Dump wird gezogen (Schemata public + auth + supabase_migrations) …"
# auth muss mit: ohne auth.users gibt es keine Gruppen-Logins mehr —
# group_id IST die Auth-User-ID, jede Zeile in public hängt daran.
# supabase_migrations muss mit: Die GitHub-Integration führt dort Buch,
# welche Migrationen liefen. Fehlte die Tabelle nach einem Restore, spielte
# die Integration ALLE Migrationen erneut gegen das fertige Schema —
# und scheiterte an der ersten, die es schon gibt.
# Kein app_internal wie bei PilzBuddy: Alle SECURITY-DEFINER-Funktionen
# dieses Projekts liegen in public und reisen mit dem Schema mit.
# Ownership/Grants bleiben drin — die Rollen (anon, authenticated,
# service_role) heißen in jedem Supabase-Projekt gleich, und ohne die
# Grants wäre die wiederhergestellte DB ohne RLS-Rechte.
$PG_DUMP "$DB_URL" \
  --schema=public \
  --schema=auth \
  --schema=supabase_migrations \
  --no-comments \
  --quote-all-identifiers \
  --file="$dump"

# Ein leerer oder halber Dump, der still hochgeladen wird, ist schlimmer
# als gar kein Backup: Man hält sich für gesichert und ist es nicht.
# Die Liste führt JEDE Tabelle aus supabase/schema.sql —
# test/backup_workflow_test.dart hält beide Seiten zusammen, damit eine
# künftige Tabelle nicht ungeprüft mitfährt.
echo "→ Dump wird geprüft …"
missing=""
# --quote-all-identifiers macht daraus CREATE TABLE "public"."trips" (…
for table in \
  public.groups public.persons public.trips public.trip_participations \
  public.settings public.group_defaults public.feedback public.app_config \
  public.plan_availability public.plan_overrides public.plan_notes \
  public.push_devices public.notification_prefs public.push_log \
  public.push_outbox public.group_admins public.error_reports \
  public.price_area public.price_sample public.price_week \
  auth.users supabase_migrations.schema_migrations; do
  schema=${table%%.*}
  name=${table#*.}
  grep -q "CREATE TABLE \"$schema\".\"$name\"" "$dump" || missing="$missing $table"
done
# Nicht nur Tabellen: my_group_active() steht in jeder RLS-Policy — fehlte
# die Funktion, scheiterte beim Einspielen schon CREATE POLICY. Dieselbe
# Fehlerklasse, die PilzBuddys allererster Restore-Drill gefunden hat
# (dort: fehlendes Schema app_internal).
grep -q 'CREATE FUNCTION "public"."my_group_active"' "$dump" \
  || missing="$missing public.my_group_active()"
if [ -n "$missing" ]; then
  echo "::error::Dump unvollständig — das fehlt:$missing. Nichts hochgeladen."
  exit 1
fi

# Nur Zahlen, nie Inhalte: Personennamen und Fahrtdaten gehören nicht ins
# Log (dieselbe Regel wie bei tool/notify.dart).
groups=$("$PSQL" "$DB_URL" -qtA -c \
  "select count(*) from public.groups" 2>/dev/null || echo "?")
trips=$("$PSQL" "$DB_URL" -qtA -c \
  "select count(*) from public.trips" 2>/dev/null || echo "?")
users=$("$PSQL" "$DB_URL" -qtA -c \
  "select count(*) from auth.users" 2>/dev/null || echo "?")
db_size=$("$PSQL" "$DB_URL" -qtA -c \
  "select pg_size_pretty(pg_database_size(current_database()))" 2>/dev/null || echo "?")
dump_size=$(du -h "$dump" | cut -f1)

echo "→ Wird verschlüsselt (age, Empfänger $RECIPIENT) …"
recipients=(-r "$RECIPIENT")
if [ -n "${BACKUP_EXTRA_RECIPIENT:-}" ]; then
  echo "  (zusätzlicher Empfänger für den Restore-Drill)"
  recipients+=(-r "$BACKUP_EXTRA_RECIPIENT")
fi
age "${recipients[@]}" -o "$dump.age" "$dump"
enc_size=$(du -h "$dump.age" | cut -f1)

# Gegenprobe, dass die Datei wirklich als age-Chiffrat vorliegt und nicht
# etwa der Klartext durchgereicht wurde.
head -c 20 "$dump.age" | grep -q "age-encryption.org" || {
  echo "::error::Ausgabe ist kein age-Chiffrat — Abbruch, bevor irgendetwas hochgeladen wird."
  exit 1
}

summary="Datenbank: $db_size · Dump: $dump_size · verschlüsselt: $enc_size · Gruppen: $groups · Fahrten: $trips · Auth-Nutzer: $users"
echo "✓ $summary"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Backup $stamp"
    echo ""
    echo "- Datenbankgröße: **$db_size** (Free-Plan-Grenze: 500 MB)"
    echo "- Dump: $dump_size, verschlüsselt: $enc_size"
    echo "- Gruppen: $groups · Fahrten: $trips · Auth-Nutzer: $users"
  } >> "$GITHUB_STEP_SUMMARY"
fi

# Zählwerte an den Drill durchreichen: Er vergleicht die wiederhergestellte
# Datenbank gegen genau diese Zahlen — ein halber Restore fällt so auf.
tag="backup-$stamp"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "groups=$groups"
    echo "trips=$trips"
    echo "users=$users"
    if [ "$upload" -eq 1 ]; then echo "tag=$tag"; else echo "tag="; fi
  } >> "$GITHUB_OUTPUT"
fi

if [ "$upload" -eq 0 ]; then
  echo "--no-upload: Datei bleibt liegen unter $dump.age"
  cp "$dump.age" "./mitfahrbar-$stamp.sql.age"
  echo "Kopiert nach ./mitfahrbar-$stamp.sql.age"
  exit 0
fi

if [ -z "${GH_TOKEN:-}" ]; then
  echo "::error::GH_TOKEN fehlt — das Backup wurde erstellt, kann aber nicht abgelegt werden. Repo-Secret BACKUP_REPO_TOKEN anlegen (fein granulares PAT, nur contents:write auf $BACKUP_REPO)."
  exit 1
fi

echo "→ Wird abgelegt in $BACKUP_REPO …"
# Release-Assets statt Git-Historie: mehrere Rückkehrpunkte, kein ewig
# wachsender Baum — und ein gelöschtes Backup ist wirklich weg, was die
# Rotation unten erst zu einer echten Löschung macht.
# Ein zweiter Lauf am selben Tag (z. B. manuell vor einer Migration) darf
# nicht scheitern: Dann wird das Asset im vorhandenen Release ersetzt.
if gh release view "$tag" --repo "$BACKUP_REPO" >/dev/null 2>&1; then
  gh release upload "$tag" "$dump.age" --repo "$BACKUP_REPO" --clobber
else
  gh release create "$tag" "$dump.age" --repo "$BACKUP_REPO" \
    --title "Backup $stamp" --notes "$summary"
fi
echo "✓ Abgelegt als $tag"

# Alte Backups abräumen — begrenzt den Speicher und die Zeit, die eine
# gelöschte Gruppe in Backups überlebt.
old=$(gh release list --repo "$BACKUP_REPO" --limit 100 --json tagName \
  --jq '.[].tagName' | grep '^backup-' | sort -r | tail -n "+$((KEEP + 1))" || true)
for tag in $old; do
  echo "→ Räumt altes Backup ab: $tag"
  gh release delete "$tag" --repo "$BACKUP_REPO" --yes --cleanup-tag
done

echo "Backup abgeschlossen."

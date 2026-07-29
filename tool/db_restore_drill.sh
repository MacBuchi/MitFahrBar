#!/usr/bin/env bash
# db_restore_drill.sh – beweist, dass ein Backup WIEDERHERSTELLBAR ist.
#
# Ein nie zurückgespieltes Backup ist kein Backup. PilzBuddys allererster
# Drill hat genau so ein „vollständiges" Backup widerlegt (fehlendes
# Helfer-Schema — entschlüsselbar, aber nicht einspielbar). Dieser Drill
# läuft deshalb in CI nach JEDEM Upload: Er entschlüsselt die Datei, spielt
# sie in einen frischen lokalen Supabase-Stack ein und prüft, ob daraus
# wieder eine funktionierende Datenbank wird — inklusive Login gegen das
# wiederhergestellte auth.users, die Hälfte, die PilzBuddys Drill offen
# lässt.
#
#     tool/db_restore_drill.sh <backup.sql.age> <age-identity-datei>
#
# Braucht einen LAUFENDEN lokalen Supabase-CLI-Stack (supabase start;
# vorher supabase db reset für einen definierten Ausgangszustand). Ohne
# gesetzte DRILL_DB_URL holt sich das Skript die Zugänge selbst aus
# `supabase status` — dasselbe Muster wie tool/e2e.sh.
#
# EXPECTED_GROUPS / EXPECTED_TRIPS / EXPECTED_USERS (optional): Zählwerte
# der Quelle. Gesetzt (der Workflow reicht sie aus dem Backup-Lauf durch)
# muss die wiederhergestellte Datenbank sie exakt treffen — ein halber
# Restore fällt so auf, nicht erst im Ernstfall.
#
# Der Drill beweist die Einspielbarkeit in einen CLI-Stack. Der Restore in
# ein echtes Supabase-Projekt (GoTrue-Versionen, gehostete Rollen) bleibt
# eine manuelle Übung — doc/backup-restore.md.
set -euo pipefail

PSQL="${PSQL:-psql}"

backup_file="${1:-}"
identity="${2:-}"
if [ -z "$backup_file" ] || [ -z "$identity" ]; then
  echo "Aufruf: tool/db_restore_drill.sh <backup.sql.age> <age-identity-datei>" >&2
  exit 1
fi
[ -f "$backup_file" ] || { echo "::error::Backup-Datei fehlt: $backup_file"; exit 1; }
[ -f "$identity" ] || { echo "::error::age-Identity fehlt: $identity"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "::error::jq fehlt — der Drill parst GoTrue-Antworten damit."; exit 1; }

# Zugänge zum lokalen Stack — wie in tool/e2e.sh, nur mit DB_URL dazu.
# Wichtig: Der Drill verbindet sich als supabase_admin, nicht als postgres.
# `postgres` ist (lokal wie gehostet) NICHT Eigentümer des auth-Schemas —
# der Drop und die OWNER-TO-Zeilen im Dump brauchen den Superuser des
# Stacks. Erster Lauf des Drills am 2026-07-30: „must be owner of schema
# auth". Lokal tragen alle verwalteten Rollen das DB-Passwort aus der URL.
if [ -z "${DRILL_DB_URL:-}" ]; then
  command -v supabase >/dev/null 2>&1 || {
    echo "::error::Supabase-CLI fehlt und DRILL_DB_URL ist nicht gesetzt."
    exit 1
  }
  eval "$(supabase status -o env)"
  DRILL_DB_URL="$(printf '%s' "$DB_URL" | sed 's|//postgres:|//supabase_admin:|')"
  DRILL_API_URL="$API_URL"
  DRILL_ANON_KEY="$ANON_KEY"
  DRILL_SERVICE_KEY="$SERVICE_ROLE_KEY"
fi

workdir=$(mktemp -d)
# Der Klartext-Dump enthält Personennamen und Passwort-Hashes — er lebt nur
# für die Dauer des Drills und wird immer aufgeräumt, auch im Fehlerfall.
trap 'rm -rf "$workdir"' EXIT
dump="$workdir/restore.sql"

echo "→ Backup wird entschlüsselt …"
age -d -i "$identity" -o "$dump" "$backup_file"

echo "→ Klartext wird geprüft, bevor irgendetwas eingespielt wird …"
for probe in \
  'CREATE TABLE "public"."groups"' \
  'CREATE TABLE "public"."trips"' \
  'CREATE TABLE "auth"."users"' \
  'CREATE SCHEMA'; do
  grep -q "$probe" "$dump" || {
    echo "::error::Dump enthält nicht: $probe — Abbruch."
    exit 1
  }
done

echo "→ Zielschemata werden geleert (der Dump bringt CREATE SCHEMA mit) …"
# supabase_migrations muss mit fallen: Nach `supabase db reset` steht dort
# die lokale Migrationshistorie, der Dump bringt die der Produktion mit.
"$PSQL" "$DRILL_DB_URL" -v ON_ERROR_STOP=1 -q -c '
  set client_min_messages = warning;
  drop schema if exists public cascade;
  drop schema if exists auth cascade;
  drop schema if exists supabase_migrations cascade;
'

echo "→ Dump wird eingespielt (ON_ERROR_STOP) …"
# -o /dev/null: Der Dump enthält select-Aufrufe (setval, set_config), deren
# Ergebniszeilen sonst im Log landen — Fehler kommen weiter über stderr.
"$PSQL" "$DRILL_DB_URL" -v ON_ERROR_STOP=1 -q -o /dev/null -f "$dump"

echo "→ Zählwerte werden geprüft …"
# "?" heißt: Die Zählabfrage beim Backup selbst schlug fehl (das Backup-
# Skript lässt den Lauf daran nicht scheitern). Dann gibt es nichts zu
# vergleichen — nicht an einem Fragezeichen rot werden.
[ "${EXPECTED_GROUPS:-}" = "?" ] && EXPECTED_GROUPS=""
[ "${EXPECTED_TRIPS:-}" = "?" ] && EXPECTED_TRIPS=""
[ "${EXPECTED_USERS:-}" = "?" ] && EXPECTED_USERS=""
groups=$("$PSQL" "$DRILL_DB_URL" -qtA -c "select count(*) from public.groups")
trips=$("$PSQL" "$DRILL_DB_URL" -qtA -c "select count(*) from public.trips")
users=$("$PSQL" "$DRILL_DB_URL" -qtA -c "select count(*) from auth.users")
echo "  Gruppen: $groups · Fahrten: $trips · Auth-Nutzer: $users"
fail=""
[ -n "${EXPECTED_GROUPS:-}" ] && [ "$groups" != "$EXPECTED_GROUPS" ] \
  && fail="$fail Gruppen($groups statt $EXPECTED_GROUPS)"
[ -n "${EXPECTED_TRIPS:-}" ] && [ "$trips" != "$EXPECTED_TRIPS" ] \
  && fail="$fail Fahrten($trips statt $EXPECTED_TRIPS)"
[ -n "${EXPECTED_USERS:-}" ] && [ "$users" != "$EXPECTED_USERS" ] \
  && fail="$fail Auth-Nutzer($users statt $EXPECTED_USERS)"
if [ -n "$fail" ]; then
  echo "::error::Restore unvollständig — Abweichung:$fail"
  exit 1
fi

echo "→ RLS wird geprüft …"
# Nach dem Restore muss JEDE public-Tabelle RLS tragen — auch die bewusst
# policy-losen (push_log, push_outbox, group_admins): Ohne RLS wären genau
# die offen, die niemand lesen darf.
unprotected=$("$PSQL" "$DRILL_DB_URL" -qtA -c \
  "select coalesce(string_agg(tablename, ', '), '') from pg_tables
   where schemaname = 'public' and not rowsecurity")
if [ -n "$unprotected" ]; then
  echo "::error::Tabellen ohne RLS nach Restore: $unprotected"
  exit 1
fi
policies=$("$PSQL" "$DRILL_DB_URL" -qtA -c \
  "select count(*) from pg_policies where schemaname = 'public'")
[ "$policies" -gt 0 ] || {
  echo "::error::Keine einzige Policy nach Restore — RLS wäre eine leere Hülle."
  exit 1
}
"$PSQL" "$DRILL_DB_URL" -qtA -c \
  "select 'public.my_group_active()'::regprocedure" >/dev/null || {
  echo "::error::my_group_active() fehlt — jede Policy, die sie ruft, wäre kaputt."
  exit 1
}
echo "  RLS auf allen Tabellen, $policies Policies, my_group_active() vorhanden"

echo "→ GoTrue gegen das wiederhergestellte auth-Schema …"
# GoTrue lief während des Schema-Tauschs weiter; die ersten Anfragen können
# an gestorbenen Verbindungen scheitern. Kurz anklopfen statt sofort rot.
listed=""
for _ in $(seq 1 10); do
  code=$(curl -s -o "$workdir/users.json" -w '%{http_code}' \
    -H "apikey: $DRILL_SERVICE_KEY" \
    -H "Authorization: Bearer $DRILL_SERVICE_KEY" \
    "$DRILL_API_URL/auth/v1/admin/users?per_page=1" || echo 000)
  if [ "$code" = "200" ]; then listed=1; break; fi
  sleep 3
done
[ -n "$listed" ] || {
  echo "::error::GoTrue liefert die wiederhergestellten Nutzer nicht (zuletzt HTTP $code)."
  exit 1
}

# Anlegen + Anmelden beweist den vollen Auth-Pfad auf dem restaurierten
# Schema — inklusive des Signup-Triggers on_auth_user_created, der aus dem
# Dump zurückkommen muss. account_type=admin, damit er wie im Betrieb
# keine Geister-Gruppe anlegt.
echo "→ Wegwerf-Konto anlegen und anmelden …"
drill_mail="drill-restore@example.com"
drill_pass="drill-restore-only"
code=$(curl -s -o "$workdir/create.json" -w '%{http_code}' \
  -X POST \
  -H "apikey: $DRILL_SERVICE_KEY" \
  -H "Authorization: Bearer $DRILL_SERVICE_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$drill_mail\",\"password\":\"$drill_pass\",\"email_confirm\":true,\"user_metadata\":{\"account_type\":\"admin\"}}" \
  "$DRILL_API_URL/auth/v1/admin/users" || echo 000)
[ "$code" = "200" ] || {
  echo "::error::Konto-Anlage auf restauriertem Schema scheitert (HTTP $code) — der Signup-Trigger oder das auth-Schema sind nicht heil."
  exit 1
}
code=$(curl -s -o "$workdir/login.json" -w '%{http_code}' \
  -X POST \
  -H "apikey: $DRILL_ANON_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"$drill_mail\",\"password\":\"$drill_pass\"}" \
  "$DRILL_API_URL/auth/v1/token?grant_type=password" || echo 000)
[ "$code" = "200" ] && jq -e '.access_token' "$workdir/login.json" >/dev/null || {
  echo "::error::Anmeldung auf restauriertem Schema scheitert (HTTP $code)."
  exit 1
}

# Die wertvollste Prüfung, wenn möglich: Ein Login mit einem WIEDER-
# HERGESTELLTEN Passwort-Hash. Das Testkonto existiert nur, wo es angelegt
# wurde — fehlt es im Dump, wird das hier ehrlich übersprungen statt
# vorgetäuscht.
test_mail="test@grp.fahrgemeinschaft.app"
has_test=$("$PSQL" "$DRILL_DB_URL" -qtA -c \
  "select count(*) from auth.users where email = '$test_mail'")
if [ "$has_test" = "1" ]; then
  echo "→ Login mit wiederhergestelltem Hash (Testkonto) …"
  code=$(curl -s -o "$workdir/testlogin.json" -w '%{http_code}' \
    -X POST \
    -H "apikey: $DRILL_ANON_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$test_mail\",\"password\":\"testtest\"}" \
    "$DRILL_API_URL/auth/v1/token?grant_type=password" || echo 000)
  [ "$code" = "200" ] || {
    echo "::error::Testkonto-Login scheitert (HTTP $code) — die wiederhergestellten Passwort-Hashes greifen nicht."
    exit 1
  }
  echo "  Hash-Beweis erbracht: Login mit Bestandskonto funktioniert"
else
  echo "  (kein Testkonto im Dump — Hash-Beweis entfällt, Anlage+Login oben bleibt der Beleg)"
fi

echo "✓ Drill bestanden: entschlüsselbar, einspielbar, RLS aktiv, Auth lebt."
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Restore-Drill"
    echo ""
    echo "- Eingespielt mit ON_ERROR_STOP: ✓"
    echo "- Gruppen: $groups · Fahrten: $trips · Auth-Nutzer: $users"
    echo "- RLS auf allen public-Tabellen, $policies Policies"
    echo "- GoTrue: Konto-Anlage + Login ✓$([ "$has_test" = "1" ] && echo " · Bestands-Hash ✓")"
  } >> "$GITHUB_STEP_SUMMARY"
fi

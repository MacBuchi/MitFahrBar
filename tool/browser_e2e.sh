#!/usr/bin/env bash
# browser_e2e.sh – Browser-E2E der Verwalter-Konsole (Issue #71), ein Befehl.
#
# Startet den lokalen Supabase-Stack (Docker + Supabase-CLI), baut die
# Web-App dagegen, liefert sie auf :8731 aus und fährt den Playwright-Flow
# aus tool/browser_e2e/console.mjs: Registrieren → Bestätigungs-Mail aus
# Mailpit → zurück in die App → Gruppe verknüpfen. Screenshots landen in
# tool/browser_e2e/shots/ — bei Fehlschlag zuerst dort nachsehen.
#
# Wichtig: config.toml setzt site_url auf http://localhost:8731, damit die
# Auth-Links aus den Mails in die lokal ausgelieferte App zurückführen.
#
# Welcher Flow läuft, sagt das erste Argument (Vorgabe: console). Der Stack
# und der Web-Build sind für beide dieselben — zweimal aufgesetzt wären es
# zwei Wahrheiten über den Testaufbau, und der Lauf dauert doppelt.
#
#   tool/browser_e2e.sh            # Verwalter-Konsole (#71)
#   tool/browser_e2e.sh offline    # Start mit und ohne Netz (#169, #232)
set -euo pipefail
cd "$(dirname "$0")/.."

FLOW="${1:-console}"
case "$FLOW" in
  console | offline) ;;
  *)
    echo "Unbekannter Flow: $FLOW (console|offline)" >&2
    exit 2
    ;;
esac

command -v supabase >/dev/null 2>&1 || { echo "Supabase-CLI fehlt." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "Node fehlt." >&2; exit 1; }

echo "== Lokalen Supabase-Stack starten =="
supabase start
eval "$(supabase status -o env)"
export E2E_SUPABASE_URL="$API_URL"
export E2E_SUPABASE_ANON_KEY="$ANON_KEY"
export E2E_SUPABASE_SERVICE_KEY="$SERVICE_ROLE_KEY"
# Ältere CLI-Versionen nennen die Mailpit-URL noch INBUCKET_URL.
export E2E_MAILPIT_URL="${MAILPIT_URL:-${INBUCKET_URL:?Mailpit-URL fehlt}}"

# **Gebaut wird, was auch ausgeliefert wird** — inklusive Firebase und
# inklusive CanvasKit vom CDN. Am 10.08.2026 lief hier zeitweise eine
# Gegenprobe ohne beides, um zu klären, ob Flutters App-Worker den
# Geltungsbereich übernimmt, sobald das FCM-SDK keinen registriert. Die
# Antwort war nein: **ohne Firebase steht dort gar kein Worker**, die
# Cache-Ablage bleibt leer. Damit ist die Frage beantwortet und der
# Sonderbau überflüssig; ein Testbau, der sich vom Release unterscheidet,
# misst ab hier nur noch sich selbst.
#
# --no-web-resources-cdn gehört seit #232 dazu: Der Renderer kommt sonst von
# gstatic, und was nicht im Build liegt, kann der Service Worker nicht
# vorhalten. Ohne das Flag liefe der Offline-Flow in eine weiße Seite — und
# zwar genau so, wie es auf der Live-Adresse aussähe.
echo "== Web-App gegen den Stack bauen =="
flutter build web \
  --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="$API_URL" \
  --dart-define=SUPABASE_KEY="$ANON_KEY"

# Ohne diesen Schritt trägt sw.js sein leeres Manifest aus dem Quelltext:
# Er installiert sich, cacht nichts, und der Offline-Flow scheiterte an
# etwas, das im Release längst funktioniert.
echo "== Precache-Manifest einsetzen =="
python3 tool/inject_sw_manifest.py

echo "== Ausliefern auf :8731 =="
python3 -m http.server 8731 --directory build/web >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

echo "== Playwright-Flow ($FLOW) =="
cd tool/browser_e2e
npm install --no-audit --no-fund
npx playwright install --with-deps chromium
node "$FLOW.mjs"

#!/usr/bin/env bash
# e2e.sh – E2E-Suite (test/e2e/) gegen einen ECHTEN Supabase-Stack.
#
# Ohne Umgebungsvariablen: startet den lokalen CLI-Stack (braucht Docker
# und die Supabase-CLI), setzt die Datenbank frisch auf (alle Migrationen
# aus supabase/migrations/) und lässt die Tests laufen — ein Befehl:
#
#   tool/e2e.sh
#
# Gegen einen entfernten Stack (z. B. die Proxmox-VM, doc/testbackend.md):
#
#   E2E_SUPABASE_URL=http://<vm-ip>:55321 \
#   E2E_SUPABASE_ANON_KEY=... \
#   E2E_SUPABASE_SERVICE_KEY=... \
#   E2E_MAILPIT_URL=http://<vm-ip>:55324 \
#   tool/e2e.sh
#
# (Dann ohne automatischen Reset — auf der VM bei Bedarf `supabase db reset`.)
# Zusätzliche Argumente gehen an `flutter test` durch, z. B. --name "claim".
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${E2E_SUPABASE_URL:-}" ]; then
  command -v supabase >/dev/null 2>&1 || {
    echo "Supabase-CLI fehlt (https://supabase.com/docs/guides/cli)." >&2
    exit 1
  }
  echo "== Lokalen Supabase-Stack starten (Ports 5532x) =="
  supabase start
  echo "== Datenbank frisch aufsetzen (Migrationen) =="
  supabase db reset
  eval "$(supabase status -o env)"
  export E2E_SUPABASE_URL="$API_URL"
  export E2E_SUPABASE_ANON_KEY="$ANON_KEY"
  export E2E_SUPABASE_SERVICE_KEY="$SERVICE_ROLE_KEY"
  # Ältere CLI-Versionen nennen die Mailpit-URL noch INBUCKET_URL.
  export E2E_MAILPIT_URL="${MAILPIT_URL:-${INBUCKET_URL:?Mailpit-URL fehlt}}"
fi

echo "== E2E-Tests gegen $E2E_SUPABASE_URL =="
flutter test test/e2e "$@"

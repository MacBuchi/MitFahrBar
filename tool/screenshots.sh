#!/usr/bin/env bash
# screenshots.sh – erzeugt die README-Screenshots neu (doc/screenshots/).
#
# Die Bilder im Repo sind Erzeugnisse, kein Handwerk: Wer die Oberfläche
# ändert, lässt dieses Skript laufen, statt Bilder nachzubauen. In der CI
# macht das der Workflow „Screenshots" bei jeder Änderung an lib/, assets/
# oder web/ selbst.
#
# Gebaut wird im **Demo-Modus** (Platzhalter-URL): In-Memory-Daten, kein
# Login, immer dieselben vier Personen — nie echte Gruppendaten.
#
#   ./tool/screenshots.sh          # Port 8731
#   ./tool/screenshots.sh 9000     # anderer Port
set -euo pipefail

port="${1:-8731}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

command -v node >/dev/null || { echo "node fehlt — Playwright braucht Node.js." >&2; exit 1; }

echo "→ Demo-Build …"
flutter build web --dart-define=SUPABASE_URL=https://REPLACE-ME.supabase.co

echo "→ Playwright bereitstellen …"
work="$(mktemp -d)"
trap 'rm -rf "$work"; [ -n "${server_pid:-}" ] && kill "$server_pid" 2>/dev/null || true' EXIT
(cd "$work" && npm init -y >/dev/null && npm install --silent playwright >/dev/null)
(cd "$work" && npx --yes playwright install --with-deps chromium >/dev/null 2>&1 \
  || npx --yes playwright install chromium >/dev/null)

echo "→ ausliefern auf Port $port …"
(cd build/web && python3 -m http.server "$port" >/dev/null 2>&1) &
server_pid=$!
for _ in $(seq 1 30); do
  curl -sf "http://localhost:$port/" >/dev/null && break
  sleep 1
done

echo "→ Screenshots …"
mkdir -p doc/screenshots
# Der alte Stand für den Vergleich hinterher — zwei Läufe sind nie
# bitgleich (animierte Gesichter), siehe screenshot_changed.mjs.
mkdir -p "$work/before"
cp doc/screenshots/*.png "$work/before/" 2>/dev/null || true
# Die Skripte laufen im Arbeitsverzeichnis neben node_modules: ESM-Importe
# ignorieren NODE_PATH, „playwright" ist sonst nicht auflösbar.
cp tool/screenshots.mjs tool/screenshot_changed.mjs "$work/"
(cd "$work" && SCREENSHOT_URL="http://localhost:$port/" \
  SCREENSHOT_OUT="$root/doc/screenshots" \
  node screenshots.mjs)

# Nur Rauschen? Dann den alten Stand zurückholen, damit weder ein Commit
# noch ein Diff entsteht.
verdict="$(cd "$work" && node screenshot_changed.mjs before "$root/doc/screenshots")"
if [ "$verdict" = 'unchanged' ]; then
  echo "→ nur Animations-Rauschen — alter Stand bleibt."
  cp "$work"/before/*.png doc/screenshots/ 2>/dev/null || true
fi

echo "✓ fertig — doc/screenshots/"

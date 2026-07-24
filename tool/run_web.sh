#!/usr/bin/env bash
# run_web.sh – MitFahrBar als Web-App bauen und im Standardbrowser öffnen.
#
# Für macOS UND Linux; der Unterschied ist nur der Öffnen-Befehl, den das
# Skript selbst erkennt. Für Windows liegt daneben `run_web.ps1`.
#
#   ./tool/run_web.sh          # Port 8080
#   ./tool/run_web.sh 9000     # anderer Port
#
# Beenden mit Strg-C; der Server wird dabei mit beendet.
set -euo pipefail

PORT="${1:-${RIDEBUDDY_PORT:-8080}}"
HOST=127.0.0.1
URL="http://${HOST}:${PORT}"

cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Fehler: 'flutter' ist nicht im PATH." >&2
  echo "Flutter installieren (https://flutter.dev) oder das SDK in den PATH" >&2
  echo "aufnehmen, zum Beispiel:" >&2
  echo "  export PATH=\"/Pfad/zum/flutter/bin:\$PATH\"" >&2
  exit 1
fi

# Den Standardbrowser öffnet jede Plattform anders.
open_browser() {
  if command -v open >/dev/null 2>&1; then
    open "$1"                       # macOS
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1   # Linux (Desktop)
  else
    echo "Kein Öffnen-Befehl gefunden – bitte selbst aufrufen: $1"
  fi
}

# Erreichbarkeit prüfen: curl bevorzugt, sonst wget.
is_up() {
  if command -v curl >/dev/null 2>&1; then
    curl -sf -o /dev/null "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O /dev/null "$1"
  else
    return 1
  fi
}

echo "MitFahrBar wird gebaut und auf ${URL} ausgeliefert …"
echo "(Der erste Build dauert etwa eine halbe Minute.)"

# Eigene Prozessgruppe, damit am Ende auch die Kindprozesse enden.
set -m
flutter run -d web-server --release \
  --web-port "$PORT" --web-hostname "$HOST" &
FLUTTER_PID=$!
set +m

cleanup() {
  trap - EXIT INT TERM
  kill -- "-${FLUTTER_PID}" 2>/dev/null || kill "$FLUTTER_PID" 2>/dev/null || true
  wait "$FLUTTER_PID" 2>/dev/null || true
  echo
  echo "Server beendet."
}
trap cleanup EXIT INT TERM

# Warten, bis wirklich ausgeliefert wird – nicht bloß, bis der Port belegt ist.
opened=false
for _ in $(seq 1 180); do
  if ! kill -0 "$FLUTTER_PID" 2>/dev/null; then
    echo "Fehler: Der Build wurde vorzeitig beendet." >&2
    exit 1
  fi
  if is_up "$URL"; then
    echo "Bereit – öffne den Standardbrowser."
    open_browser "$URL"
    opened=true
    break
  fi
  sleep 1
done

if [ "$opened" = false ]; then
  echo "Zeitüberschreitung: ${URL} antwortet nicht." >&2
  echo "Läuft dort vielleicht schon etwas anderes? Dann anderen Port wählen:" >&2
  echo "  ./tool/run_web.sh 9000" >&2
  exit 1
fi

echo "Läuft. Zum Beenden Strg-C drücken."
wait "$FLUTTER_PID"

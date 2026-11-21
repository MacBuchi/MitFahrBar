#!/bin/sh
# Startet den offiziellen Dart- und Flutter-MCP-Server für Agenten
# (`.mcp.json` und `.codex/config.toml`, #289; Vorlage TrailBuddy #239).
# Die EINE Stelle für die Auswahl der Werkzeuge:
#
#   --enable run_tests   gehört zur Kategorie `cli` und ist ab Werk AUS.
#   dart_format          AUS — formatiert wird mit `dart format .` vor
#                        jedem Push (CLAUDE.md, Workflow); ein zweiter Weg
#                        dorthin wäre nur eine zweite Gewohnheit.
#   dart_fix             AUS — schreibt Code um, ohne dass jemand hinsieht.
#   create_project       AUS — es gibt nichts anzulegen.
#   widget_inspector, flutter_driver_command, hot_reload, hot_restart
#                        AUS — brauchen eine laufende App auf einem Gerät;
#                        in einer Cloud-Sitzung gibt es keins. Die echte App
#                        prüft .claude/skills/run-web/.
#
# Zwei stille Fallen (in TrailBuddy gemessen): `analyze_files` mit
# RELATIVEN Pfaden analysiert nichts und meldet trotzdem „No errors" —
# file://-URIs übergeben. `run_tests` umgekehrt: Pfade relativ zur Wurzel,
# eine file://-URI ergibt „Does not exist". Und nie `applyFixes: true`.
#
# Das SDK: erst `dart` auf dem PATH, dann $FLUTTER_ROOT, dann das lokale
# SDK dieses Rechners, dann das Flutter eines Cloud-Images. Ohne SDK endet
# das Skript mit einer Meldung statt mit einem Server, der still nicht
# antwortet.

set -eu

DART=""
if command -v dart >/dev/null 2>&1; then
  DART=$(command -v dart)
elif [ -n "${FLUTTER_ROOT:-}" ] && [ -x "$FLUTTER_ROOT/bin/dart" ]; then
  DART="$FLUTTER_ROOT/bin/dart"
elif [ -x /Volumes/MacStore/Programming/Flutter/SDK/flutter/bin/dart ]; then
  DART=/Volumes/MacStore/Programming/Flutter/SDK/flutter/bin/dart
elif [ -x /opt/flutter/bin/dart ]; then
  FLUTTER_ROOT=/opt/flutter
  export FLUTTER_ROOT
  DART=/opt/flutter/bin/dart
fi

if [ -z "$DART" ]; then
  echo "dart_mcp.sh: kein Dart-SDK gefunden (PATH, FLUTTER_ROOT)." >&2
  exit 1
fi

# Der Server läuft in TZ=Europe/Berlin, damit `run_tests` dieselbe Zeitzone
# sieht wie die CI (#290) — in einer Cloud-Sitzung (UTC) wäre
# test/ci_timezone_test.dart sonst rot.
TZ=Europe/Berlin
export TZ

exec "$DART" mcp-server \
  --enable run_tests \
  --disable dart_format,dart_fix,create_project,widget_inspector,flutter_driver_command,hot_reload,hot_restart

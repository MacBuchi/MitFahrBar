#!/usr/bin/env bash
# config_drift.sh – Prod-Auth-Config gegen die Repo-Erwartungen prüfen (#70).
#
# Warum: Die Supabase-Auth-Einstellungen leben im Dashboard und sind für das
# Repo unsichtbar. Genau so blieb am 23.07.2026 unbemerkt, dass mit der
# Bestätigungspflicht „Neue Gruppe anfragen" in Production brach — der
# Teststack lief mit anderer Config und konnte es nicht sehen (behoben in
# v0.27.0). Dieses Skript liest die Prod-Config über die Management-API und
# schlägt Alarm, sobald eine tragende Einstellung von dem abweicht, was der
# Code voraussetzt.
#
# Bewusst NUR lesend: `supabase config push` könnte Dashboard-Einstellungen
# (Brevo-SMTP-Zugangsdaten!) überschreiben — Drift wird gemeldet, nie
# „repariert".
#
# Token: SUPABASE_ACCESS_TOKEN (in CI als Repo-Secret; läuft er ab, wird
# dieser Check rot und erinnert ans Erneuern). Lokal fällt das Skript auf
# den CLI-Login im macOS-Keychain zurück.
set -euo pipefail

PROJECT_REF="azrlhlcxhpwmxcinjovp"

TOKEN="${SUPABASE_ACCESS_TOKEN:-}"
if [ -z "$TOKEN" ] && command -v security >/dev/null 2>&1; then
  TOKEN="$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null || true)"
fi
if [ -z "$TOKEN" ]; then
  echo "FEHLER: SUPABASE_ACCESS_TOKEN fehlt (und kein CLI-Login im Keychain)." >&2
  exit 2
fi

config="$(curl -sf -H "Authorization: Bearer $TOKEN" \
  "https://api.supabase.com/v1/projects/$PROJECT_REF/config/auth")" || {
  echo "FEHLER: Management-API nicht erreichbar oder Token ungültig/abgelaufen." >&2
  exit 2
}

fail=0
expect() { # expect <json-key> <erwartet> <warum>
  local actual
  actual="$(printf '%s' "$config" | jq -r ".$1")"
  if [ "$actual" != "$2" ]; then
    echo "DRIFT: $1 = $actual (erwartet: $2) — $3"
    fail=1
  else
    echo "ok: $1 = $actual"
  fi
}

expect mailer_autoconfirm false \
  "Verwalter-Konten müssen ihr Postfach beweisen; Gruppen-Konten entstehen serverseitig (request-group). Autoconfirm AN machte die Bestätigungs-UX tot."
expect external_email_enabled true \
  "Ohne E-Mail-Auth kein Login — weder Gruppen noch Verwalter."
expect disable_signup false \
  "Signup AUS bräche die Verwalter-Registrierung (Gruppen gehen über die Function, Admins über auth.signUp)."
expect smtp_host smtp-relay.brevo.com \
  "Eigenes SMTP (Brevo) ist Pflicht: Supabases Standardversand liefert nur an Projekt-Teammitglieder."
expect smtp_admin_email noreply-mitfahrbar@mcbuchi.de \
  "Absender gehört zur authentifizierten Domain — sonst leiden Zustellbarkeit und DMARC."
expect smtp_sender_name MitFahrBar \
  "Steht als Absender im Postfach der Nutzer — der sichtbarste Rest eines alten Namens."
# site_url und uri_allow_list stehen fest verdrahtet in auth_repository.dart
# als emailRedirectTo/redirectTo. Weicht das Dashboard davon ab, weist
# Supabase die Weiterleitung ab und „Passwort vergessen" endet im Nichts —
# genau die Sorte Ausfall, die man erst merkt, wenn jemand aussperrt ist.
expect site_url https://macbuchi.github.io/MitFahrBar/ \
  "Ziel der Auth-Links; muss der Pages-URL und auth_repository.dart entsprechen."
expect uri_allow_list https://macbuchi.github.io/MitFahrBar/ \
  "Ohne passende Allow-List weist Supabase das emailRedirectTo aus auth_repository.dart ab."

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Die Prod-Auth-Config weicht vom erwarteten Stand ab. Entweder war die"
  echo "Dashboard-Änderung Absicht (dann HIER die Erwartung nachziehen und"
  echo "prüfen, was im Code an der Einstellung hängt) — oder sie war es nicht"
  echo "(dann im Dashboard zurückstellen). Kontext: CLAUDE.md, Issue #70."
fi
exit "$fail"

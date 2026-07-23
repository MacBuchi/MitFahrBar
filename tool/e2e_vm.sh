#!/usr/bin/env bash
# e2e_vm.sh – E2E-Suite gegen die standardmäßig GESTOPPTE Test-VM.
#
# Fährt die VM hoch, zieht den gewünschten Git-Stand, setzt die Datenbank
# frisch auf (Migrationen), lässt die Suite vom Entwicklungsrechner aus
# laufen und fährt die VM danach wieder herunter — ein Befehl.
#
# Konfiguration über die Umgebung — bewusst ohne Defaults, denn Hosts und
# IPs gehören nicht ins öffentliche Repo (Werte: lokale Secrets-Ablage):
#
#   RIDEBUDDY_PVE_SSH    z. B. root@<proxmox-host>
#   RIDEBUDDY_VM_ID      z. B. 120
#   RIDEBUDDY_VM_SSH     z. B. ridebuddy@<vm-ip>
#   RIDEBUDDY_VM_ADDR    z. B. <vm-ip>            (für die E2E_*-URLs)
#   RIDEBUDDY_VM_BRANCH  Git-Ref; Default: aktueller lokaler Branch
#   RIDEBUDDY_VM_KEEP=1  VM nach dem Lauf anlassen (z. B. für Handy-Tests)
#
# SSH-Schlüssel kommen aus der eigenen ssh-Konfiguration (~/.ssh/config).
# Zusätzliche Argumente gehen an flutter test durch.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${RIDEBUDDY_PVE_SSH:?fehlt — z. B. root@<proxmox-host>, siehe doc/testbackend.md}"
: "${RIDEBUDDY_VM_ID:?fehlt — VM-ID auf dem Proxmox-Host}"
: "${RIDEBUDDY_VM_SSH:?fehlt — z. B. ridebuddy@<vm-ip>}"
: "${RIDEBUDDY_VM_ADDR:?fehlt — <vm-ip>}"
branch="${RIDEBUDDY_VM_BRANCH:-$(git branch --show-current)}"

echo "== VM $RIDEBUDDY_VM_ID starten =="
ssh "$RIDEBUDDY_PVE_SSH" "qm start $RIDEBUDDY_VM_ID 2>/dev/null || true"

echo "== auf SSH warten =="
up=0
for _ in $(seq 1 40); do
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "$RIDEBUDDY_VM_SSH" true 2>/dev/null; then
    up=1
    break
  fi
  sleep 5
done
[ "$up" = "1" ] || { echo "VM antwortet nicht per SSH." >&2; exit 1; }

echo "== Stand '$branch' ziehen, Stack abwarten, DB frisch aufsetzen =="
ssh -o BatchMode=yes "$RIDEBUDDY_VM_SSH" "set -e
cd ~/Fahrgemeinschaft
git fetch -q origin '$branch'
git checkout -qB '$branch' 'origin/$branch'
for _ in \$(seq 1 60); do systemctl is-active --quiet supabase-stack && break; sleep 5; done
systemctl is-active --quiet supabase-stack || { echo 'Stack-Unit nicht aktiv' >&2; exit 1; }
supabase db reset"

echo "== Keys vom Stack holen =="
eval "$(ssh -o BatchMode=yes "$RIDEBUDDY_VM_SSH" \
  'cd ~/Fahrgemeinschaft && supabase status -o env' \
  | grep -E '^(ANON_KEY|SERVICE_ROLE_KEY)=')"

echo "== Suite gegen http://$RIDEBUDDY_VM_ADDR:55321 =="
rc=0
E2E_SUPABASE_URL="http://$RIDEBUDDY_VM_ADDR:55321" \
E2E_SUPABASE_ANON_KEY="$ANON_KEY" \
E2E_SUPABASE_SERVICE_KEY="$SERVICE_ROLE_KEY" \
E2E_MAILPIT_URL="http://$RIDEBUDDY_VM_ADDR:55324" \
  tool/e2e.sh "$@" || rc=$?

if [ "${RIDEBUDDY_VM_KEEP:-0}" != "1" ]; then
  echo "== VM wieder herunterfahren =="
  ssh "$RIDEBUDDY_PVE_SSH" "qm shutdown $RIDEBUDDY_VM_ID --timeout 180" || true
fi
exit "$rc"

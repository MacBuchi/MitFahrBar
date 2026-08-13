#!/usr/bin/env python3
"""demo_group.py – füllt die Play-Testgruppe mit brauchbaren Demo-Daten.

Google verlangt für die Review Zugangsdaten, wenn hinter einem Login etwas
liegt. Eine **leere** Gruppe wirkt dabei wie eine kaputte App: kein Ranking,
keine Statistik, ein leerer Wochenplan. Dieses Skript legt an, was es
braucht, damit die Gruppe wie eine benutzte aussieht.

**Es geht den Weg der App**: Anmeldung als Gruppe, danach jeder Schreibzugriff
unter RLS mit dem Zugriffstoken — kein Service-Key. Was hier durchgeht, geht
auch in der App durch; ein Rechtefehler fiele hier auf und nicht erst dem
Prüfer.

**Es ist wiederholbar.** Vorhandene Personen und Tage werden übersprungen,
Verfügbarkeiten zusammengeführt. Einmal zerklickt, stellt ein zweiter Lauf
den brauchbaren Zustand wieder her — gelöscht wird nie etwas.

    export DEMO_HANDLE=mitfahrbar
    export DEMO_PASSWORD='…'          # aus der Passwortablage, nie im Repo
    python3 tool/demo_group.py

Der Riegel unten ist der wichtige Teil: Ohne ihn schriebe ein vertippter
Handle 32 Fahrten in die **echte** Gruppe und verschöbe rückwirkend die
Punkte aller. Deshalb prüft das Skript den Gruppennamen und bricht ab, wenn
darin nicht „test" steht.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, timedelta

# Dieselben öffentlichen Werte wie in `lib/core/supabase_config.dart` — der
# Publishable-Key ist bewusst öffentlich, die Sicherheit liegt in der RLS.
URL = "https://azrlhlcxhpwmxcinjovp.supabase.co"
ANON = "sb_publishable_Fs71LcKOZdxBBFtrwQU6Tg_e9oDEzCs"

# Die Login-Adresse jeder Gruppe. Dieselbe Bildung wie in
# `core/group_login.dart` und in der Edge Function `request-group` — driftet
# eine der drei, meldet der Login „falsches Passwort" statt der Wahrheit.
LOGIN_DOMAIN = "grp.fahrgemeinschaft.app"

PEOPLE = [
    {"name": "Anna", "energy_type": "diesel", "consumption_per_100km": 5.4,
     "seats": 5, "vehicle": "Dacia Jogger"},
    {"name": "Bernd", "energy_type": "petrol", "consumption_per_100km": 6.8,
     "seats": 5, "vehicle": "VW Golf"},
    {"name": "Clara", "energy_type": "electric", "consumption_per_100km": 17.0,
     "seats": 4, "vehicle": "Renault Zoe"},
    {"name": "David", "energy_type": "diesel", "consumption_per_100km": 6.1,
     "seats": 7, "vehicle": "Ford Tourneo"},
]
ORDER = [p["name"] for p in PEOPLE]
WEEKS_BACK = 8


def call(path, payload=None, token=None, prefer=None):
    headers = {"apikey": ANON, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(f"{URL}{path}", data=data, headers=headers)
    try:
        with urllib.request.urlopen(request) as response:
            body = response.read().decode()
            return json.loads(body) if body.strip() else None
    except urllib.error.HTTPError as error:
        # Bewusst ohne die gesendeten Daten im Text: Hier stünde sonst das
        # Gruppenpasswort in der Konsole.
        raise SystemExit(f"{path} -> HTTP {error.code}") from None


def main() -> int:
    handle = os.environ.get("DEMO_HANDLE")
    password = os.environ.get("DEMO_PASSWORD")
    if not handle or not password:
        print("DEMO_HANDLE und DEMO_PASSWORD setzen.", file=sys.stderr)
        return 2

    session = call(
        "/auth/v1/token?grant_type=password",
        {"email": f"{handle}@{LOGIN_DOMAIN}", "password": password},
    )
    token = session["access_token"]

    group = call("/rest/v1/groups?select=id,name", token=token)[0]
    if "test" not in group["name"].lower() and "--force" not in sys.argv:
        print(
            f"Abbruch: „{group['name']}\" sieht nicht nach einer Testgruppe "
            "aus. Dieses Skript legt Dutzende Fahrten an und verschöbe damit "
            "rückwirkend die Punkte aller. Mit --force, wenn es wirklich "
            "gemeint ist.",
            file=sys.stderr,
        )
        return 1
    print(f"Gruppe: {group['name']}")

    # --- Personen ---------------------------------------------------------
    # Unterschiedliche Fahrzeuge, damit Ersparnis und CO2 überhaupt rechnen:
    # Beides braucht Verbrauch und Energieart. Die Sitzplätze machen den
    # Wochenplaner interessant (7-Sitzer gegen 4-Sitzer).
    known = {
        p["name"]: p["id"]
        for p in call("/rest/v1/persons?select=id,name", token=token) or []
    }
    for person in PEOPLE:
        if person["name"] in known:
            continue
        created = call(
            "/rest/v1/persons", person, token=token, prefer="return=representation"
        )
        known[person["name"]] = created[0]["id"]
    print("Personen:", ", ".join(sorted(known)))

    # --- Fahrten ----------------------------------------------------------
    # Nur Vergangenes: „Nichts wird in der Zukunft eingetragen" gilt auch
    # hier, sonst verschöbe die Demo Punkte für Fahrten, die nie stattfanden.
    seen = {
        t["trip_date"]
        for t in call("/rest/v1/trips?select=trip_date", token=token) or []
    }
    today = date.today()
    slot = 0
    created_trips = 0
    for back in range(WEEKS_BACK * 7, 0, -1):
        day = today - timedelta(days=back)
        if day.weekday() > 3:  # Mo–Do, wie im echten Betrieb
            continue
        if day.isoformat() in seen:
            continue
        driver = ORDER[slot % len(ORDER)]
        riders = [n for n in ORDER if n != driver]
        if slot % 5 == 0:
            riders = riders[:2]  # nicht immer sind alle dabei
        slot += 1

        trip = call(
            "/rest/v1/trips",
            {"trip_date": day.isoformat()},
            token=token,
            prefer="return=representation",
        )
        rows = [
            {"trip_id": trip[0]["id"], "person_id": known[driver], "status": "driver"}
        ]
        for index, rider in enumerate(riders):
            status = "one_way" if (slot + index) % 11 == 0 else "passenger"
            rows.append(
                {
                    "trip_id": trip[0]["id"],
                    "person_id": known[rider],
                    "status": status,
                }
            )
        call(
            "/rest/v1/trip_participations",
            rows,
            token=token,
            prefer="return=minimal",
        )
        created_trips += 1
    print("Fahrten neu angelegt:", created_trips)

    # --- Verfügbarkeit ----------------------------------------------------
    # Laufende UND kommende Woche: Der Prüfer landet auf der laufenden, und
    # ab Freitagmittag zeigt der Planer die kommende. Ohne beides steht dort
    # „Noch niemand verfügbar", und die Hälfte der App wirkt tot.
    monday = today - timedelta(days=today.weekday())
    rows = []
    for offset in range(12):
        day = monday + timedelta(days=offset)
        if day.weekday() > 4 or day < today:
            continue
        for index, name in enumerate(ORDER):
            if (offset + index) % 7 == 5:  # einer kann mal nicht
                continue
            rows.append(
                {
                    "plan_date": day.isoformat(),
                    "person_id": known[name],
                    "one_way": (offset + index) % 8 == 3,
                }
            )
    if rows:
        call(
            "/rest/v1/plan_availability?on_conflict=group_id,plan_date,person_id",
            rows,
            token=token,
            prefer="resolution=merge-duplicates,return=minimal",
        )
    print("Verfügbarkeiten gesetzt:", len(rows))

    persons = call("/rest/v1/persons?select=id", token=token) or []
    trips = call("/rest/v1/trips?select=id", token=token) or []
    print(f"Stand: {len(persons)} Personen, {len(trips)} Fahrten")
    return 0


if __name__ == "__main__":
    sys.exit(main())

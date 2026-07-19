#!/usr/bin/env python3
"""Einmal-Import der Excel-Historie nach Supabase.

Liest .donotsync/seed/seed.json (erzeugt aus Fahrgemeinschaft.xlsx) und
schreibt Personen, Fahrten und Teilnahmen über die PostgREST-API.

Aufruf:
  SUPABASE_URL=https://xyz.supabase.co \
  SUPABASE_SERVICE_ROLE_KEY=... \
  python3 tool/import_seed.py [--dry-run]

Der service_role-Key umgeht RLS und darf NIE eingecheckt werden.
"""
import json
import os
import sys
import urllib.request

DRY_RUN = "--dry-run" in sys.argv
SEED_PATH = os.path.join(os.path.dirname(__file__), "..", ".donotsync", "seed", "seed.json")

STATUS_TO_DB = {"driver": "driver", "passenger": "passenger", "oneWay": "one_way"}


def request(method, path, payload=None, prefer=None):
    url = os.environ["SUPABASE_URL"].rstrip("/") + "/rest/v1/" + path
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req) as resp:
        body = resp.read().decode()
        return json.loads(body) if body else None


def main():
    with open(SEED_PATH, encoding="utf-8") as fh:
        seed = json.load(fh)

    persons = seed["persons"]
    trips = seed["trips"]
    print(f"Seed: {len(persons)} Personen, {len(trips)} Fahrten")

    future = [t["date"] for t in trips if t["date"] > "2026-07-19"]
    if future:
        print(f"WARNUNG – Datumsangaben in der Zukunft (bitte in der App prüfen/korrigieren): {future}")

    if DRY_RUN:
        print("Dry-Run – nichts geschrieben.")
        return

    if "SUPABASE_URL" not in os.environ or "SUPABASE_SERVICE_ROLE_KEY" not in os.environ:
        sys.exit("SUPABASE_URL und SUPABASE_SERVICE_ROLE_KEY als Env-Variablen setzen.")

    existing = request("GET", "trips?select=id&limit=1")
    if existing:
        sys.exit("Abbruch: Es existieren bereits Fahrten in der Datenbank – Import ist nur für eine leere DB gedacht.")

    # Upsert auf name -> wiederaufsetzbar, falls Personen aus einem
    # früheren (abgebrochenen) Lauf schon existieren.
    created = request(
        "POST",
        "persons?on_conflict=name",
        [
            {
                "name": p["name"],
                "active": p["active"],
                "vehicle": p.get("vehicle"),
                "energy_type": p.get("energyType"),
                "consumption_per_100km": p.get("consumptionPer100km"),
            }
            for p in persons
        ],
        prefer="return=representation,resolution=merge-duplicates",
    )
    id_by_name = {row["name"]: row["id"] for row in created}
    print(f"{len(created)} Personen angelegt/aktualisiert.")

    created_trips = request(
        "POST",
        "trips",
        [{"trip_date": t["date"]} for t in trips],
        prefer="return=representation",
    )
    trip_id_by_date = {row["trip_date"]: row["id"] for row in created_trips}
    print(f"{len(created_trips)} Fahrten angelegt.")

    participations = [
        {
            "trip_id": trip_id_by_date[t["date"]],
            "person_id": id_by_name[name],
            "status": STATUS_TO_DB[status],
        }
        for t in trips
        for name, status in t["participations"].items()
    ]
    for start in range(0, len(participations), 500):
        request("POST", "trip_participations", participations[start:start + 500])
    print(f"{len(participations)} Teilnahmen angelegt. Import fertig.")
    print("Abnahme: Punktestände in der App mit dem Excel vergleichen (Marcus −5,5 / Thorsten −2 / Christoph 0).")


if __name__ == "__main__":
    main()

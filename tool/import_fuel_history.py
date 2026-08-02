#!/usr/bin/env python3
"""Fuellt die Spritpreis-Vergangenheit aus dem Tankerkoenig-Archiv nach.

Ohne diesen Lauf zeigt das Diagramm fuer jede Woche vor dem Live-Takt die
Konstante aus den Parametern -- also eine gerade Linie, wo Preise waren. Das
betrifft nicht nur den Start: Jede Gruppe, die ihre Fahrten spaeter per
CSV-Import nachtraegt, bringt Wochen mit, fuer die nie gemessen wurde.

## Die Datenbank ist die Warteschlange

Es gibt bewusst KEIN Auftrags-Flag und keine Zustandsdatei. Der Auftrag ist:

    Woche, in der eine Gruppe gefahren ist, ohne Zeile in `price_week`.

Das ist dasselbe Muster wie „die Existenz einer Zeile in `trips` am Tag IST
die Bestaetigung": Der Zustand wird nicht danebengeschrieben, sondern
abgeleitet. Ein zweiter Lauf ist damit automatisch die Fortsetzung des
ersten, ein abgebrochener Lauf kostet nichts, und zwei Laeufe koennen sich
nicht widersprechen. Deshalb ist auch `--max-weeks` unbedenklich: Was nicht
drankam, ist beim naechsten Aufruf einfach wieder die Luecke.

Geschrieben wird mit `resolution=ignore-duplicates`. Der Lauf kann damit
NIEMALS einen vorhandenen Wert ueberschreiben -- insbesondere keinen
gemessenen, der die genauere Wahrheit ueber seine Woche ist.

## Je Region, nicht je Gruppe

Gerechnet wird entlang `price_area.region_key` (Koordinaten auf zwei
Stellen). Zwei Gruppen in derselben Gegend teilen sich einen Download und
bekommen aus einer Auswertung ihre je eigenen Wochenzeilen -- genau wie der
Live-Takt in `supabase/functions/fuel-sample/` es auch macht.

## Dieselbe Kennzahl wie der Live-Takt

Der Wochenwert ist das 10. Perzentil derselben Stichprobe, die auch gemessen
wuerde: alle Stationen im Umkreis, abgelesen um 05:05, 11:05 und 17:05 UTC
an allen sieben Tagen. Nur so entsteht an der Naht zwischen importierter
Vergangenheit und gemessener Gegenwart keine Stufe, die keine Preisaenderung
ist -- und deshalb steht dort UTC und nicht Ortszeit, siehe SAMPLE_TIMES_UTC.

Drei Dinge daran sind gemessen, nicht geraten (Wochen aus 2023, 2024 und
2026, Region Bad Rappenau):

- **Alle sieben Tage, nicht nur die Fahrtage.** Nur Mo-Do zoege das
  Wochen-P10 systematisch um bis zu 1 ct nach unten -- Freitag und Samstag
  sind die teuren Tage. Es waere ein Drittel des Downloads gewesen und genau
  die Stufe, die wir vermeiden.
- **Ein Tag je Woche reicht nicht.** Mittwoch allein wich um -2 bis +2 ct
  ab, in beide Richtungen: kein Versatz, den man herausrechnen koennte,
  sondern Rauschen.
- **Oeffnungszeiten aendern nichts.** Der Live-Takt filtert geschlossene
  Stationen; hier ergaben sich in allen Probewochen identische Werte,
  deshalb wird der Aufwand nicht getrieben.

## Die Preisdatei ist ein Protokoll, kein Abbild

`prices/YYYY/MM/*.csv` enthaelt PreisAENDERUNGEN. Der Preis zur Stichzeit ist
die letzte Aenderung davor -- die kann von gestern sein. Deshalb wird eine
Woche immer am Stueck und der Reihe nach gelesen: Jeder Tag traegt den
naechsten.

Am ersten Tag gibt es keinen Vorgaenger; dort sind morgens oft nur eine
Handvoll Stationen bekannt -- und zwar gerade die aggressiv umpreisenden,
also die billigen. Diese Momentaufnahme mitzuzaehlen zoege das Perzentil
nach unten. Deshalb zaehlt sie nur, wenn sie MIN_COVERAGE der Stationen
kennt. Weggelassen wird damit ein Zeitpunkt, nie eine Teilmenge von
Stationen -- das ist der Unterschied zwischen weniger Daten und schiefen
Daten.

## Zugang

DIE ARCHIV-ZUGANGSDATEN SIND PERSOENLICH UND GEHOEREN NICHT INS REPO. In CI
kommen sie aus Secrets, lokal aus ~/mitfahrbar-keys/Tankerkoenig_Archiv.txt.
Das Passwort ist derselbe Wert wie der Live-API-Key -- ein Leck oeffnet
beides. Lizenz der Sammlung: CC BY-NC-SA 4.0 (nicht die CC BY 4.0 der
Live-API): nicht-kommerziell, Namensnennung, Weitergabe abgeleiteter Daten
unter gleicher Lizenz. Die Wochenwerte bleiben in der Gruppendatenbank und
werden nicht verbreitet -- SA greift damit nicht, BY steht in README und
"Ueber MitFahrBar".

Aufruf (in CI wie lokal identisch):

    SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... \\
    TANKERKOENIG_ARCHIVE_USER=... TANKERKOENIG_ARCHIVE_PASSWORD=... \\
    python3 tool/import_fuel_history.py --max-weeks 100

Ohne `SUPABASE_SERVICE_ROLE_KEY` tut das Skript nichts (wie feedback_bot.py
und notify.dart). `--dry-run` zeigt nur die Luecke.
"""
import argparse
import base64
import csv
import datetime as dt
import io
import json
import math
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request

BASE = ('https://data.tankerkoenig.de/tankerkoenig-organization'
        '/tankerkoenig-data/raw/branch/master')
KEYFILE = pathlib.Path.home() / 'mitfahrbar-keys' / 'Tankerkoenig_Archiv.txt'

# Dieselben Stichzeiten wie `sample-fuel-prices` -- und zwar in UTC, weil
# pg_cron in UTC rechnet: '5 5,11,17 * * *' in
# 20260802110000_fuel_sample_cron.sql. Ortszeit waere hier der naheliegende,
# aber falsche Griff: Der Live-Takt tastet im Winter eine Stunde frueher ab
# (06:05/12:05/18:05 statt 07:05/13:05/19:05). Feste Ortszeiten im Import
# ergaeben also genau im Winterhalbjahr eine andere Frage als die gemessene
# -- die Stufe an der Naht, die dieses ganze Vorgehen vermeiden soll.
SAMPLE_TIMES_UTC = (dt.time(5, 5), dt.time(11, 5), dt.time(17, 5))
SERIES = ('diesel', 'e5', 'e10')

# Muss zu `defaultPercentile` in lib/core/price_series.dart und zu
# percentile_cont(0.10) in rollup_fuel_weeks() passen. Drei Stellen, EINE
# Zahl -- wer sie hier aendert, aendert sie dort mit.
PERCENTILE = 0.10

# Anteil der Stationen, den eine Momentaufnahme kennen muss, um zu zaehlen.
MIN_COVERAGE = 0.60

# Vor Mitte 2014 gibt es das Archiv nicht. Ohne diese Grenze liefe der Job
# fuer eine (versehentlich) sehr alte Fahrt sieben 404er je Woche, immer
# wieder -- die Luecke bliebe ja bestehen.
ARCHIVE_START = dt.date(2014, 6, 1)

PAGE = 1000


# --------------------------------------------------------------------------
# Supabase

def api(method, path, body=None, prefer=None):
    url = os.environ['SUPABASE_URL'].rstrip('/') + path
    key = os.environ['SUPABASE_SERVICE_ROLE_KEY']
    headers = {'apikey': key, 'Content-Type': 'application/json'}
    # Alte service_role-Keys sind JWTs und brauchen zusaetzlich Authorization;
    # neue sb_secret_*-Keys nur den apikey-Header.
    if key.startswith('eyJ'):
        headers['Authorization'] = f'Bearer {key}'
    if prefer:
        headers['Prefer'] = prefer
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers,
                                     method=method)
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode()
        return json.loads(text) if text else None


def select_all(path):
    """Alle Zeilen holen. PostgREST deckelt bei 1000 -- ohne Blaettern
    fehlten ab der 1001. Fahrt still die aeltesten Wochen."""
    rows, offset = [], 0
    joiner = '&' if '?' in path else '?'
    while True:
        page = api('GET', f'{path}{joiner}limit={PAGE}&offset={offset}') or []
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        offset += PAGE


def iso_week_of(day):
    return day.isocalendar()[:2]


def monday_of(iso_year, iso_week):
    return dt.date.fromisocalendar(iso_year, iso_week, 1)


def load_state():
    """Regionen, gefahrene Wochen je Gruppe und was schon dasteht."""
    areas = select_all('/rest/v1/price_area'
                       '?select=group_id,lat,lng,radius_km,region_key')
    regions = {}
    for area in areas:
        entry = regions.setdefault(area['region_key'], {
            'lat': float(area['lat']),
            'lng': float(area['lng']),
            'radius': float(area['radius_km']),
            'groups': [],
        })
        entry['groups'].append(area['group_id'])

    driven = {}
    for trip in select_all('/rest/v1/trips?select=group_id,trip_date'):
        day = dt.date.fromisoformat(trip['trip_date'])
        driven.setdefault(trip['group_id'], set()).add(iso_week_of(day))

    have = {}
    for row in select_all('/rest/v1/price_week'
                          '?select=group_id,iso_year,iso_week'):
        have.setdefault(row['group_id'], set()).add(
            (row['iso_year'], row['iso_week']))

    return regions, driven, have


def gaps_for(region, driven, have, today):
    """Fehlende Wochen der Region: Vereinigung ueber ihre Gruppen.

    Nur abgeschlossene Wochen. Eine laufende Woche zu importieren waere
    doppelt falsch: Sie ist unvollstaendig, und danach ist sie keine Luecke
    mehr -- der Live-Verdichter wuerde sie nie mehr ergaenzen, weil
    `ignore-duplicates` die vorhandene Zeile stehen laesst.
    """
    weeks = set()
    for group_id in region['groups']:
        for year, week in driven.get(group_id, set()):
            if (year, week) in have.get(group_id, set()):
                continue
            monday = monday_of(year, week)
            if monday < ARCHIVE_START or monday + dt.timedelta(days=7) > today:
                continue
            weeks.add((year, week))
    return sorted(weeks)


# --------------------------------------------------------------------------
# Archivzugang

def archive_auth():
    user = os.environ.get('TANKERKOENIG_ARCHIVE_USER')
    password = os.environ.get('TANKERKOENIG_ARCHIVE_PASSWORD')
    if not (user and password) and KEYFILE.exists():
        for line in KEYFILE.read_text(encoding='utf-8').splitlines():
            if line.startswith('BENUTZER=') and not user:
                user = line.split('=', 1)[1].strip()
            elif line.startswith('PASSWORT=') and not password:
                password = line.split('=', 1)[1].strip()
    if not (user and password):
        sys.exit('Archiv-Zugangsdaten fehlen (TANKERKOENIG_ARCHIVE_USER / '
                 f'_PASSWORD oder {KEYFILE}).')
    return 'Basic ' + base64.b64encode(f'{user}:{password}'.encode()).decode()


def fetch(path, auth, retries=3):
    """Eine Archivdatei holen; None, wenn es sie nicht gibt.

    Der Kopf wird von Hand gesetzt statt ueber einen HTTPBasicAuthHandler:
    Der kassierte erst eine 401 und wiederholte den Abruf -- bei 30 MB je
    Datei zweimal derselbe Weg durch die Leitung.
    """
    request = urllib.request.Request(
        f'{BASE}/{path}',
        headers={'Authorization': auth, 'User-Agent': 'MitFahrBar-Import'})
    last = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                return response.read().decode('utf-8', errors='replace')
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            if error.code in (401, 403):
                sys.exit(f'Archiv weist ab ({error.code}) -- Zugang pruefen.')
            last = error
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last = error
        if attempt < retries - 1:
            time.sleep(5 * (attempt + 1))
    print(f'    ! {path}: {last}', file=sys.stderr)
    return None


def distance_km(lat_a, lng_a, lat_b, lng_b):
    value = (math.sin(math.radians(lat_a)) * math.sin(math.radians(lat_b))
             + math.cos(math.radians(lat_a)) * math.cos(math.radians(lat_b))
             * math.cos(math.radians(lng_b - lng_a)))
    return 6371.0 * math.acos(min(1.0, max(-1.0, value)))


def stations_for(month, region, auth, cache):
    """UUIDs im Umkreis, Stand des jeweiligen Monats.

    Der Bestand aendert sich langsam, ueber Jahre aber doch (97 Stationen
    Anfang 2023, 103 im Juli 2026). Ein fester Bestand unterschlaege spaetere
    Stationen und schleppte frueher geschlossene mit. Monatlich statt
    taeglich trifft den Unterschied zu einem Bruchteil der Abrufe.
    """
    key = (region['region_key'], month)
    if key in cache:
        return cache[key]
    text = None
    for offset in range(7):     # Monatserster kann fehlen
        day = month + dt.timedelta(days=offset)
        text = fetch(f'stations/{day:%Y/%m}/{day}-stations.csv', auth)
        if text:
            break
    if not text:
        cache[key] = set()
        return cache[key]

    uuids = set()
    for row in csv.DictReader(io.StringIO(text)):
        try:
            lat, lng = float(row['latitude']), float(row['longitude'])
        except (ValueError, TypeError, KeyError):
            continue
        if distance_km(region['lat'], region['lng'], lat, lng) <= region['radius']:
            uuids.add(row['uuid'])
    cache[key] = uuids
    return uuids


# --------------------------------------------------------------------------
# Auswertung

def percentile(values, fraction):
    """Lineare Interpolation zwischen den Rangwerten -- zeichengenau die
    Definition von percentile_cont() in rollup_fuel_weeks()."""
    ordered = sorted(values)
    if not ordered:
        return None
    position = fraction * (len(ordered) - 1)
    low, high = math.floor(position), math.ceil(position)
    if low == high:
        return ordered[low]
    return ordered[low] + (ordered[high] - ordered[low]) * (position - low)


def read_day(day, uuids, auth):
    """Preisaenderungen eines Tages, auf die Region gefiltert und sortiert.

    Die Sortierung wird NICHT vorausgesetzt: Die Dateien sind zwar
    chronologisch, aber davon haengt die Richtigkeit jeder Momentaufnahme ab
    -- und gut tausend Regionszeilen zu sortieren kostet nichts.
    """
    text = fetch(f'prices/{day:%Y/%m}/{day}-prices.csv', auth)
    if text is None:
        return None, None
    rows = []
    offset = None
    for line in text.splitlines():
        # Nur zwei Felder abspalten, um die Station zu pruefen: Der volle
        # Split lohnt sich fuer 0,7 % der Zeilen nicht.
        parts = line.split(',', 2)
        if len(parts) < 3 or parts[1] not in uuids:
            continue
        fields = line.split(',')
        if len(fields) < 5:
            continue
        prices = {}
        for name, index in (('diesel', 2), ('e5', 3), ('e10', 4)):
            try:
                value = float(fields[index])
            except (ValueError, IndexError):
                continue
            # 0,000 heisst „wird hier nicht angeboten". Als Null gezaehlt
            # zoege es das Perzentil auf den Boden.
            if value > 0:
                prices[name] = value
        if prices:
            # '2026-07-29 00:01:20+02' -> Ortszeit und Versatz getrennt. Der
            # Versatz kommt aus den Daten selbst statt aus einer
            # Zeitzonen-Datenbank: Er steht in jeder Zeile, und der Runner
            # braucht so kein tzdata.
            if offset is None and len(fields[0]) > 19:
                offset = parse_offset(fields[0][19:])
            rows.append((fields[0][:19], parts[1], prices))
    rows.sort(key=lambda row: row[0])
    return rows, offset


def parse_offset(text):
    """'+02' oder '+02:00' -> Minuten. Am Umstellungstag hat eine Datei zwei
    Versaetze; genommen wird der erste. Das verschiebt an zwei Tagen im Jahr
    eine Momentaufnahme um eine Stunde -- gegenüber 21 Aufnahmen je Woche
    keine Groesse, fuer die sich eine Zeitzonen-Abhaengigkeit lohnt."""
    try:
        sign = -1 if text[0] == '-' else 1
        parts = text.lstrip('+-').split(':')
        return sign * (int(parts[0]) * 60 + (int(parts[1]) if len(parts) > 1 else 0))
    except (ValueError, IndexError):
        return None


def take_snapshot(last, uuids, samples, seen, counters):
    """Eine Momentaufnahme uebernehmen -- oder verwerfen, wenn zu duenn."""
    if len(last) < MIN_COVERAGE * len(uuids):
        counters['dropped'] += 1
        return
    counters['snapshots'] += 1
    for uuid, prices in last.items():
        seen.add(uuid)
        for name, value in prices.items():
            samples[name].append(value)


def collect_week(monday, region, auth, cache, delay):
    """Eine Woche einlesen. `last` traegt den letzten bekannten Preis ueber
    die Tage hinweg -- der Grund, warum die Woche am Stueck gelesen wird."""
    uuids = stations_for(monday.replace(day=1), region, auth, cache)
    if not uuids:
        return None, 'keine Stationen im Umkreis'

    last, seen = {}, set()
    samples = {name: [] for name in SERIES}
    counters = {'snapshots': 0, 'dropped': 0, 'missing': 0}

    for offset in range(7):
        day = monday + dt.timedelta(days=offset)
        if offset and delay:
            time.sleep(delay)
        rows, offset = read_day(day, uuids, auth)
        if rows is None:
            counters['missing'] += 1
            continue
        # Die Stichzeiten stehen in UTC; verglichen wird gegen die Ortszeit
        # in der Datei. Ohne Versatz (leerer Tag) bleibt die Woche ohne
        # Aufnahme -- besser als eine um zwei Stunden verschobene.
        if offset is None:
            counters['missing'] += 1
            continue
        marks = [
            f'{dt.datetime.combine(day, mark) + dt.timedelta(minutes=offset):%Y-%m-%d %H:%M:%S}'
            for mark in SAMPLE_TIMES_UTC
        ]
        cursor = 0
        for stamp, uuid, prices in rows:
            while cursor < len(marks) and stamp > marks[cursor]:
                take_snapshot(last, uuids, samples, seen, counters)
                cursor += 1
            last[uuid] = prices
        while cursor < len(marks):
            take_snapshot(last, uuids, samples, seen, counters)
            cursor += 1

    if counters['missing'] == 7:
        return None, 'alle sieben Tagesdateien fehlen'
    if counters['snapshots'] == 0:
        return None, f'keine belastbare Momentaufnahme ({counters["dropped"]} zu duenn)'
    return {'samples': samples, 'stations': len(seen), **counters}, None


# --------------------------------------------------------------------------

def summary(lines):
    print('\n'.join(lines))
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write('\n'.join(lines) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--max-weeks', type=int, default=100,
                        help='Obergrenze je Lauf (Vorgabe 100). Der Rest '
                             'bleibt Luecke und kommt beim naechsten Lauf.')
    parser.add_argument('--delay', type=float, default=0.0,
                        help='Pause zwischen den Abrufen in Sekunden')
    parser.add_argument('--dry-run', action='store_true',
                        help='Nur die Luecke zeigen, nichts laden')
    args = parser.parse_args()

    if not os.environ.get('SUPABASE_SERVICE_ROLE_KEY'):
        print('::notice::SUPABASE_SERVICE_ROLE_KEY fehlt — nichts zu tun.')
        return
    if not os.environ.get('SUPABASE_URL'):
        sys.exit('SUPABASE_URL fehlt.')

    regions, driven, have = load_state()
    if not regions:
        summary(['Keine Region eingerichtet — nichts zu tun.'])
        return

    today = dt.date.today()
    todo = {}
    for region_key, region in regions.items():
        region['region_key'] = region_key
        missing = gaps_for(region, driven, have, today)
        if missing:
            todo[region_key] = missing

    outstanding = sum(len(weeks) for weeks in todo.values())
    if not outstanding:
        summary([f'{len(regions)} Region(en), keine Lücke — nichts zu tun.'])
        return

    print(f'{len(regions)} Region(en), {outstanding} offene Woche(n), '
          f'Obergrenze {args.max_weeks} für diesen Lauf.')
    if args.dry_run:
        for region_key, weeks in todo.items():
            print(f'  {region_key}: {len(weeks)} Wochen, '
                  f'{weeks[0][0]}-W{weeks[0][1]:02d} bis '
                  f'{weeks[-1][0]}-W{weeks[-1][1]:02d}')
        return

    auth = archive_auth()
    cache, pending = {}, []
    done = skipped = 0
    budget = args.max_weeks
    started = time.time()

    for region_key, weeks in todo.items():
        region = regions[region_key]
        for year, week in weeks:
            if budget <= 0:
                break
            budget -= 1
            monday = monday_of(year, week)
            entry, problem = collect_week(monday, region, auth, cache,
                                          args.delay)
            if problem:
                print(f'  {year}-W{week:02d} übersprungen: {problem}')
                skipped += 1
                continue

            values = []
            for name in SERIES:
                value = percentile(entry['samples'][name], PERCENTILE)
                if value is not None:
                    values.append((name, value, len(entry['samples'][name])))
            if not values:
                skipped += 1
                continue

            # Eine Auswertung, je Gruppe der Region eine Zeile -- aber nur
            # fuer die Gruppen, denen die Woche wirklich fehlt.
            for group_id in region['groups']:
                if (year, week) in have.get(group_id, set()):
                    continue
                if (year, week) not in driven.get(group_id, set()):
                    continue
                for name, value, count in values:
                    pending.append({
                        'group_id': group_id,
                        'iso_year': year, 'iso_week': week, 'series': name,
                        'value': round(value, 3),
                        'sample_count': count,
                        'station_count': entry['stations'],
                        'origin': 'imported',
                    })
            done += 1
            print(f'  {year}-W{week:02d}  ' + '  '.join(
                f'{name} {value:.3f}' for name, value, _ in values)
                + f'  ({entry["snapshots"]} Aufnahmen, {entry["dropped"]} '
                  f'verworfen, {entry["stations"]} Stationen)')

            if len(pending) >= 300:
                # `ignore-duplicates`: Der Lauf kann keinen vorhandenen Wert
                # ueberschreiben -- schon gar keinen gemessenen.
                api('POST', '/rest/v1/price_week', pending,
                    prefer='resolution=ignore-duplicates,return=minimal')
                pending = []
        if budget <= 0:
            break

    if pending:
        api('POST', '/rest/v1/price_week', pending,
            prefer='resolution=ignore-duplicates,return=minimal')

    remaining = outstanding - done - skipped
    minutes = (time.time() - started) / 60
    lines = [f'### Preisarchiv nachgefüllt',
             '',
             f'- Wochen geschrieben: **{done}** (in {minutes:.0f} min)']
    if skipped:
        lines.append(f'- Übersprungen (keine Archivdaten): {skipped}')
    if remaining > 0:
        lines.append(f'- **Noch offen: {remaining} Wochen** — Workflow erneut '
                     'starten, der Lauf setzt von selbst dort fort.')
    else:
        lines.append('- Keine Lücke mehr offen.')
    summary(lines)


if __name__ == '__main__':
    main()

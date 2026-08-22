#!/usr/bin/env python3
"""Fuellt die Spritpreis-Vergangenheit aus dem Tankerkoenig-Archiv nach.

Ohne diesen Lauf zeigt das Diagramm fuer jede Woche vor dem Live-Takt die
Konstante aus den Parametern -- also eine gerade Linie, wo Preise waren. Das
betrifft nicht nur den Start: Jede Gruppe, die ihre Fahrten spaeter per
CSV-Import nachtraegt, bringt Wochen mit, fuer die nie gemessen wurde.

## Die Datenbank ist die Warteschlange

Es gibt bewusst KEIN Auftrags-Flag und keine Zustandsdatei. Der Auftrag ist:

    Woche, in der eine Gruppe gefahren ist, ohne VOLLSTAENDIGE Zeilen
    (alle drei Sorten) in `price_week`.

Das ist dasselbe Muster wie „die Existenz einer Zeile in `trips` am Tag IST
die Bestaetigung": Der Zustand wird nicht danebengeschrieben, sondern
abgeleitet. Ein zweiter Lauf ist damit automatisch die Fortsetzung des
ersten, ein abgebrochener Lauf kostet nichts, und zwei Laeufe koennen sich
nicht widersprechen. Deshalb ist auch `--max-weeks` unbedenklich: Was nicht
drankam, ist beim naechsten Aufruf einfach wieder die Luecke.

Geschrieben wird mit `resolution=ignore-duplicates`. Der Lauf kann damit
NIEMALS einen vorhandenen Wert ueberschreiben -- insbesondere keinen
gemessenen, der die genauere Wahrheit ueber seine Woche ist.

## Der Merker: die eine Ausnahme von „alles wird abgeleitet"

Seit dem naechtlichen Zeitplan (fuel-history.yml `schedule:`) gibt es genau
EINE gemerkte Sache: Wochen, die das Archiv nie fuellen wird
(`price_week_skip` -- Archivluecke, keine Stationen im Umkreis, zu duenn).
Ohne den Merker zoege der Job fuer so eine Woche jede Nacht dieselben
sieben 30-MB-Dateien; die Luecke bleibt ja bestehen. Drei Regeln daran:

- Gemerkt wird nur, was das ARCHIV gesagt hat (404, leere Region), nie
  eine Netzstoerung -- die wirft `ArchiveUnavailable` und die Woche wird
  schlicht vertagt.
- Erst MARK_AFTER_DAYS nach Wochenende: Das Archiv publiziert mit Verzug,
  eine junge Woche ist „noch nicht da", nicht „nie".
- Die Marke traegt den `region_key` ihrer Entscheidung. Verschiebt eine
  Gruppe ihr Gebiet, passt er nicht mehr und die Woche wird neu versucht;
  die alte Zeile bleibt stehen und wirkt nicht.

## Die Woche traegt den Download, nicht das Gebiet

Gerechnet wird entlang `price_area.region_key` (Koordinaten auf zwei
Stellen); zwei Gruppen in derselben Gegend bekommen aus einer Auswertung
ihre je eigenen Wochenzeilen.

**Der Download haengt aber an der WOCHE.** Sieben Tagesdateien à ~30 MB
tragen jeden Mittelpunkt in Deutschland -- gefiltert wird erst beim Lesen.
Bis August 2026 lief die Schleife trotzdem gebietsweise: Jede zusaetzliche
Gegend zahlte dieselben 210 MB noch einmal. Weil `region_key` auf ~1 km
aufloest, hat praktisch jede Gruppe ihr eigenes Gebiet -- der Aufwand wuchs
also mit der Zahl der Gruppen. Seit der Umkehr (Woche aussen, Gebiete
innen, `collect_weeks`) haengt er an der Zahl der offenen Wochen und ist
von der Zahl der Gruppen unabhaengig. `--max-weeks` zaehlt deshalb
geladene Wochen, nicht Gebiet-mal-Woche.

Gemessen wurde vorher, ob es auch ohne exakte Kreise ginge -- ein grobes
Raster haette zusaetzlich die ZEILEN geteilt (siehe `--compare-grid`). Die
Antwort war nein, und sie wird nicht gebraucht: Zeilen sind mit 156 je
Gruppe und Jahr ohnehin unkritisch, der Download war das Problem.

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

# Ueberschreibbar fuer den lokalen Probelauf gegen einen Miniatur-Server —
# der Merker-Pfad (404 -> Marke) ist sonst nur in Produktion erlebbar.
BASE = os.environ.get(
    'TANKERKOENIG_ARCHIVE_BASE',
    'https://data.tankerkoenig.de/tankerkoenig-organization'
    '/tankerkoenig-data/raw/branch/master')
KEYFILE = pathlib.Path.home() / 'mitfahrbar-keys' / 'Tankerkoenig_Archiv.txt'

# Dieselben Stichzeiten wie `sample-fuel-prices` -- und zwar in UTC, weil
# pg_cron in UTC rechnet: '5 5,11,17 * * *' in
# 20260802110000_fuel_sample_cron.sql. Ortszeit waere hier der naheliegende,
# aber falsche Griff: Der Live-Takt tastet im Winter eine Stunde frueher ab
# (06:05/12:05/18:05 statt 07:05/13:05/19:05). Feste Ortszeiten im Import
# ergaeben also genau im Winterhalbjahr eine andere Frage als die gemessene
# -- die Stufe an der Naht, die dieses ganze Vorgehen vermeiden soll.
# **Seit dem Abschalten des Live-Takts sind sie eine Konvention, kein
# Spiegel.** Sie bleiben, weil die bereits gespeicherten Wochenwerte mit
# genau dieser Stichprobe entstanden sind: Wer sie aendert, verschiebt die
# Naht zwischen alten und neuen Zeilen und erzeugt eine Stufe, die keine
# Preisaenderung ist. Das Archiv haette mehr herzugeben (es kennt JEDE
# Preisaenderung) -- dieselbe Frage neu zu stellen, hiesse die ganze
# Historie neu zu rechnen.
SAMPLE_TIMES_UTC = (dt.time(5, 5), dt.time(11, 5), dt.time(17, 5))
SERIES = ('diesel', 'e5', 'e10')

# Muss zu `defaultPercentile` in lib/core/price_series.dart und zu
# percentile_cont(0.10) in rollup_fuel_weeks() passen. Drei Stellen, EINE
# Zahl -- wer sie hier aendert, aendert sie dort mit.
PERCENTILE = 0.10

# Anteil der Stationen, den eine Momentaufnahme kennen muss, um zu zaehlen.
MIN_COVERAGE = 0.60

# Umkreis einer Region, wenn keiner aus der Datenbank kommt -- der Messmodus
# rechnet mit ihm. Muss zu `defaultRadiusKm` in lib/models/price_area.dart
# passen (der Screen bietet nichts anderes an); der frueher hier genannte
# Deckel der Abtast-Function ist mit dem Live-Takt weggefallen.
DEFAULT_RADIUS_KM = 20.0

# Vor Mitte 2014 gibt es das Archiv nicht. Ohne diese Grenze liefe der Job
# fuer eine (versehentlich) sehr alte Fahrt sieben 404er je Woche, immer
# wieder -- die Luecke bliebe ja bestehen.
ARCHIVE_START = dt.date(2014, 6, 1)

# So viele Tage nach Wochenende darf eine ergebnislose Woche noch NICHT
# dauerhaft gemerkt werden: Das Archiv publiziert mit Verzug, und eine
# Woche, die „noch nicht da" ist, als „nie" abzuschreiben nagelte genau die
# Naht zwischen Live-Takt und Archiv fuer immer fest.
MARK_AFTER_DAYS = 28

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

    # Serienweise, nicht wochenweise: Eine Teilwoche (eine Sorte ohne Wert)
    # gaelte sonst fuer immer als fertig, und `ignore-duplicates` koennte
    # die fehlende Sorte nie nachtragen.
    series_of = {}
    for row in select_all('/rest/v1/price_week'
                          '?select=group_id,iso_year,iso_week,series'):
        series_of.setdefault(row['group_id'], {}).setdefault(
            (row['iso_year'], row['iso_week']), set()).add(row['series'])
    complete = {
        group: {week for week, names in weeks.items()
                if names >= set(SERIES)}
        for group, weeks in series_of.items()
    }

    marks = {}
    for row in select_all('/rest/v1/price_week_skip'
                          '?select=group_id,iso_year,iso_week,region_key'):
        marks.setdefault(row['group_id'], {})[
            (row['iso_year'], row['iso_week'])] = row['region_key']

    return regions, driven, complete, marks


def gaps_for(region, driven, complete, marks, today):
    """Fehlende Wochen der Region: Vereinigung ueber ihre Gruppen.

    Nur abgeschlossene Wochen. Eine laufende Woche zu importieren waere
    doppelt falsch: Sie ist unvollstaendig, und danach ist sie keine Luecke
    mehr -- der Live-Verdichter wuerde sie nie mehr ergaenzen, weil
    `ignore-duplicates` die vorhandene Zeile stehen laesst.
    """
    weeks = set()
    for group_id in region['groups']:
        marked = marks.get(group_id, {})
        for year, week in driven.get(group_id, set()):
            if (year, week) in complete.get(group_id, set()):
                continue
            # Eine Marke gilt nur fuer das Gebiet, unter dem sie entstand:
            # Wer sein Gebiet verschiebt, bekommt automatisch einen neuen
            # Versuch. Die alte Zeile bleibt stehen und wirkt nicht.
            if marked.get((year, week)) == region['region_key']:
                continue
            monday = monday_of(year, week)
            if monday < ARCHIVE_START or monday + dt.timedelta(days=7) > today:
                continue
            weeks.add((year, week))
    return sorted(weeks)


def gap_marks(region, driven, complete, marks, year, week, reason, today):
    """Merker-Zeilen fuer alle Gruppen der Region, denen die Woche fehlt.

    Nur fuer Wochen, deren Ende laenger als MARK_AFTER_DAYS zurueckliegt:
    Das Archiv publiziert mit Verzug -- eine junge Woche ist „noch nicht
    da", nicht „nie". Sie bleibt einfach Luecke und wird wieder versucht.
    """
    ended = monday_of(year, week) + dt.timedelta(days=7)
    if ended + dt.timedelta(days=MARK_AFTER_DAYS) > today:
        return []
    rows = []
    for group_id in region['groups']:
        if (year, week) in complete.get(group_id, set()):
            continue
        if (year, week) not in driven.get(group_id, set()):
            continue
        if marks.get(group_id, {}).get((year, week)) == region['region_key']:
            continue
        rows.append({
            'group_id': group_id,
            'iso_year': year, 'iso_week': week,
            'region_key': region['region_key'],
            'reason': reason,
            'decided_at': dt.datetime.now(dt.timezone.utc).isoformat(),
        })
    return rows


def write_marks(rows):
    """Merker ablegen. `merge-duplicates`, und zwar NUR hier: In der
    Buchhaltung muss die neuste Entscheidung gewinnen -- eine Marke mit
    veraltetem region_key liefe nach einem Gebietswechsel sonst als ewige
    Wiedervorlage. Die Preiswerte selbst schreibt weiterhin ausschliesslich
    `ignore-duplicates`; price_week_skip fasst keine Preise an."""
    if rows:
        api('POST', '/rest/v1/price_week_skip', rows,
            prefer='resolution=merge-duplicates,return=minimal')


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


class ArchiveUnavailable(Exception):
    """Netz-/Serverfehler nach allen Versuchen -- NICHT „Datei fehlt".

    Die Unterscheidung traegt den Merker: Eine 404 ist eine Aussage des
    ARCHIVS ueber die Woche (dauerhaft, darf gemerkt werden), ein Timeout
    eine ueber die LEITUNG (vorübergehend, die Woche wird vertagt). Beides
    als None zu behandeln hiesse, eine Netzstoerung koennte eine Woche fuer
    immer abschreiben."""


def fetch(path, auth, retries=3):
    """Eine Archivdatei holen; None, wenn das Archiv sie nicht hat.

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
    raise ArchiveUnavailable(f'{path}: {last}')


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
    """Eine Momentaufnahme uebernehmen -- oder verwerfen, wenn zu duenn.

    `last` traegt seit collect_weeks() die VEREINIGUNG mehrerer Mittelpunkte,
    deshalb wird hier auf die Stationen dieses Mittelpunkts eingeschraenkt.
    Bei einem einzelnen Mittelpunkt ist das ein Nulldurchgang: Dort enthaelt
    `last` ohnehin nur dessen Stationen. Ohne die Einschraenkung waere die
    Deckungspruefung gegen die falsche Grundmenge gestellt -- und ein
    Mittelpunkt bekaeme die Preise seines Nachbarn mitgezaehlt.
    """
    known = {uuid: prices for uuid, prices in last.items() if uuid in uuids}
    if len(known) < MIN_COVERAGE * len(uuids):
        counters['dropped'] += 1
        return
    counters['snapshots'] += 1
    for uuid, prices in known.items():
        seen.add(uuid)
        for name, value in prices.items():
            samples[name].append(value)


def collect_weeks(monday, centres, auth, cache, delay):
    """Eine Woche EINMAL lesen und daraus mehrere Mittelpunkte bedienen.

    Der teure Teil ist der Download: sieben Tagesdateien à ~30 MB. Er haengt
    an der WOCHE, nicht am Mittelpunkt -- zwei Gebiete, die dieselbe Woche
    brauchen, teilen ihn sich hier. Das Zuordnen danach ist reine Rechnung
    im Speicher.

    Gelesen wird mit der Vereinigung aller Stationen; eingeschraenkt wird
    erst in take_snapshot(). `last` traegt den letzten bekannten Preis ueber
    die Tage hinweg -- der Grund, warum die Woche am Stueck gelesen wird.

    Gibt je Mittelpunkt (Ergebnis, Fehlertext) zurueck, geschluesselt auf
    `region_key`.
    """
    stations = {
        centre['region_key']: stations_for(monday.replace(day=1), centre, auth, cache)
        for centre in centres
    }
    union = set().union(*stations.values()) if stations else set()
    if not union:
        return {key: (None, 'keine Stationen im Umkreis') for key in stations}

    last = {}
    state = {
        key: {
            'seen': set(),
            'samples': {name: [] for name in SERIES},
            'counters': {'snapshots': 0, 'dropped': 0, 'missing': 0},
        }
        for key in stations
    }
    live = [key for key, uuids in stations.items() if uuids]
    missing = 0

    for index in range(7):
        day = monday + dt.timedelta(days=index)
        if index and delay:
            time.sleep(delay)
        rows, offset = read_day(day, union, auth)
        # Die Stichzeiten stehen in UTC; verglichen wird gegen die Ortszeit
        # in der Datei. Ohne Versatz (leerer Tag) bleibt die Woche ohne
        # Aufnahme -- besser als eine um zwei Stunden verschobene.
        if rows is None or offset is None:
            missing += 1
            continue
        marks = [
            f'{dt.datetime.combine(day, mark) + dt.timedelta(minutes=offset):%Y-%m-%d %H:%M:%S}'
            for mark in SAMPLE_TIMES_UTC
        ]

        def snapshot():
            for key in live:
                take_snapshot(last, stations[key], state[key]['samples'],
                              state[key]['seen'], state[key]['counters'])

        cursor = 0
        for stamp, uuid, prices in rows:
            while cursor < len(marks) and stamp > marks[cursor]:
                snapshot()
                cursor += 1
            last[uuid] = prices
        while cursor < len(marks):
            snapshot()
            cursor += 1

    results = {}
    for key, entry in state.items():
        counters = {**entry['counters'], 'missing': missing}
        if not stations[key]:
            results[key] = (None, 'keine Stationen im Umkreis')
        elif missing == 7:
            results[key] = (None, 'alle sieben Tagesdateien fehlen')
        elif counters['snapshots'] == 0:
            results[key] = (
                None,
                f'keine belastbare Momentaufnahme ({counters["dropped"]} zu duenn)',
            )
        else:
            results[key] = (
                {'samples': entry['samples'], 'stations': len(entry['seen']), **counters},
                None,
            )
    return results


# --------------------------------------------------------------------------

def summary(lines):
    print('\n'.join(lines))
    path = os.environ.get('GITHUB_STEP_SUMMARY')
    if path:
        with open(path, 'a', encoding='utf-8') as handle:
            handle.write('\n'.join(lines) + '\n')


# --------------------------------------------------------------------------
# Selbstpruefung: ein Download, dieselben Zahlen

def self_check():
    """Beweist die tragende Eigenschaft der Umkehr (Woche aussen, Gebiete
    innen): EIN geteilter Download liefert dieselben Werte wie getrennte
    Laeufe je Gebiet.

    Das ist die Pruefung, an der der Umbau haengt -- ein schnellerer Lauf,
    der andere Wochenwerte liefert, waere kein Fortschritt, sondern eine
    stille Verschiebung der Ersparnis aller Gruppen. Sie laeuft ohne Netz
    und ohne Datenbank gegen erfundene Stationen und deshalb in der PR-CI
    mit; die echte Kennzahl steckt in `take_snapshot`, wo die Vereinigung
    wieder auf die Stationen EINES Mittelpunkts eingeschraenkt wird.
    """
    global fetch

    # **Die beiden Gebiete duerfen sich NICHT dieselben Stationen teilen.**
    # Mit einem gemeinsamen Bestand liefe die Pruefung ins Leere: Ob die
    # Vereinigung eingeschraenkt wird oder nicht, waere dann derselbe
    # Bestand, und die Pruefung bliebe gruen, waehrend genau diese Zeile
    # fehlt. Deshalb liegen sie ~84 km auseinander und **unterschiedlich
    # teuer** -- ohne Einschraenkung zoege B das Perzentil von A nach oben.
    stations = (
        [{'uuid': f'a{i:07d}-0000-0000-0000-000000000000',
          'lat': 49.24 + i * 0.01, 'lng': 9.10, 'level': 0.0} for i in range(6)]
        + [{'uuid': f'b{i:07d}-0000-0000-0000-000000000000',
            'lat': 50.00 + i * 0.01, 'lng': 9.10, 'level': 0.40}
           for i in range(6)]
    )
    prices = {
        station['uuid']: (1.500 + station['level'] + i % 6 * 0.01,
                          1.700 + station['level'] + i % 6 * 0.01,
                          1.640 + station['level'] + i % 6 * 0.01)
        for i, station in enumerate(stations)
    }
    calls = []

    def stub(path, auth, retries=3):
        calls.append(path)
        if path.startswith('stations/'):
            head = 'uuid,name,latitude,longitude'
            body = [f"{s['uuid']},Test,{s['lat']},{s['lng']}" for s in stations]
            return '\n'.join([head, *body])
        day = path.split('/')[-1][:10]
        rows = []
        for clock in ('04:00:00', '12:00:00'):
            for station in stations:
                diesel, e5, e10 = prices[station['uuid']]
                rows.append(f'{day} {clock}+02,{station["uuid"]},'
                            f'{diesel:.3f},{e5:.3f},{e10:.3f},1,1,1')
        return '\n'.join(rows)

    def area(key, lat, lng):
        return {'region_key': key, 'lat': lat, 'lng': lng,
                'radius': DEFAULT_RADIUS_KM, 'groups': []}

    # Zwei ueberlappende Gebiete und eines ohne jede Station -- der Fall, in
    # dem ein Mittelpunkt gar nichts liest, muss beide Wege gleich treffen.
    areas = [area('A', 49.26, 9.10), area('B', 50.02, 9.10),
             area('C', 53.63, 11.41)]
    monday = monday_of(2026, 20)

    def values(entry):
        if entry is None:
            return None
        return {name: round(percentile(entry['samples'][name], PERCENTILE), 6)
                for name in SERIES}

    original = fetch
    fetch = stub
    try:
        calls.clear()
        apart = {}
        for single in areas:
            result = collect_weeks(monday, [single], 'auth', {}, 0)
            entry, problem = result[single['region_key']]
            apart[single['region_key']] = (values(entry), problem)
        apart_files = len([c for c in calls if c.startswith('prices/')])

        calls.clear()
        together = {
            key: (values(entry), problem)
            for key, (entry, problem) in
            collect_weeks(monday, areas, 'auth', {}, 0).items()
        }
        shared_files = len([c for c in calls if c.startswith('prices/')])
    finally:
        fetch = original

    problems = []
    if apart != together:
        problems.append(f'Werte weichen ab:\n  getrennt {apart}\n'
                        f'  geteilt  {together}')
    if shared_files != 7:
        problems.append(f'geteilt: {shared_files} Preisdateien statt 7')
    if apart_files <= shared_files:
        problems.append(f'kein Gewinn: getrennt {apart_files}, '
                        f'geteilt {shared_files}')
    if problems:
        sys.exit('Selbstpruefung fehlgeschlagen:\n' + '\n'.join(problems))
    print(f'Selbstpruefung ok: gleiche Werte, {apart_files} Preisdateien '
          f'getrennt gegen {shared_files} geteilt.')


# --------------------------------------------------------------------------
# Messmodus: wie weit darf der Mittelpunkt einrasten?

# Kandidaten fuer die Maschenweite. Ein Gitterpunkt traegt kuenftig den
# Wochenwert fuer alle Gruppen in seiner Naehe -- statt eines Werts je
# Gruppe. Was das kostet, ist eine MESSFRAGE und keine Geschmacksfrage:
# Der Wert bleibt das P10 im 20-km-Umkreis, nur der Mittelpunkt rastet ein.
GRID_STEPS = (0.1, 0.25, 0.5)


def grid_key_of(lat, lng, step):
    """Naechster Gitterpunkt als Schluessel, z. B. '49.25,9.25'.

    Halbe Schritte werden AUFGERUNDET (floor(x+0.5)), nicht kaufmaennisch
    gerundet wie Pythons round(): Dieselbe Zuordnung muss spaeter in SQL und
    Dart entstehen, und round() rundet dort anders (Banker's Rounding trifft
    genau die Punkte auf der Rasterkante).
    """
    return '%.2f,%.2f' % (math.floor(lat / step + 0.5) * step,
                          math.floor(lng / step + 0.5) * step)


def parse_place(text):
    """'49.24,9.10' oder '49.24,9.10:Bad Rappenau'."""
    head, _, label = text.partition(':')
    lat, _, lng = head.partition(',')
    return {'label': label or head, 'lat': float(lat), 'lng': float(lng)}


def parse_week(text):
    """'2023-W20' -> (2023, 20)."""
    year, _, week = text.upper().partition('-W')
    return int(year), int(week)


def compare_grid(places, weeks, auth, delay):
    """Vergleicht das P10 am echten Punkt mit dem am eingerasteten.

    **Das ist der Messstand, der GEGEN das Raster entschieden hat**
    (21.08.2026, Zahlen in doc/entscheidung-preisnetz.md). Er bleibt hier,
    wie der Soak-Test bei der Fahrerwahl: Wer ein geteiltes Preisnetz
    wieder vorschlaegt, wiederholt die Messung, statt den Satz zu zitieren.

    Schreibt NICHTS und braucht keine Datenbank. Die Frage war: Darf der
    Mittelpunkt auf ein Gitter einrasten, damit sich Gruppen eine Zeile
    teilen? Schwelle war die projekteigene 1-ct-Grenze, dieselbe, an der die
    Mo-Do-Frage entschieden wurde.

    Die WOCHE steht aussen, die Orte innen -- alle Mittelpunkte teilen sich
    einen Download. Andersherum waere die Messung selbst der Beweis fuer das
    Gegenteil dessen, was sie vorbereitet.
    """
    cache = {}
    centres, shift = [], {}
    for place in places:
        key = f"{place['label']}|echt"
        centres.append({'region_key': key, 'lat': place['lat'],
                        'lng': place['lng'], 'radius': DEFAULT_RADIUS_KM})
        shift[key] = 0.0
        for step in GRID_STEPS:
            lat, lng = (float(part) for part in
                        grid_key_of(place['lat'], place['lng'], step).split(','))
            grid = f"{place['label']}|{step}"
            centres.append({'region_key': grid, 'lat': lat, 'lng': lng,
                            'radius': DEFAULT_RADIUS_KM})
            shift[grid] = distance_km(place['lat'], place['lng'], lat, lng)

    for place in places:
        versatz = ', '.join(
            '%s° %.1f km' % (step, shift['%s|%s' % (place['label'], step)])
            for step in GRID_STEPS)
        print('%s (%s, %s) — Versatz: %s'
              % (place['label'], place['lat'], place['lng'], versatz))

    deltas = {step: [] for step in GRID_STEPS}
    lines = ['| Ort | Woche | Sorte | echt | '
             + ' | '.join(f'{step}° (Versatz)' for step in GRID_STEPS) + ' |',
             '| --- | --- | --- | ---: | '
             + ' | '.join('---:' for _ in GRID_STEPS) + ' |']

    for year, week in weeks:
        monday = monday_of(year, week)
        print(f'  {year}-W{week:02d} …', flush=True)
        results = collect_weeks(monday, centres, auth, cache, delay)
        for place in places:
            values = {}
            for suffix in ('echt', *(str(step) for step in GRID_STEPS)):
                result, error = results[f"{place['label']}|{suffix}"]
                if error:
                    print(f"    {place['label']} {suffix}: {error}")
                    continue
                values[suffix] = {
                    name: percentile(result['samples'][name], PERCENTILE)
                    for name in SERIES
                }
            if 'echt' not in values:
                continue
            for name in SERIES:
                base = values['echt'].get(name)
                if base is None:
                    continue
                cells = []
                for step in GRID_STEPS:
                    other = values.get(str(step), {}).get(name)
                    if other is None:
                        cells.append('—')
                        continue
                    delta = (other - base) * 100
                    deltas[step].append(delta)
                    cells.append(f'{other:.3f} ({delta:+.2f} ct)')
                lines.append(f"| {place['label']} | {year}-W{week:02d} | {name} "
                             f"| {base:.3f} | " + ' | '.join(cells) + ' |')

    # **Die Verteilung, nicht der Hoechstwert.** Aus einem einzelnen
    # Extremwert eine Eigenschaft der Maschenweite zu machen, ist genau der
    # Fehler, den doc/entscheidung-mitfahrer-verteilung.md schon einmal
    # gekostet hat: „Wer aus einer Kennzahl auf einem Seed eine
    # Regel-Eigenschaft macht, misst zu schmal." Der Versatz ist Rauschen um
    # null, und ein systematischer Zug waere das eigentliche Ausschlusskriterium.
    lines += ['', '| Maschenweite | n | Mittel (Zug) | exakt gleich | '
                  '≤ 1 ct | p95 | Maximum |',
              '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
    for step in GRID_STEPS:
        values = deltas[step]
        if not values:
            continue
        count = len(values)
        bias = sum(values) / count
        exact = sum(1 for value in values if abs(value) < 0.005) / count * 100
        within = sum(1 for value in values if abs(value) <= 1.0) / count * 100
        spread = sorted(abs(value) for value in values)
        p95 = spread[min(count - 1, int(0.95 * (count - 1) + 0.5))]
        lines.append(f'| {step}° | {count} | {bias:+.3f} ct | {exact:.0f} % '
                     f'| {within:.0f} % | {p95:.2f} ct | {spread[-1]:.2f} ct |')
    summary(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('--max-weeks', type=int, default=100,
                        help='Obergrenze je Lauf (Vorgabe 100), gezaehlt in '
                             'geladenen WOCHEN — eine Woche traegt alle '
                             'Gebiete, die sie brauchen. Der Rest bleibt '
                             'Luecke und kommt beim naechsten Lauf.')
    parser.add_argument('--delay', type=float, default=0.0,
                        help='Pause zwischen den Abrufen in Sekunden')
    parser.add_argument('--dry-run', action='store_true',
                        help='Nur die Luecke zeigen, nichts laden')
    parser.add_argument('--self-check', action='store_true',
                        help='Prueft ohne Netz und Datenbank, dass ein '
                             'geteilter Download dieselben Werte liefert '
                             'wie getrennte Laeufe je Gebiet.')
    parser.add_argument('--compare-grid', action='store_true',
                        help='Messmodus: P10 am echten Punkt gegen den '
                             'eingerasteten. Schreibt nichts und braucht '
                             'keine Datenbank.')
    parser.add_argument('--at', action='append', default=[],
                        metavar='LAT,LNG[:NAME]',
                        help='Ort fuer --compare-grid, mehrfach erlaubt')
    parser.add_argument('--week', action='append', default=[],
                        metavar='YYYY-Www',
                        help='Woche fuer --compare-grid, mehrfach erlaubt')
    args = parser.parse_args()

    # Selbstpruefung und Messmodus laufen VOR der Schluesselpruefung: Beide
    # fassen die Datenbank nicht an, und ein Riegel, der nur mit
    # Service-Key laeuft, waere in der PR-CI keiner.
    if args.self_check:
        self_check()
        return

    if args.compare_grid:
        if not args.at or not args.week:
            sys.exit('--compare-grid braucht mindestens ein --at und ein --week.')
        compare_grid([parse_place(text) for text in args.at],
                     [parse_week(text) for text in args.week],
                     archive_auth(), args.delay)
        return

    if not os.environ.get('SUPABASE_SERVICE_ROLE_KEY'):
        print('::notice::SUPABASE_SERVICE_ROLE_KEY fehlt — nichts zu tun.')
        return
    if not os.environ.get('SUPABASE_URL'):
        sys.exit('SUPABASE_URL fehlt.')

    regions, driven, complete, marks = load_state()
    if not regions:
        summary(['Keine Region eingerichtet — nichts zu tun.'])
        return

    today = dt.date.today()
    todo = {}
    for region_key, region in regions.items():
        region['region_key'] = region_key
        missing = gaps_for(region, driven, complete, marks, today)
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
    cache, pending, marked = {}, [], []
    done = skipped = deferred = downloads = 0
    budget = args.max_weeks
    started = time.time()

    # **Die Woche steht aussen, die Regionen innen.** Der teure Teil ist der
    # Download -- sieben Tagesdateien à ~30 MB --, und der haengt an der
    # WOCHE, nicht am Gebiet: Dieselben Dateien tragen jeden Mittelpunkt.
    # Regionsweise gelesen zahlte jede zusaetzliche Gegend die
    # 210 MB noch einmal, obwohl die Nachbarregion sie gerade gelesen hatte;
    # der Aufwand wuchs also mit der Zahl der Gebiete und damit praktisch mit
    # der Zahl der Gruppen (`region_key` loest auf ~1 km auf).
    # So gelesen haengt er an der Zahl der offenen WOCHEN — und die ist von
    # der Zahl der Gruppen unabhaengig.
    by_week = {}
    for region_key, weeks in todo.items():
        for year, week in weeks:
            by_week.setdefault((year, week), []).append(region_key)

    for year, week in sorted(by_week):
        if budget <= 0:
            break
        budget -= 1
        downloads += 1
        monday = monday_of(year, week)
        centres = [regions[key] for key in by_week[(year, week)]]
        try:
            results = collect_weeks(monday, centres, auth, cache, args.delay)
        except ArchiveUnavailable as error:
            # Leitung, nicht Archiv: keine Marke, die Woche bleibt Luecke
            # und der naechste Lauf versucht sie erneut. Sie faellt fuer
            # ALLE Gebiete dieser Woche aus -- es ist ein Download.
            print(f'  {year}-W{week:02d} vertagt (Netz): {error}')
            deferred += len(centres)
            continue

        for region in centres:
            region_key = region['region_key']
            entry, problem = results[region_key]
            if problem:
                rows = gap_marks(region, driven, complete, marks,
                                 year, week, problem, today)
                marked.extend(rows)
                # Ohne Marke (Woche juenger als MARK_AFTER_DAYS) bleibt sie
                # Luecke -- das Archiv koennte sie noch bekommen.
                if rows:
                    skipped += 1
                else:
                    deferred += 1
                print(f'  {year}-W{week:02d} {region_key} übersprungen: '
                      f'{problem}' + ('' if rows else ' (bleibt Lücke)'))
                continue

            values = []
            for name in SERIES:
                value = percentile(entry['samples'][name], PERCENTILE)
                if value is not None:
                    values.append((name, value, len(entry['samples'][name])))
            if not values:
                rows = gap_marks(region, driven, complete, marks,
                                 year, week, 'keine Sorte mit Wert', today)
                marked.extend(rows)
                if rows:
                    skipped += 1
                else:
                    deferred += 1
                continue
            # Eine Sorte ohne Wert bei sonst voller Woche: Die Zeilen der
            # uebrigen werden geschrieben, aber die Woche bliebe offen --
            # ohne Marke zoege der naechtliche Lauf sie fuer immer neu.
            missing_series = [name for name in SERIES
                              if not any(name == n for n, _, _ in values)]
            if missing_series:
                marked.extend(gap_marks(
                    region, driven, complete, marks, year, week,
                    'Sorte(n) dauerhaft ohne Wert: '
                    + ', '.join(missing_series), today))

            # Eine Auswertung, je Gruppe der Region eine Zeile -- aber nur
            # fuer die Gruppen, denen die Woche wirklich fehlt.
            for group_id in region['groups']:
                if (year, week) in complete.get(group_id, set()):
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
            print(f'  {year}-W{week:02d} {region_key}  ' + '  '.join(
                f'{name} {value:.3f}' for name, value, _ in values)
                + f'  ({entry["snapshots"]} Aufnahmen, {entry["dropped"]} '
                  f'verworfen, {entry["stations"]} Stationen)')

            if len(pending) >= 300:
                # `ignore-duplicates`: Der Lauf kann keinen vorhandenen Wert
                # ueberschreiben -- schon gar keinen gemessenen.
                api('POST', '/rest/v1/price_week', pending,
                    prefer='resolution=ignore-duplicates,return=minimal')
                pending = []

    if pending:
        api('POST', '/rest/v1/price_week', pending,
            prefer='resolution=ignore-duplicates,return=minimal')
    write_marks(marked)

    remaining = outstanding - done - skipped
    minutes = (time.time() - started) / 60
    lines = [f'### Preisarchiv nachgefüllt',
             '',
             f'- Wochenwerte geschrieben: **{done}** (Gebiet × Woche) '
             f'aus **{downloads}** geladenen Woche(n), in {minutes:.0f} min']
    if skipped:
        lines.append(f'- Übersprungen und dauerhaft gemerkt '
                     f'(kommt nicht wieder): {skipped} Woche(n), '
                     f'{len(marked)} Merker-Zeile(n)')
    if deferred:
        lines.append(f'- Vertagt (Netzfehler oder Woche noch zu jung): '
                     f'{deferred} — bleibt Lücke für den nächsten Lauf.')
    if remaining > 0:
        lines.append(f'- **Noch offen: {remaining} Wochen** — der nächste '
                     'Lauf (nächtlich oder von Hand) setzt dort fort.')
    else:
        lines.append('- Keine Lücke mehr offen.')
    summary(lines)


if __name__ == '__main__':
    main()

-- Preisarchiv, Schritt 1: aktuelle Werte abtasten und je Woche verdichten.
--
-- Ziel ist EIN Wert je Gruppe und ISO-Woche für fünf Reihen: Diesel, E5,
-- E10, Hausstrom, Tankstellenstrom. Drei davon werden gemessen, zwei
-- kommen als Konstante aus den Gruppensettings — die stehen deshalb
-- bewusst NICHT in diesen Tabellen (siehe `price_week` unten).
--
-- Die Kosten-/Ersparnisrechnung rührt das hier alles noch nicht an. Solange
-- nicht für JEDE gefahrene Woche ein Wert vorliegt, wäre eine Umstellung
-- eine Rechnung mit Löchern; `fairness.dart` und `computeStats` sehen diese
-- Tabellen nie.
--
-- Warum überhaupt eine eigene Ablage: Die Tankerkönig-API kennt nur „jetzt",
-- keine Historie. Wer einen Verlauf will, muss selbst mitschreiben.

-- ------------------------------------------------------------- price_area
-- Wo diese Gruppe tankt. Kein Eintrag = Feature aus.
--
-- `region_key` fasst nahe beieinander liegende Gruppen zusammen (zwei
-- Nachkommastellen sind ~1 km): Zwei Gruppen in derselben Gegend teilen
-- sich damit EINE Abfrage statt zwei. Der Schlüssel ist zugleich der Grund,
-- warum die Rohschicht ohne `group_id` auskommt — sie hängt an der Gegend,
-- nicht an der Gruppe.
create table public.price_area (
  group_id uuid primary key default auth.uid()
    references public.groups(id) on delete cascade,
  -- Anzeigename aus der Geokodierung, z. B. "Bad Salzuflen, Nordrhein-
  -- Westfalen". Mitgespeichert, damit im Screen steht, worauf sich die
  -- Reihe bezieht — eine nackte Koordinate sagt niemandem etwas.
  label text not null check (char_length(label) between 1 and 200),
  lat numeric(9, 6) not null check (lat between -90 and 90),
  lng numeric(9, 6) not null check (lng between -180 and 180),
  -- Tankerkönig deckelt die Umkreissuche bei 25 km.
  radius_km numeric(4, 1) not null default 20
    check (radius_km between 1 and 25),
  region_key text generated always as (
    round(lat, 2)::text || ',' || round(lng, 2)::text || ',' ||
    round(radius_km, 1)::text
  ) stored,
  updated_at timestamptz not null default now()
);

create index price_area_region_idx on public.price_area (region_key);

alter table public.price_area enable row level security;

create policy price_area_isolated on public.price_area
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

grant select, insert, update, delete on public.price_area
  to anon, authenticated;
grant all on public.price_area to service_role;

-- ----------------------------------------------------------- price_sample
-- Rohschicht: was die API zu einem Zeitpunkt gemeldet hat.
--
-- Bewusst OHNE `group_id`, und das ist die einzige Stelle, an der das
-- erlaubt ist, weil hier keine Gruppendaten stehen — es sind öffentliche
-- Marktdaten, die zufällig für eine Gruppe abgefragt wurden. Der Riegel
-- dazu ist derselbe wie bei `push_outbox`: null Policies, `revoke all`.
-- Kein Client liest die Rohschicht je; gruppensichtbar ist allein
-- `price_week`. Wer hier eine SELECT-Policy ergänzt — auch „nur zum
-- Debuggen" —, macht aus dem Riegel eine Absichtserklärung.
--
-- Die Werte leben kurz: Sobald eine Woche verdichtet ist, werden sie
-- weggeräumt (7 Tage Puffer). Sie sind Zwischenprodukt, kein Archiv.
-- Die 7 Tage sind zugleich das, was ein späterer „Tankdaumen" bräuchte
-- (aktueller Preis gegen das Perzentil der Region) — deshalb hängt die
-- Tabelle an der Region und nicht an der Gruppe.
create table public.price_sample (
  region_key text not null,
  captured_at timestamptz not null,
  station_id uuid not null,
  -- Nullable je Sorte: Nicht jede Tankstelle führt alle drei, und eine
  -- geschlossene meldet gar keinen Preis. Ein fehlender Wert darf nicht
  -- als 0 in ein Perzentil laufen.
  e5 numeric(5, 3) check (e5 > 0),
  e10 numeric(5, 3) check (e10 > 0),
  diesel numeric(5, 3) check (diesel > 0),
  primary key (region_key, captured_at, station_id)
);

create index price_sample_sweep_idx
  on public.price_sample (region_key, captured_at);

alter table public.price_sample enable row level security;

-- Keine Policy — mit aktivierter RLS und ohne Policy sieht ein Client
-- nichts. Das `revoke` steht trotzdem daneben: `alter default privileges`
-- gibt `authenticated` sonst Rechte auf jede neue Tabelle, und der Riegel
-- soll nicht davon abhängen, dass niemand später eine Policy ergänzt.
revoke all on public.price_sample from anon, authenticated;
grant all on public.price_sample to service_role;

-- ------------------------------------------------------------- price_week
-- Die Wochenschicht — der Vertrag, in dem später gerechnet wird.
--
-- Der Wert ist das 10. Perzentil aller Stichproben der Woche über alle
-- Stationen im Umkreis. Nicht das Minimum: Man tankt nie genau beim
-- billigsten Anbieter zum billigsten Zeitpunkt. Das Perzentil ist zudem
-- die einzige Definition, die für gemessene UND später importierte Daten
-- dieselbe Frage beantwortet — die Vergangenheit aus dem Tankerkönig-
-- Archiv liefert jeden Preiswechsel und kann dieselben Zeitpunkte exakt
-- rekonstruieren. Ohne diese gemeinsame Definition entstünde an der Naht
-- zwischen Import und Messung eine Stufe, die keine Preisänderung ist.
--
-- Hausstrom und Tankstellenstrom stehen hier NICHT. Sie sind vorerst
-- Konstanten aus den Gruppensettings, und Konstanten werden nicht
-- gespeichert: Eine Änderung müsste sonst die Historie umschreiben, und
-- eine abgelegte Konstante sähe später aus wie eine Messung. Der Lesepfad
-- (`core/price_series.dart`) füllt die Lücken und markiert sie — gleiche
-- Linie wie „Kennzahlen werden berechnet, nie gespeichert".
create table public.price_week (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  iso_year int not null check (iso_year between 2014 and 2100),
  iso_week int not null check (iso_week between 1 and 53),
  series text not null check (series in ('e5', 'e10', 'diesel')),
  value numeric(6, 3) not null check (value > 0),
  -- Wie viele Stichproben und wie viele Stationen den Wert tragen. Bei
  -- wenigen Stationen ist ein 10-%-Perzentil faktisch „der günstigste von
  -- dreien"; das soll die Oberfläche sagen können, statt es zu verschweigen.
  sample_count int not null check (sample_count > 0),
  station_count int not null check (station_count > 0),
  -- Woher der Wert stammt. `mixed` entsteht, wenn eine Woche teils
  -- importiert und teils gemessen ist — das kommt genau einmal vor, an der
  -- Naht. Konstanten tauchen hier nicht auf, die kennt nur der Lesepfad.
  origin text not null check (origin in ('measured', 'imported', 'mixed')),
  computed_at timestamptz not null default now(),
  primary key (group_id, iso_year, iso_week, series)
);

alter table public.price_week enable row level security;

-- Nur lesen. Geschrieben wird ausschließlich vom Verdichtungslauf mit dem
-- service_role-Key: Eine gefälschte Preiskurve fiele niemandem auf.
create policy price_week_read on public.price_week
  for select to authenticated
  using (group_id = auth.uid() and public.my_group_active());

-- Erst zurücknehmen, dann gezielt geben: `alter default privileges` gibt
-- den Client-Rollen sonst select/insert/update/delete auf JEDE neue
-- Tabelle. Die RLS oben hielte auch so (ohne Policy kein Insert), aber der
-- Riegel soll nicht allein davon abhängen, dass niemand später eine Policy
-- ergänzt — dieselbe Begründung wie bei `push_outbox`.
revoke all on public.price_week from anon, authenticated;
grant select on public.price_week to authenticated;
grant all on public.price_week to service_role;

-- ---------------------------------------------------------------- settings
-- Drei Reihen brauchen einen Fallback-Wert, solange keine Messung vorliegt,
-- und zwei bestehen vorerst NUR daraus. Bisher gab es einen Benzin- und
-- einen Strompreis; gebraucht werden E5 und E10 getrennt sowie Haus- und
-- Tankstellenstrom getrennt.
--
-- Bewusst additiv, nichts umbenannt: `saveSettings` ist ein Upsert je
-- Schlüssel, ein noch nicht aktualisierter Client überschreibt also die
-- neuen Zeilen nicht und liest sie schlicht nicht. Er zeigt weiter seinen
-- Benzinpreis (= E5) und läuft weder in falsche Werte noch in eine
-- Exception — deshalb bleibt `min_supported_version` hier unangetastet.
insert into public.settings (group_id, key, value)
select s.group_id, 'e10_price_per_liter', greatest(s.value - 0.10, 0.01)
  from public.settings s
 where s.key = 'petrol_price_per_liter'
on conflict (group_id, key) do nothing;

insert into public.settings (group_id, key, value)
select distinct s.group_id, 'charging_price_per_kwh', 0.59
  from public.settings s
on conflict (group_id, key) do nothing;

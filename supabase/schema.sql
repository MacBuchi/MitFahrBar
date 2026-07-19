-- schema.sql – Gesamtbild der Datenbank (Doku/Frischinstallation).
-- Eingespielt wird NICHT diese Datei, sondern supabase/migrations/
-- (Supabase-GitHub-Integration, automatisch bei Push auf main).
-- Bei Schema-Änderungen: neue Migrationsdatei anlegen UND dieses
-- Gesamtbild nachziehen.
--
-- Sicherheitsmodell: EIN Gruppenlogin für alle Mitglieder. Jeder
-- authentifizierte Nutzer hat Vollzugriff, anonym ist nichts sichtbar.
-- Der Publishable-Key im Client ist öffentlich; die Zugriffskontrolle
-- liegt vollständig hier (RLS).

-- ---------------------------------------------------------------- Tabellen

create table public.persons (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  active boolean not null default true,
  vehicle text,
  energy_type text check (energy_type in ('electric', 'diesel', 'petrol')),
  consumption_per_100km numeric check (consumption_per_100km > 0),
  created_at timestamptz not null default now()
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  -- Pro Tag sind mehrere Fahrten möglich (z. B. zwei getrennte Autos),
  -- deshalb bewusst NICHT unique.
  trip_date date not null,
  note text,
  created_at timestamptz not null default now()
);

create index trips_trip_date_idx on public.trips (trip_date);

create table public.trip_participations (
  trip_id uuid not null references public.trips(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  status text not null check (status in ('driver', 'passenger', 'one_way')),
  primary key (trip_id, person_id)
);

-- Höchstens ein Fahrer pro Fahrt.
create unique index trip_one_driver_uidx
  on public.trip_participations (trip_id)
  where (status = 'driver');

create table public.settings (
  key text primary key,
  value numeric not null
);

insert into public.settings (key, value) values
  ('commute_km', 30),
  ('one_way_factor', 0.5),
  ('electricity_price_per_kwh', 0.35),
  ('diesel_price_per_liter', 1.70),
  ('petrol_price_per_liter', 1.78),
  ('points_weight', 0.5)
on conflict (key) do nothing;

-- --------------------------------------------------------------------- RLS

alter table public.persons             enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_participations enable row level security;
alter table public.settings            enable row level security;

create policy persons_group_all on public.persons
  for all to authenticated using (true) with check (true);

create policy trips_group_all on public.trips
  for all to authenticated using (true) with check (true);

create policy participations_group_all on public.trip_participations
  for all to authenticated using (true) with check (true);

create policy settings_group_all on public.settings
  for all to authenticated using (true) with check (true);

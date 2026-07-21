-- schema.sql – Gesamtbild der Datenbank (Doku/Frischinstallation).
-- Eingespielt wird NICHT diese Datei, sondern supabase/migrations/
-- (Supabase-GitHub-Integration, automatisch bei Push auf main).
-- Bei Schema-Änderungen: neue Migrationsdatei anlegen UND dieses
-- Gesamtbild nachziehen.
--
-- Sicherheitsmodell: Multi-Tenant. Eine Gruppe = ein Login (auth user),
-- group_id = auth.uid(). Jede Gruppe sieht nur ihre eigenen Daten (RLS),
-- und nur wenn sie freigegeben ('active') ist. Neue Gruppen sind 'pending'
-- und werden von einer Admin-Gruppe freigegeben. Der Publishable-Key im
-- Client ist öffentlich; die Zugriffskontrolle liegt vollständig hier.

-- ---------------------------------------------------------------- Tabellen

create table public.groups (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text unique not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.persons (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  vehicle text,
  energy_type text check (energy_type in ('electric', 'diesel', 'petrol')),
  consumption_per_100km numeric check (consumption_per_100km > 0),
  -- Sitzplätze inklusive Fahrer (Fahrzeugschein-Zahl). null = unbekannt und
  -- darf nie zu einer Warnung oder einem Ausschluss führen.
  seats int check (seats > 1),
  created_at timestamptz not null default now()
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  -- Pro Tag sind mehrere Fahrten möglich (z. B. zwei getrennte Autos),
  -- deshalb bewusst NICHT unique.
  trip_date date not null,
  note text,
  created_at timestamptz not null default now()
);

create table public.trip_participations (
  trip_id uuid not null references public.trips(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  status text not null check (status in ('driver', 'passenger', 'one_way')),
  primary key (trip_id, person_id)
);

-- Höchstens ein Fahrer pro Fahrt.
create unique index trip_one_driver_uidx
  on public.trip_participations (trip_id)
  where (status = 'driver');

create index trips_trip_date_idx on public.trips (trip_date);
create index persons_group_idx on public.persons (group_id);
create index trips_group_idx on public.trips (group_id);
create index trip_participations_group_idx on public.trip_participations (group_id);

-- settings pro Gruppe.
create table public.settings (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  key text not null,
  value numeric not null,
  primary key (group_id, key)
);

-- In-App-Feedback; der Feedback-Bot macht daraus GitHub-Issues.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  type text not null default 'feature' check (type in ('feature', 'bug')),
  message text not null check (char_length(message) between 3 and 2000),
  app_version text,
  platform text,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create index feedback_unprocessed_idx on public.feedback (created_at)
  where processed_at is null;

-- Wochenplaner. Gespeichert wird nur, was Menschen entschieden haben:
-- Verfügbarkeit und ein etwaiges Übersteuern des Fahrer-Vorschlags. Der
-- Vorschlag selbst ist berechnet (KONZEPT.md §4) und steht deshalb nirgends;
-- ein „bestätigt"-Kennzeichen gibt es ebenfalls nicht — die Bestätigung
-- erzeugt eine Zeile in `trips`, deren Existenz am Tag ist die Bestätigung.
create table public.plan_availability (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  -- Nur eine Richtung. Kein Status-Enum: Der Fahrer wird im Plan nie
  -- gespeichert, also bleibt nur „ganz" gegen „eine Richtung".
  one_way boolean not null default false,
  created_at timestamptz not null default now(),
  -- `group_id` gehört in den Schlüssel: Ohne ihn wäre er global eindeutig
  -- und zwei Gruppen kämen sich am selben Tag ins Gehege.
  primary key (group_id, plan_date, person_id)
);

create table public.plan_overrides (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  driver_id uuid not null references public.persons(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, plan_date)
);

create index plan_availability_group_idx on public.plan_availability (group_id);
create index plan_overrides_group_idx on public.plan_overrides (group_id);

-- --------------------------------------------------------------- Funktionen

-- SECURITY-DEFINER-Helfer: lesen groups ohne RLS-Rekursion.
create or replace function public.my_group_active()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'active' from public.groups where id = auth.uid()), false);
$$;

create or replace function public.is_group_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin and status = 'active'
                   from public.groups where id = auth.uid()), false);
$$;

-- Jeder neue Auth-User wird zu einer 'pending'-Gruppe (+ Default-Settings).
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  insert into public.groups (id, name, handle, status, is_admin)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'group_name', ''), new_handle),
          new_handle, 'pending', false);
  insert into public.settings (group_id, key, value) values
    (new.id, 'commute_km', 30),
    (new.id, 'one_way_factor', 0.5),
    (new.id, 'electricity_price_per_kwh', 0.35),
    (new.id, 'diesel_price_per_liter', 1.70),
    (new.id, 'petrol_price_per_liter', 1.78),
    (new.id, 'points_weight', 1.0);
  return new;
end $$;

create trigger on_auth_user_created_group
  after insert on auth.users
  for each row execute function public.handle_new_group();

-- --------------------------------------------------------------------- RLS

alter table public.groups              enable row level security;
alter table public.persons             enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_participations enable row level security;
alter table public.settings            enable row level security;
alter table public.plan_availability   enable row level security;
alter table public.plan_overrides      enable row level security;

-- Eigene Gruppe lesen; Admins sehen alle (Freigabe-Liste). Insert = Trigger.
create policy groups_select on public.groups for select to authenticated
  using (id = auth.uid() or public.is_group_admin());
create policy groups_admin_update on public.groups for update to authenticated
  using (public.is_group_admin()) with check (public.is_group_admin());

create policy persons_isolated on public.persons for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy trips_isolated on public.trips for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy participations_isolated on public.trip_participations for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy settings_isolated on public.settings for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy plan_availability_isolated on public.plan_availability
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy plan_overrides_isolated on public.plan_overrides
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

-- Feedback: eigenes einreichen und nachlesen, mehr nicht.
create policy feedback_insert on public.feedback for insert to authenticated
  with check (group_id = auth.uid() and public.my_group_active());
create policy feedback_select_own on public.feedback for select to authenticated
  using (group_id = auth.uid());

grant all on public.feedback to service_role;

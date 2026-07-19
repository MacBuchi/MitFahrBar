-- Multi-Tenant: mehrere Fahrgemeinschaften in einer Instanz, mit Freigabe.
-- Modell: eine Gruppe = ein Login (auth user), group_id = auth.uid().
-- Neue Gruppen sind 'pending', bis eine Admin-Gruppe sie 'active' schaltet.
-- Strikte Trennung über RLS (group_id = auth.uid() UND eigene Gruppe aktiv).

-- 1) Gruppen -------------------------------------------------------------
create table public.groups (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text unique not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected')),
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

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

-- 2) group_id an alle Datentabellen (zunächst nullable für Backfill) ------
alter table public.persons
  add column group_id uuid references public.groups(id) on delete cascade;
alter table public.trips
  add column group_id uuid references public.groups(id) on delete cascade;
alter table public.trip_participations
  add column group_id uuid references public.groups(id) on delete cascade;
alter table public.settings
  add column group_id uuid references public.groups(id) on delete cascade;

-- 3) Bestehende (bisher einzige) Gruppe anlegen und Daten zuordnen --------
--    Zum Migrationszeitpunkt existiert genau ein Auth-User (der bisherige
--    Gruppen-Login) -> wird zur aktiven Admin-Gruppe.
insert into public.groups (id, name, handle, status, is_admin)
select id, 'Fahrgemeinschaft', 'fahrgemeinschaft', 'active', true
from auth.users
order by created_at
limit 1
on conflict (id) do nothing;

update public.persons
  set group_id = (select id from public.groups where is_admin limit 1)
  where group_id is null;
update public.trips
  set group_id = (select id from public.groups where is_admin limit 1)
  where group_id is null;
update public.trip_participations
  set group_id = (select id from public.groups where is_admin limit 1)
  where group_id is null;
update public.settings
  set group_id = (select id from public.groups where is_admin limit 1)
  where group_id is null;

-- Falls keine Gruppe existierte (Frischinstallation): global geseedete
-- Settings ohne Gruppe entfernen, sie entstehen künftig pro Gruppe.
delete from public.settings where group_id is null;

-- 4) group_id verpflichtend + Default auth.uid() -------------------------
alter table public.persons alter column group_id set not null;
alter table public.persons alter column group_id set default auth.uid();
alter table public.trips alter column group_id set not null;
alter table public.trips alter column group_id set default auth.uid();
alter table public.trip_participations alter column group_id set not null;
alter table public.trip_participations alter column group_id set default auth.uid();

-- settings: Primärschlüssel von (key) auf (group_id, key) umstellen
alter table public.settings drop constraint settings_pkey;
alter table public.settings alter column group_id set not null;
alter table public.settings alter column group_id set default auth.uid();
alter table public.settings add primary key (group_id, key);

create index persons_group_idx on public.persons (group_id);
create index trips_group_idx on public.trips (group_id);
create index trip_participations_group_idx on public.trip_participations (group_id);

-- 5) Trigger: jeder neue Auth-User wird zu einer 'pending'-Gruppe --------
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
    (new.id, 'points_weight', 0.5);
  return new;
end $$;

create trigger on_auth_user_created_group
  after insert on auth.users
  for each row execute function public.handle_new_group();

-- 6) RLS neu fassen ------------------------------------------------------
alter table public.groups enable row level security;

-- Eigene Gruppe lesen; Admins sehen alle (für die Freigabe-Liste).
create policy groups_select on public.groups for select to authenticated
  using (id = auth.uid() or public.is_group_admin());
-- Nur Admins ändern den Status (Freigeben/Ablehnen). Insert macht der Trigger.
create policy groups_admin_update on public.groups for update to authenticated
  using (public.is_group_admin()) with check (public.is_group_admin());

drop policy if exists persons_group_all on public.persons;
drop policy if exists trips_group_all on public.trips;
drop policy if exists participations_group_all on public.trip_participations;
drop policy if exists settings_group_all on public.settings;

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

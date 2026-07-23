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
--
-- Daneben kann je Gruppe EIN Verwalter-Konto stehen (echte E-Mail,
-- account_type = 'admin' in den Metadata): Es sieht keine Gruppendaten
-- (anderer uid) und kann über SECURITY-DEFINER-Funktionen ausschließlich
-- das Gruppenpasswort neu setzen und die Gruppe löschen. Passwort-Reset
-- läuft dafür über Supabases Standard-Mailfluss — ohne Betreiber.

-- crypt()/gen_salt() für die Passwortprüfungen der Konsolen-Funktionen.
create extension if not exists pgcrypto;

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
  -- Sitzplätze inklusive Fahrer (Fahrzeugschein-Zahl). Vorgabe 5 = normaler
  -- PKW, damit die Prüfung ohne Pflegeaufwand greift.
  seats int not null default 5 check (seats > 1),
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

-- Gruppenübergreifende Konfiguration. **Einzige Tabelle ohne `group_id`** —
-- sie enthält keine Gruppendaten, alle Gruppen müssen denselben Wert sehen,
-- und Clients dürfen sie nur lesen (Issue #19). Der Wert wird ausschließlich
-- von Migrationen gesetzt.
create table public.app_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

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
  -- Eine Zeile je Fahrer: Das Übersteuern eines Tages ist die MENGE seiner
  -- Zeilen (Issue #62, mehrere Autos pro Tag). `group_id` gehört in den
  -- Schlüssel, sonst kämen sich zwei Gruppen am selben Tag ins Gehege.
  primary key (group_id, plan_date, driver_id)
);

create index plan_availability_group_idx on public.plan_availability (group_id);
create index plan_overrides_group_idx on public.plan_overrides (group_id);

-- Verknüpfung Verwalter-Konto ↔ Gruppe. `group_id unique` = höchstens ein
-- Admin je Gruppe; die Erst-Verknüpfung beweist sich mit dem Gruppen-Login
-- (claim_admin_group) und rastet danach ein.
create table public.group_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  group_id uuid unique not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now()
);

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
  -- Konsolen-Registrierungen erzeugen keine Geister-„pending"-Gruppe.
  if new.raw_user_meta_data->>'account_type' = 'admin' then
    return new;
  end if;
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

-- ------------------------------------------------- Verwalter-Konsole (#55)

-- Verknüpft das angemeldete Admin-Konto mit einer Gruppe. Beweis ist das
-- Gruppen-Login (Handle + Gruppenpasswort) — und nur, solange die Gruppe
-- noch keinen Admin hat. Grenze des geteilten Logins: Das erste Postfach
-- gewinnt; der Verwalter verknüpft direkt nach dem Release.
create or replace function public.claim_admin_group(
  claim_handle text,
  group_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  caller record;
  target record;
  stored text;
begin
  select id, raw_user_meta_data into caller
    from auth.users where id = auth.uid();
  if caller.id is null
     or caller.raw_user_meta_data->>'account_type' is distinct from 'admin' then
    raise exception 'not an admin account';
  end if;

  select g.id into target from public.groups g
    where g.handle = claim_handle and g.status = 'active';
  if target.id is null then
    raise exception 'wrong group credentials';
  end if;

  select encrypted_password into stored from auth.users where id = target.id;
  if stored is null or stored <> crypt(group_password, stored) then
    raise exception 'wrong group credentials';
  end if;

  if exists (select 1 from public.group_admins where group_id = target.id) then
    raise exception 'group already claimed';
  end if;
  if exists (select 1 from public.group_admins where user_id = auth.uid()) then
    raise exception 'admin already linked';
  end if;

  insert into public.group_admins (user_id, group_id)
  values (auth.uid(), target.id);
end $$;

-- Die verknüpfte Gruppe fürs Konsolen-UI (leer, wenn unverknüpft).
create or replace function public.my_admin_group()
returns table (handle text, name text)
language sql stable security definer set search_path = public as $$
  select g.handle, g.name
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid();
$$;

-- Setzt das Passwort des GRUPPEN-Kontos neu — die Rettungsleine, wenn das
-- geteilte Passwort verloren ging oder jemand alle ausgesperrt hat.
create or replace function public.admin_reset_group_password(
  new_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target uuid;
begin
  select group_id into target from public.group_admins
    where user_id = auth.uid();
  if target is null then
    raise exception 'not linked';
  end if;
  if length(coalesce(new_password, '')) < 8 then
    raise exception 'password too short';
  end if;
  update auth.users
     set encrypted_password = crypt(new_password, gen_salt('bf'))
   where id = target;
end $$;

-- Löscht Gruppe UND Admin-Konto. Sudo-Muster: eigenes Admin-Passwort erneut
-- plus getippter Handle. Der Gruppen-Auth-User zieht über die Kaskade
-- (groups.id -> auth.users, Datentabellen -> groups) alles mit.
create or replace function public.admin_delete_group(
  admin_password text,
  handle_confirmation text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target uuid;
  target_handle text;
  own text;
begin
  select ga.group_id, g.handle into target, target_handle
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid();
  if target is null then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;
  if handle_confirmation is distinct from target_handle then
    raise exception 'handle mismatch';
  end if;

  delete from auth.users where id = target;
  delete from auth.users where id = auth.uid();
end $$;

-- --------------------------------------------------------------------- RLS

alter table public.groups              enable row level security;
alter table public.persons             enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_participations enable row level security;
alter table public.settings            enable row level security;
alter table public.plan_availability   enable row level security;
alter table public.plan_overrides      enable row level security;
-- Bewusst KEINE Policies auf group_admins: Kein Client liest oder schreibt
-- die Verknüpfung direkt, alles läuft über die Konsolen-Funktionen.
alter table public.group_admins        enable row level security;

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

-- Konfiguration: nur lesen. Bewusst keine Schreib-Policy — sonst könnte ein
-- Client die Mindestversion hochsetzen und damit alle aussperren. `anon`
-- darf lesen, damit der Sperr-Schirm schon vor dem Login greift.
alter table public.app_config enable row level security;
create policy app_config_read on public.app_config
  for select to anon, authenticated using (true);

-- Feedback: eigenes einreichen und nachlesen, mehr nicht.
create policy feedback_insert on public.feedback for insert to authenticated
  with check (group_id = auth.uid() and public.my_group_active());
create policy feedback_select_own on public.feedback for select to authenticated
  using (group_id = auth.uid());

-- ------------------------------------------------------------------ Grants
-- Explizit statt Plattform-Default: Neuere Stacks (lokaler CLI-Stack,
-- Postgres-17-Image) sind „secure by default" und geben Client-Rollen ohne
-- Grant weder DML noch EXECUTE — die App fände auf einem frischen Stack
-- keine Tabelle vor. Die Zugriffskontrolle bleibt vollständig bei den
-- RLS-Policies oben; service_role braucht die Rechte für den Feedback-Bot
-- und die E2E-Tests.

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete
  on all tables in schema public to anon, authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;
grant execute on all functions in schema public
  to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

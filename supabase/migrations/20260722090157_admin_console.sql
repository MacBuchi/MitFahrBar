-- Verwalter-Konsole (Issue #55): ein zweites, leichtgewichtiges Auth-Konto
-- je Gruppe mit ECHTER E-Mail. Der Gruppen-Login (handle@grp.local, geteilt)
-- bleibt unangetastet — Mitglieder teilen weiterhin keine E-Mail. Das
-- Admin-Konto kann ausschließlich: Gruppenpasswort neu setzen und die
-- Gruppe löschen. Es sieht keine Gruppendaten (anderer uid, RLS blockt).
--
-- Warum so: Passwort-vergessen und E-Mail-Bestätigung laufen damit über
-- Supabases Standardflüsse ans Postfach des Verwalters — Selbstbedienung,
-- null Pflegeaufwand beim Betreiber. Ein „Admin-Passwort" innerhalb der
-- Gruppe hätte genau diese Rettungsleine nicht gehabt.

-- crypt()/gen_salt() für die Passwortprüfungen in den Funktionen.
create extension if not exists pgcrypto;

-- ------------------------------------------------------------- Verknüpfung

-- RLS an, bewusst KEINE Policies: Kein Client liest oder schreibt die
-- Tabelle direkt; alles läuft über die SECURITY-DEFINER-Funktionen.
-- `group_id unique` = höchstens ein Admin-Konto je Gruppe.
create table public.group_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  group_id uuid unique not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.group_admins enable row level security;

-- ------------------------------------------------- Trigger-Ausnahme Signup

-- Konsolen-Registrierungen (account_type = 'admin' in den Metadata) dürfen
-- keine Geister-„pending"-Gruppe erzeugen.
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
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

-- ---------------------------------------------------------------- Funktionen

-- Verknüpft das angemeldete Admin-Konto mit einer Gruppe. Beweis ist das
-- Gruppen-Login (Handle + Gruppenpasswort) — und nur, solange die Gruppe
-- noch keinen Admin hat. Dokumentierte Grenze des geteilten Logins: Das
-- erste Postfach gewinnt; der Verwalter verknüpft direkt nach dem Release.
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

-- Löscht Gruppe UND Admin-Konto. Sudo-Muster: das eigene Admin-Passwort
-- muss erneut eingegeben werden, dazu der getippte Handle als Bestätigung.
-- Das Löschen des Gruppen-Auth-Users nimmt über die bestehende Kaskade
-- (groups.id -> auth.users, alle Datentabellen -> groups) alles mit —
-- ein Schlag, keine Reste. Danach fällt auch das Admin-Konto.
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

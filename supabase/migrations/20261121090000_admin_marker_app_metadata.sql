-- Verwalter-Konten tragen ihre Markierung in `app_metadata`: Das schreibt nur
-- der Server. Entschieden wird EINMAL, beim Anlegen des Kontos; spätere
-- Änderungen an `user_metadata` zählen für Berechtigungen nicht — sie gehören
-- dem Nutzer. Voraussetzung für #292 (Anbieter-Logins bringen ihre eigenen
-- `user_metadata` mit).
--
-- Reihenfolge: Trigger → Nachtrag → Leser. So verliert ein bestehendes
-- Verwalter-Konto zu keinem Zeitpunkt seinen Zugang.
--
-- Mindestversion bleibt stehen: Ein alter Client entscheidet sein Routing
-- weiter über `user_metadata.account_type`, und bei echten Verwalter-Konten
-- bleibt dieser Wert unverändert stehen. Er routet also weiter richtig; eine
-- Sicherheitsgrenze war das Routing nie.

-- ------------------------------------------------------- 1. Markierung setzen

create or replace function public.mark_admin_account()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.raw_user_meta_data->>'account_type' = 'admin' then
    new.raw_app_meta_data := coalesce(new.raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('account_type', 'admin');
  end if;
  return new;
end $$;

-- Ein Trigger braucht kein execute-Recht des Aufrufers; aufrufbar soll er
-- für Clients nicht sein.
revoke all on function public.mark_admin_account() from public, anon, authenticated;

create trigger on_auth_user_mark_admin
  before insert on auth.users
  for each row execute function public.mark_admin_account();

-- ------------------------------------------- 2. Bestehende Konten nachtragen

-- Nie einen Gruppen-Login: Eine Gruppe ist nie ein Verwalter-Konto, egal was
-- in ihren `user_metadata` steht.
update auth.users u
   set raw_app_meta_data = coalesce(u.raw_app_meta_data, '{}'::jsonb)
                           || jsonb_build_object('account_type', 'admin')
 where u.raw_user_meta_data->>'account_type' = 'admin'
   and not exists (select 1 from public.groups g where g.id = u.id);

-- -------------------------------------------------------- 3. Leser umstellen

-- Rumpf unverändert bis auf die Ausnahme. Der AFTER-Trigger sieht den Wert,
-- den der BEFORE-Trigger oben gesetzt hat.
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  -- Konsolen-Registrierungen erzeugen keine Geister-„pending"-Gruppe.
  if new.raw_app_meta_data->>'account_type' = 'admin' then
    return new;
  end if;
  insert into public.groups (id, name, handle, status)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'group_name', ''), new_handle),
          new_handle, 'pending');
  insert into public.settings (group_id, key, value) values
    (new.id, 'commute_km', 30),
    (new.id, 'one_way_factor', 0.5),
    (new.id, 'electricity_price_per_kwh', 0.35),
    (new.id, 'diesel_price_per_liter', 1.70),
    (new.id, 'petrol_price_per_liter', 1.78),
    (new.id, 'points_weight', 1.0);
  return new;
end $$;

-- Gleiche Signatur, gleicher Rumpf; nur der Kopf liest `app_metadata` und
-- weist zusätzlich jeden Gruppen-Login ab.
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
  select id, raw_app_meta_data into caller
    from auth.users where id = auth.uid();
  if caller.id is null
     or caller.raw_app_meta_data->>'account_type' is distinct from 'admin'
     or exists (select 1 from public.groups g where g.id = caller.id) then
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

  insert into public.group_admins (user_id, group_id)
  values (auth.uid(), target.id);

  update public.groups set released_at = null where id = target.id;
end $$;

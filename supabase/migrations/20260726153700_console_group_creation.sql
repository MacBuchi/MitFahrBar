-- Gruppen-Anlage in der Verwalter-Konsole (Issue #106, #107)
--
-- Bisher entstand eine Gruppe nur anonym über `/request`, landete als
-- 'pending' und musste von der einen Admin-Gruppe freigegeben werden. Ein
-- frisch registriertes Verwalter-Konto kam damit nirgendwo hin:
-- `claim_admin_group` verlangt eine bestehende, aktive Gruppe SAMT
-- Gruppenpasswort. Ab hier legt das Verwalter-Konto seine Gruppen selbst an
-- (Edge Function `request-group`, jetzt authentifiziert) — sofort aktiv und
-- sofort verknüpft. Der Deckel von 5 Gruppen je Konto ersetzt die Freigabe.
--
-- DREI DINGE, DIE HIER ZUSAMMENGEHÖREN UND NICHT EINZELN „AUFGERÄUMT"
-- WERDEN DÜRFEN:
--
-- 1. Der Deckel ist ein TRIGGER, keine aufrufbare Funktion. `alter default
--    privileges` (siehe explicit_client_grants) gibt `authenticated` execute
--    auf jede neue Funktion. Eine Funktion `adopt_group(gruppe, konto)` wäre
--    damit die Übernahme-Lücke: Jedes angemeldete Konto könnte sich an jede
--    noch unverknüpfte Gruppe hängen, OHNE das Gruppenpasswort zu kennen.
--    Ein Trigger ist nicht aufrufbar und greift für jeden Weg — Anlage,
--    claim und Betreiber-SQL.
--
-- 2. Die Signaturen der drei gruppenbezogenen Funktionen WECHSELN, und die
--    alten werden ausdrücklich gedroppt. `create or replace` kann keine
--    Signatur ändern; ein zusätzlicher Parameter erzeugt einen Overload.
--    Bliebe die alte einparametrige Fassung stehen, träfe ihr
--    `select … into` bei mehreren Gruppen still die ERSTE Zeile — ein alter
--    Client löschte damit die falsche Gruppe. Deshalb hebt dieses File auch
--    `min_supported_version`.
--
-- 3. `handle_new_group()` bleibt unverändert. Der Trigger darf den
--    Metadata-Angaben eines Signups NICHT trauen: Ein gebasteltes
--    `auth.signUp` gegen die Gruppen-Domain würde sonst eine aktive, an ein
--    fremdes Konto gehängte Gruppe erzeugen. Fremd-Signups landen weiter als
--    'pending' und sind damit inert (die RLS verbietet ihnen jedes Lesen und
--    Schreiben).
--
-- VORBEREITUNG FÜR SPÄTER (bewusst jetzt, weil es nachträglich teuer wäre):
-- `status` bekommt den Wert 'archived', und `groups.released_at` markiert
-- Gruppen ohne Verwalter. Damit ist ein künftiger Aufräum-Job — verwaiste
-- und seit langem ungenutzte Gruppen stilllegen — eine reine Job-Frage und
-- kein Schema-Umbau: `my_group_active()` prüft `status = 'active'`, eine
-- archivierte Gruppe ist also über alle Policies hinweg sofort still,
-- verlustfrei und umkehrbar. Der vorgesehene Ort für den Job ist GitHub
-- Actions neben `tool/notify.dart` (Service-Role-Key als Secret, nur Zahlen
-- ins Log) — hier wird er NICHT gebaut.

-- ---------------------------------------------------------------- Struktur

-- Ein Konto trägt jetzt mehrere Gruppen. `group_id unique` bleibt: höchstens
-- EIN Verwalter je Gruppe ist weiter die Regel (#55).
alter table public.group_admins drop constraint group_admins_pkey;
alter table public.group_admins add primary key (user_id, group_id);

-- 'archived' als künftiger Ruhezustand. Der Wert wird hier noch von nichts
-- gesetzt; er steht bereit, damit das Stilllegen später keine
-- Constraint-Migration UND kein Client-Release braucht (der Client parst
-- unbekannte Status seit 0.37.0 tolerant und behandelt sie als „nicht
-- aktiv").
alter table public.groups drop constraint groups_status_check;
alter table public.groups add constraint groups_status_check
  check (status in ('pending', 'active', 'rejected', 'archived'));

-- Wann die Gruppe ihren Verwalter verloren hat. Eine aktive Gruppe ohne
-- Verknüpfung ist der einzige legitime Zwischenzustand (Übergabe nach
-- `admin_release_group`) — mit Zeitstempel ist sie von einer echten Waise
-- unterscheidbar, ohne dass jemand mitschreiben muss.
alter table public.groups add column released_at timestamptz;

-- --------------------------------------------------------------- Funktionen

-- Deckel: 5 Gruppen je Verwalter-Konto, serverseitig. Ein Deckel nur im UI
-- ist kein Deckel.
--
-- Der Vorschuss-Lock ist nicht Zierde: Ohne ihn zählen zwei gleichzeitige
-- Anlagen beide den Stand VOR der jeweils anderen, und es entstehen 6
-- Gruppen. SECURITY DEFINER, weil `group_admins` keine einzige Policy hat.
create function public.enforce_group_admin_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('group_admins:' || new.user_id::text));
  if (select count(*) from public.group_admins
       where user_id = new.user_id) >= 5 then
    raise exception 'group limit reached';
  end if;
  return new;
end $$;

create trigger group_admins_cap
  before insert on public.group_admins
  for each row execute function public.enforce_group_admin_cap();

-- Verliert eine Gruppe ihren Verwalter, wird der Zeitpunkt vermerkt. Der
-- Trigger fängt beide Wege: das absichtliche Lösen (`admin_release_group`)
-- UND die Kaskade, wenn ein Verwalter-Konto gelöscht wird — der zweite Fall
-- wäre sonst eine stille Waise.
--
-- Bewusst NUR der Zeitstempel, kein Statuswechsel: Eine Übergabe darf die
-- Gruppe nicht aussperren, die Mitfahrer fahren ja weiter.
create function public.mark_group_released()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.groups set released_at = now() where id = old.group_id;
  return old;
end $$;

create trigger group_admins_released
  after delete on public.group_admins
  for each row execute function public.mark_group_released();

-- Alle verknüpften Gruppen fürs Konsolen-UI (leer, wenn keine).
-- Die Einzelform `my_admin_group()` fällt weg — sie könnte bei mehreren
-- Gruppen nur eine beliebige davon zeigen.
drop function public.my_admin_group();

create function public.my_admin_groups()
returns table (group_id uuid, handle text, name text)
language sql stable security definer set search_path = public as $$
  select g.id, g.handle, g.name
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid()
   order by g.created_at;
$$;

-- Übernimmt eine BESTEHENDE Gruppe. Bleibt nötig, solange es Gruppen gibt,
-- die vor diesem Umbau entstanden sind — und für die Übergabe an eine
-- Nachfolgerin. Beweis ist weiter das Gruppen-Login.
--
-- Die frühere Prüfung „admin already linked" fällt weg: Mehrere Gruppen sind
-- jetzt erlaubt, die Grenze zieht der Cap-Trigger. `released_at` wird
-- geleert — die Gruppe hat wieder einen Verwalter.
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

  insert into public.group_admins (user_id, group_id)
  values (auth.uid(), target.id);

  update public.groups set released_at = null where id = target.id;
end $$;

-- Ab hier: dieselben drei Aktionen wie bisher, aber jede nennt IHRE Gruppe.
-- Die Eigentumsprüfung `user_id = auth.uid() and group_id = target_group`
-- ist der eigentliche Inhalt — ohne sie könnte ein Verwalter die Gruppe
-- eines anderen treffen.

-- Setzt das Passwort des GRUPPEN-Kontos neu — die Rettungsleine, wenn das
-- geteilte Passwort verloren ging oder jemand alle ausgesperrt hat.
drop function public.admin_reset_group_password(text);

create function public.admin_reset_group_password(
  target_group uuid,
  new_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.group_admins
                  where user_id = auth.uid() and group_id = target_group) then
    raise exception 'not linked';
  end if;
  if length(coalesce(new_password, '')) < 8 then
    raise exception 'password too short';
  end if;
  update auth.users
     set encrypted_password = crypt(new_password, gen_salt('bf'))
   where id = target_group;
end $$;

-- Löst die Verknüpfung (Issue #73) — die Übergabe. Sudo-Muster: eigenes
-- Admin-Passwort erneut. Danach kann ein anderes Konto über
-- claim_admin_group neu einrasten; Gruppendaten und Verwalter-Konto bleiben
-- unberührt, `released_at` merkt sich den Zeitpunkt (Trigger).
--
-- Bewusste Grenze bleibt: Wer Postfach UND Passwort verliert, kommt an seine
-- Gruppen nicht mehr heran. Ein Selbstbedienungs-Weg daran vorbei wäre die
-- Übernahme-Lücke, die das Einrasten gerade verhindert — jedes Mitglied
-- kennt das Gruppenpasswort. Vorgesehen dafür ist eine Übernahme mit
-- Widerspruchsfrist (eigenes Issue), nicht ein zweiter Schlüssel hier.
drop function public.admin_release_group(text);

create function public.admin_release_group(
  target_group uuid,
  admin_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  own text;
begin
  if not exists (select 1 from public.group_admins
                  where user_id = auth.uid() and group_id = target_group) then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;

  delete from public.group_admins
   where user_id = auth.uid() and group_id = target_group;
end $$;

-- Löscht DIE GRUPPE. Sudo-Muster: eigenes Admin-Passwort erneut plus
-- getippter Handle. Der Gruppen-Auth-User zieht über die Kaskade
-- (groups.id -> auth.users, Datentabellen -> groups) alles mit.
--
-- Neu: Das Verwalter-Konto überlebt. Bei bis zu 5 Gruppen wäre ein
-- Selbst-Löschen Datenverlust an den übrigen vier — und es würde die oben
-- benannte Lücke verschlimmern. Deshalb wird hier genau EINE Zeile in
-- `auth.users` entfernt — die der Zielgruppe. `test/schema_test.dart` zählt
-- das nach.
drop function public.admin_delete_group(text, text);

create function public.admin_delete_group(
  target_group uuid,
  admin_password text,
  handle_confirmation text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target_handle text;
  own text;
begin
  select g.handle into target_handle
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid() and ga.group_id = target_group;
  if target_handle is null then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;
  if handle_confirmation is distinct from target_handle then
    raise exception 'handle mismatch';
  end if;

  delete from auth.users where id = target_group;
end $$;

-- ------------------------------------------------------------ Mindestversion

-- Pflicht nach der Hausregel in CLAUDE.md: Dieses File entfernt
-- `my_admin_group()` und die alten Signaturen, die veröffentlichte Clients
-- aufrufen. Ihre Konsole bräche stumm — also müssen sie sich aktualisieren.
update public.app_config
   set value = '0.37.0', updated_at = now()
 where key = 'min_supported_version';

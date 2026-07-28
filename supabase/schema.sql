-- schema.sql – Gesamtbild der Datenbank (Doku/Frischinstallation).
-- Eingespielt wird NICHT diese Datei, sondern supabase/migrations/
-- (Supabase-GitHub-Integration, automatisch bei Push auf main).
-- Bei Schema-Änderungen: neue Migrationsdatei anlegen UND dieses
-- Gesamtbild nachziehen.
--
-- Sicherheitsmodell: Multi-Tenant. Eine Gruppe = ein Login (auth user),
-- group_id = auth.uid(). Jede Gruppe sieht nur ihre eigenen Daten (RLS),
-- und nur wenn sie 'active' ist. Der Publishable-Key im Client ist
-- öffentlich; die Zugriffskontrolle liegt vollständig hier.
--
-- Gruppen entstehen in der Verwalter-Konsole (Edge Function `request-group`)
-- und sind sofort aktiv und verknüpft. 'pending' ist nur noch der inerte
-- Ruhezustand für Fremd-Signups gegen die Gruppen-Domain: Ein direktes
-- `auth.signUp` ist nie abstellbar (die Verwalter-Registrierung braucht
-- offenes Signup), der Trigger unten macht daraus eine Zeile, die nichts
-- lesen und nichts schreiben kann. Eine FREIGABE gibt es seit #108 nicht
-- mehr — mit ihr fielen `groups.is_admin`, `is_group_admin()` und jede
-- Update-Policy auf `groups`.
--
-- Je Gruppe steht EIN Verwalter-Konto (echte E-Mail, account_type = 'admin'
-- in den Metadata); ein Konto trägt bis zu 5 Gruppen. Es sieht keine
-- Gruppendaten (anderer uid) und kann über SECURITY-DEFINER-Funktionen
-- ausschließlich das Gruppenpasswort neu setzen, die Verknüpfung lösen und
-- die Gruppe löschen. Passwort-Reset läuft über Supabases Mailfluss (Code,
-- kein Link — siehe #102) — ohne Betreiber.

-- crypt()/gen_salt() für die Passwortprüfungen der Konsolen-Funktionen.
create extension if not exists pgcrypto;
-- Der Minutentakt, der den Ausgangskorb abholt (#132). pg_net ist auf
-- Supabase schon installiert; pg_cron nicht, steht aber in
-- `shared_preload_libraries` und lässt sich anlegen (auf dem CLI-Stack
-- geprüft, bevor dieser Weg gewählt wurde).
create extension if not exists pg_cron;

-- ---------------------------------------------------------------- Tabellen

create table public.groups (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text unique not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'archived')),
  created_at timestamptz not null default now(),
  -- Wann die Gruppe ihren Verwalter verloren hat. Eine aktive Gruppe ohne
  -- Verknüpfung ist nur als Übergabefenster vorgesehen; der Zeitstempel
  -- macht sie von einer echten Waise unterscheidbar. 'archived' ist der
  -- vorgesehene Ruhezustand — `my_group_active()` prüft auf 'active', eine
  -- archivierte Gruppe ist damit über alle Policies hinweg still,
  -- verlustfrei und umkehrbar.
  released_at timestamptz
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

-- Ein Name gehört in EINER Gruppe genau einer Person (Issue #109) — über
-- Gruppengrenzen hinweg dagegen frei, zwei Fahrgemeinschaften dürfen beide
-- eine „Anna" haben. Bis v0.41.0 stand hier ein globaler `unique (name)` aus
-- der Zeit vor der Mandantentrennung; er sperrte die zweite Gruppe aus und
-- verriet ihr dabei, dass der Name woanders existiert.
--
-- Index statt Constraint, weil normalisiert verglichen wird: `lower(btrim())`
-- ist genau die Abbildung, mit der `core/csv_import.dart` Namen auf Personen
-- zuordnet. Inaktive zählen mit — wer zurückkommt, wird reaktiviert, nicht
-- neu angelegt (eine zweite Zeile spaltete seine Punkte-Historie).
create unique index persons_group_name_key
  on public.persons (group_id, lower(btrim(name)));

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

-- Anmerkungen zu einem Plantag (Issue #127, deckt #120 mit ab): „komme erst
-- um 9". **Kein Chat** — keine Threads, kein Gelesen-Status, keine Antworten;
-- KONZEPT.md §1 („Kommunikation bleibt in WhatsApp") gilt weiter. Der Name
-- sagt genau das: eine Notiz am Plantag, neben den beiden Tabellen darüber.
--
-- Der Schlüssel ist eine generierte UUID, kein fachlicher — mehrere
-- Anmerkungen je Tag und Person sind der Normalfall. Vorlage ist deshalb
-- `feedback`, nicht `plan_availability`. `btrim` im Längen-Check, weil
-- `between 1 and 500` allein 500 Leerzeichen durchließe.
--
-- `person_id` ist der Verfasser und kein Identitätsnachweis: Jeder kann für
-- jeden schreiben, wie im Planer jeder für jeden einträgt.
create table public.plan_notes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

create index plan_availability_group_idx on public.plan_availability (group_id);
create index plan_overrides_group_idx on public.plan_overrides (group_id);
-- Gelesen wird immer eine Spanne von Tagen (die Planwoche) einer Gruppe.
create index plan_notes_day_idx on public.plan_notes (group_id, plan_date);

-- Push-Benachrichtigungen zum Wochenplaner (Issue #101). Drei Aufgaben:
-- push_devices = wohin, notification_prefs = wann, push_log = was schon raus
-- ist. Der vorgeschlagene Fahrer steht auch hier NICHT — push_log hält nur
-- einen Hash des Tageszustands, damit der Versand-Job Änderungen erkennt.

-- Ein Gerät = eine Zeile. Primärschlüssel ist der Token, NICHT
-- (group_id, token): FCM-Token sind global eindeutig, eine Kollision
-- zwischen Gruppen ist konstruktiv unmöglich — und ein Gerät gehört zu genau
-- EINER Gruppe, meldet es sich in einer anderen an, muss die alte Zeile
-- weichen. Die „group_id in den Schlüssel"-Regel zielt auf fachliche
-- Schlüssel, die ohne sie über alle Gruppen eindeutig wären; ein Token ist
-- das nicht.
create table public.push_devices (
  token text primary key,
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  -- Wer an diesem Gerät benachrichtigt wird. KEIN Login: Jeder kann jeden
  -- wählen, wie im Planer jeder für jeden einträgt. Zustelladresse, kein
  -- Identitätsnachweis. NULL = noch niemandem zugeordnet, bekommt nichts.
  person_id uuid references public.persons(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

-- Uhrzeiten je PERSON (nicht je Gerät), alle in Europe/Berlin.
-- **Keine Zeile = keine Benachrichtigungen**: Die Zeile entsteht beim
-- Einschalten im Screen. So gibt es genau eine Wahrheit darüber, wer etwas
-- bekommt, und der Versand-Job braucht keine Vorgabewerte zu kennen.
create table public.notification_prefs (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  evening_enabled boolean not null default true,
  evening_time time not null default '21:00',
  -- Ende des Änderungs-Fensters: Danach nützt keine Nachricht mehr, und ein
  -- nachgeholter Lauf darf niemanden nachts wecken.
  departure_time time not null default '07:30',
  changes_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (group_id, person_id)
);

-- Versand-Gedächtnis. Kein `default auth.uid()`: Hier schreibt nur der
-- Versand-Job mit dem service_role-Key, und der hat keine auth.uid().
create table public.push_log (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  plan_date date not null,
  kind text not null check (kind in ('evening', 'change')),
  digest text not null,
  sent_at timestamptz not null default now(),
  primary key (group_id, person_id, plan_date, kind)
);

-- Ausgangskorb (#132): was gesagt WÜRDE. Der Client rechnet den Text mit dem
-- echten `planWeek`/`composeBody` aus und legt ihn hier ab; ein Trigger macht
-- die Zeile 60 Sekunden später fällig, pg_cron holt sie ab. So bleibt die
-- Fairness-Regel in Dart, obwohl der Versand ereignisgetrieben ist.
--
-- Hier steht der vorgeschlagene Fahrer im Klartext — die einzige Ausnahme von
-- „wird nie gespeichert", und sie hängt an einem Riegel: **null Policies und
-- keine Client-Rechte**, wie bei `push_log`. Geschrieben wird ausschließlich
-- über `publish_push_outbox`, gelesen nur mit dem service_role-Key. Was der
-- Client nicht lesen kann, kann keine zweite Wahrheit werden.
--
-- Die Uhrzeiten stehen NICHT hier, sondern in `notification_prefs` — sonst
-- wirkte eine geänderte Weckzeit erst nach dem nächsten Schreiben.
create table public.push_outbox (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  plan_date date not null,
  digest text not null,
  body text not null,
  -- Zwei Kopfzeilen: Welche Art die Meldung ist, entscheidet `push_log`, und
  -- das darf der Client nicht lesen. Er legt beide ab, der Versand wählt —
  -- so wandert kein deutsches Wort nach TypeScript.
  title_evening text not null,
  title_change text not null,
  -- NULL = nichts offen. Der Versand quittiert damit.
  due_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (group_id, person_id, plan_date)
);

create index push_devices_group_idx on public.push_devices (group_id);
create index push_devices_person_idx
  on public.push_devices (group_id, person_id);
create index push_log_date_idx on public.push_log (plan_date);
create index push_outbox_due_idx on public.push_outbox (due_at)
  where due_at is not null;

-- Verknüpfung Verwalter-Konto ↔ Gruppe. Ein Konto trägt bis zu 5 Gruppen
-- (Deckel im Trigger unten), deshalb der zusammengesetzte Schlüssel.
-- `group_id unique` bleibt: höchstens EIN Verwalter je Gruppe (#55). Eine
-- bestehende Gruppe übernimmt man weiter mit dem Gruppen-Login
-- (claim_admin_group); neue entstehen bereits verknüpft.
create table public.group_admins (
  user_id uuid references auth.users(id) on delete cascade,
  group_id uuid unique not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

-- --------------------------------------------------------------- Funktionen

-- SECURITY-DEFINER-Helfer: liest groups ohne RLS-Rekursion. Hieran hängt
-- jede Datentabellen-Policy — 'archived' zu setzen macht eine Gruppe damit
-- über alle Policies hinweg still, verlustfrei und umkehrbar.
create or replace function public.my_group_active()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'active' from public.groups where id = auth.uid()), false);
$$;

-- Jeder neue Auth-User wird zu einer 'pending'-Gruppe (+ Default-Settings).
-- Der Trigger traut den Metadata eines Signups nur den Gruppennamen zu:
-- Ein gebasteltes `auth.signUp` gegen die Gruppen-Domain darf keine aktive
-- oder fremd verknüpfte Gruppe erzeugen. Aktiv und verknüpft wird eine
-- Gruppe ausschließlich in der Edge Function `request-group`.
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  -- Konsolen-Registrierungen erzeugen keine Geister-„pending"-Gruppe.
  if new.raw_user_meta_data->>'account_type' = 'admin' then
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

create trigger on_auth_user_created_group
  after insert on auth.users
  for each row execute function public.handle_new_group();

-- ------------------------------------------------- Verwalter-Konsole (#55)

-- Deckel: 5 Gruppen je Verwalter-Konto (#106), serverseitig. Ein Deckel nur
-- im UI ist kein Deckel.
--
-- Bewusst ein TRIGGER und keine aufrufbare Funktion: `alter default
-- privileges` unten gibt `authenticated` execute auf jede Funktion. Eine
-- Funktion `adopt_group(gruppe, konto)` wäre damit die Übernahme-Lücke —
-- jedes angemeldete Konto könnte sich an jede unverknüpfte Gruppe hängen,
-- ohne das Gruppenpasswort zu kennen. Der Vorschuss-Lock verhindert, dass
-- zwei gleichzeitige Anlagen beide den Stand vor der anderen zählen.
create or replace function public.enforce_group_admin_cap()
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

-- Verliert eine Gruppe ihren Verwalter, wird der Zeitpunkt vermerkt — beim
-- absichtlichen Lösen UND bei der Kaskade eines gelöschten Verwalter-Kontos
-- (der zweite Fall wäre sonst eine stille Waise). Bewusst nur der
-- Zeitstempel, kein Statuswechsel: Eine Übergabe darf die Gruppe nicht
-- aussperren, die Mitfahrer fahren ja weiter.
create or replace function public.mark_group_released()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.groups set released_at = now() where id = old.group_id;
  return old;
end $$;

create trigger group_admins_released
  after delete on public.group_admins
  for each row execute function public.mark_group_released();

-- Entprellen des Ausgangskorbs (#132): Fünf Taps im Planer sind fünf Upserts
-- auf dieselben Zeilen und sollen EINE Meldung ergeben. Jede Inhaltsänderung
-- schiebt die Fälligkeit 60 Sekunden nach hinten.
--
-- Der `is distinct from`-Vergleich ist der Kern: Der stündliche Reparatur-Job
-- schreibt dieselben Zeilen immer wieder. Setzte der Trigger die Fälligkeit
-- auch bei unverändertem Inhalt neu, schöbe er sie stündlich vor sich her und
-- es würde **nie** etwas gesendet. Und weil `new.due_at` bei unverändertem
-- Inhalt unangetastet bleibt, kann der Versand mit `due_at = null`
-- quittieren, ohne dass die Zeile sofort wieder fällig wird.
create or replace function public.push_outbox_debounce()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT'
    or new.digest is distinct from old.digest
    or new.body is distinct from old.body
    or new.title_evening is distinct from old.title_evening
    or new.title_change is distinct from old.title_change
  then
    new.due_at := now() + interval '60 seconds';
  end if;
  return new;
end $$;

create trigger push_outbox_debounce_trg
  before insert or update on public.push_outbox
  for each row execute function public.push_outbox_debounce();

-- Der einzige Schreibweg in den Ausgangskorb (#132). SECURITY DEFINER wie
-- `register_push_device`, und aus einem harten Grund: „schreiben ja, lesen
-- nein" ist an der Tabelle nicht zu haben — Postgres verlangt für
-- `on conflict do update` das SELECT-Recht, und mit Recht, aber ohne
-- SELECT-Policy scheitert der Upsert daran, dass die bestehende Zeile für
-- den Aufrufer unsichtbar ist.
--
-- Die Funktion kann keine Zugehörigkeit verändern: Die `group_id` kommt aus
-- `auth.uid()` und nie aus der Nutzlast, und Einträge zu gruppenfremden
-- Personen fallen im Join heraus. `keep_from` räumt vergangene Tage weg,
-- damit die Tabelle auf Personen × Planwoche beschränkt bleibt.
create or replace function public.publish_push_outbox(
  entries jsonb,
  keep_from date
)
returns void language plpgsql security definer set search_path = public as $$
declare
  gid uuid := auth.uid();
begin
  if gid is null or not public.my_group_active() then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  delete from public.push_outbox
    where group_id = gid and plan_date < keep_from;

  insert into public.push_outbox (
    group_id, person_id, plan_date, digest, body, title_evening, title_change
  )
  select
    gid,
    person.id,
    (entry->>'plan_date')::date,
    entry->>'digest',
    entry->>'body',
    entry->>'title_evening',
    entry->>'title_change'
  from jsonb_array_elements(coalesce(entries, '[]'::jsonb)) as entry
  join public.persons person
    on person.id = (entry->>'person_id')::uuid
   and person.group_id = gid
  on conflict (group_id, person_id, plan_date) do update
    set digest = excluded.digest,
        body = excluded.body,
        title_evening = excluded.title_evening,
        title_change = excluded.title_change;
end $$;

-- Übernimmt eine BESTEHENDE Gruppe: für Gruppen von vor #106 und für die
-- Übergabe an eine Nachfolgerin. Beweis ist das Gruppen-Login (Handle +
-- Gruppenpasswort) — und nur, solange die Gruppe noch keinen Admin hat.
-- Grenze des geteilten Logins: Das erste Postfach gewinnt.
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

-- Alle verknüpften Gruppen fürs Konsolen-UI (leer, wenn keine). Die frühere
-- Einzelform könnte bei mehreren Gruppen nur eine beliebige davon zeigen.
create or replace function public.my_admin_groups()
returns table (group_id uuid, handle text, name text)
language sql stable security definer set search_path = public as $$
  select g.id, g.handle, g.name
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid()
   order by g.created_at;
$$;

-- Setzt das Passwort des GRUPPEN-Kontos neu — die Rettungsleine, wenn das
-- geteilte Passwort verloren ging oder jemand alle ausgesperrt hat.
-- Alle drei Aktionen nennen IHRE Gruppe. Die Eigentumsprüfung
-- `user_id = auth.uid() and group_id = target_group` ist der eigentliche
-- Inhalt der Signaturen — ohne sie träfe ein Verwalter die Gruppe eines
-- anderen.
create or replace function public.admin_reset_group_password(
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
-- Admin-Passwort erneut. Danach kann ein anderes Konto über claim_admin_group
-- neu einrasten; Gruppendaten und Verwalter-Konto bleiben unberührt, der
-- Trigger vermerkt den Zeitpunkt in `released_at`.
-- Bewusste Grenze: Wer Postfach UND Passwort verliert, kommt an seine
-- Gruppen nicht mehr heran — Selbstbedienung daran vorbei wäre die
-- Übernahme-Lücke, die das Einrasten gerade verhindert (jedes Mitglied kennt
-- das Gruppenpasswort). Vorgesehen dafür ist eine Übernahme mit
-- Widerspruchsfrist, nicht ein zweiter Schlüssel hier.
create or replace function public.admin_release_group(
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
-- Das Verwalter-Konto überlebt: Bei bis zu 5 Gruppen wäre ein Selbst-Löschen
-- Datenverlust an den übrigen. Deshalb wird hier genau EINE Zeile in
-- `auth.users` entfernt — die der Zielgruppe. `test/schema_test.dart` zählt
-- das nach.
create or replace function public.admin_delete_group(
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

-- ------------------------------------------------ Push-Registrierung (#101)

-- Registrierung über SECURITY DEFINER statt direktem Upsert: Wechselt ein
-- Gerät die Gruppe, liegt seine alte Zeile unter fremder group_id — die RLS
-- zeigt sie nicht, der Upsert liefe in eine Unique-Verletzung auf einer
-- unsichtbaren Zeile (dieselbe Falle wie seinerzeit bei plan_overrides).
create or replace function public.register_push_device(
  device_token text,
  person uuid,
  device_platform text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not public.my_group_active() then
    raise exception 'not allowed';
  end if;
  if coalesce(device_token, '') = '' then
    raise exception 'missing token';
  end if;
  if device_platform not in ('android', 'web') then
    raise exception 'unknown platform';
  end if;
  if person is not null and not exists (
    select 1 from public.persons p
     where p.id = person and p.group_id = me
  ) then
    raise exception 'unknown person';
  end if;

  delete from public.push_devices where token = device_token;
  insert into public.push_devices (token, group_id, person_id, platform)
  values (device_token, me, person, device_platform);
end $$;

create or replace function public.unregister_push_device(
  device_token text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.push_devices
   where token = device_token and group_id = auth.uid();
end $$;

-- Was ist fällig? (#132) Dieselben Regeln wie `dueMessages` in
-- `lib/core/push_digest.dart`, nur ohne den Teil, der den Text macht — der
-- steht schon im Korb. Das Fenster reicht von der Abendzeit des Vortages bis
-- zur Abfahrtszeit; **`at time zone 'Europe/Berlin'` ist Pflicht**, weil
-- Postgres in UTC läuft und ein Fehler hier zweimal im Jahr eine Stunde
-- danebenläge, ohne dass ein Test es sähe.
--
-- `'raus'` ist `removedDigest` aus push_digest.dart. Der Wert steht hier ein
-- zweites Mal; `test/schema_test.dart` hält beide zusammen.
create or replace function public.push_due(at timestamptz default now())
returns table (
  token text,
  group_id uuid,
  person_id uuid,
  plan_date date,
  kind text,
  digest text,
  title text,
  body text
)
language sql security definer set search_path = public as $$
  with ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      box.body,
      box.title_evening,
      box.title_change,
      case
        when evening.digest is null then
          case
            when prefs.evening_enabled and box.digest <> 'raus' then 'evening'
          end
        when prefs.changes_enabled
          and box.digest is distinct from coalesce(change.digest, evening.digest)
          and box.due_at is not null
          and box.due_at <= at
          and (change.sent_at is null
               or at - change.sent_at >= interval '30 minutes')
        then 'change'
      end as kind
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      left join public.push_log evening
        on evening.group_id = box.group_id
       and evening.person_id = box.person_id
       and evening.plan_date = box.plan_date
       and evening.kind = 'evening'
      left join public.push_log change
        on change.group_id = box.group_id
       and change.person_id = box.person_id
       and change.plan_date = box.plan_date
       and change.kind = 'change'
    where at >= ((box.plan_date - 1)::timestamp + prefs.evening_time)
                  at time zone 'Europe/Berlin'
      and at <  (box.plan_date::timestamp + prefs.departure_time)
                  at time zone 'Europe/Berlin'
  )
  select
    device.token,
    ready.group_id,
    ready.person_id,
    ready.plan_date,
    ready.kind,
    ready.digest,
    case when ready.kind = 'evening'
      then ready.title_evening else ready.title_change end,
    ready.body
  from ready
    join public.push_devices device
      on device.group_id = ready.group_id
     and device.person_id = ready.person_id
  where ready.kind is not null;
$$;

revoke all on function public.push_due(timestamptz) from anon, authenticated;

-- ---------------------------------------------------------------- Abholer
--
-- Der Minutentakt weckt nur; entschieden und gesendet wird in der Function
-- `flush-push`. Der Umweg ist Absicht: FCM braucht ein Dienstkonto, und das
-- gehört zu den übrigen Server-Geheimnissen, nicht in die Datenbank.
--
-- **Zugangsdaten aus dem Vault, nicht aus einer Tabelle.** Eine Spalte mit
-- dem Job-Geheimnis stünde für jeden mit service_role-Zugang im Klartext und
-- landete in jedem Datenbank-Abzug. Fehlen die Einträge, tut die Funktion
-- **nichts** — so bleibt der lokale Teststack und jede Frischinstallation
-- lauffähig, ohne dass jemand Geheimnisse anlegen muss.
--
-- Einmalig einzurichten (Betreiber, nicht im Repo):
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
create or replace function public.flush_due_push()
returns void language plpgsql security definer
set search_path = public, vault, net as $$
declare
  base_url text;
  job_secret text;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  if base_url is null or job_secret is null then
    return;
  end if;

  -- Nichts zu tun heißt: nicht anklopfen. Spart im Normalfall 1440 Aufrufe
  -- am Tag, und die Abfrage ist ein Index-Treffer.
  if not exists (select 1 from public.push_due()) then
    return;
  end if;

  perform net.http_post(
    url := base_url || '/flush-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', job_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function public.flush_due_push() from anon, authenticated;

select cron.schedule(
  'flush-due-push',
  '* * * * *',
  $$select public.flush_due_push()$$
);

-- --------------------------------------------------------------------- RLS

alter table public.groups              enable row level security;
alter table public.persons             enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_participations enable row level security;
alter table public.settings            enable row level security;
alter table public.plan_availability   enable row level security;
alter table public.plan_overrides      enable row level security;
alter table public.plan_notes          enable row level security;
alter table public.push_devices        enable row level security;
alter table public.notification_prefs  enable row level security;
-- Bewusst KEINE Policies auf group_admins: Kein Client liest oder schreibt
-- die Verknüpfung direkt, alles läuft über die Konsolen-Funktionen.
alter table public.group_admins        enable row level security;
-- Ebenso ohne Policy: Das Versand-Gedächtnis gehört allein dem Job
-- (service_role umgeht RLS). Eine Client-Policy gäbe jedem Mitglied die
-- Möglichkeit, Nachrichten zu unterdrücken oder erneut auszulösen.
alter table public.push_log            enable row level security;

-- Nur die eigene Gruppe lesen. Insert macht der Trigger.
--
-- Bewusst KEINE Update-Policy (#108): Eine Gruppe ändert sich ausschließlich
-- über die SECURITY-DEFINER-Funktionen der Konsole und künftig über den
-- vorgesehenen Aufräum-Job mit Service-Role-Key. Könnte ein Client `status`
-- schreiben, könnte er sich selbst freischalten — genau das machte die alte
-- Freigabe-Policy nötig und mit ihr die Sonderrolle einer Admin-Gruppe.
create policy groups_select on public.groups for select to authenticated
  using (id = auth.uid());

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
create policy plan_notes_isolated on public.plan_notes
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy push_devices_isolated on public.push_devices
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy notification_prefs_isolated on public.notification_prefs
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

-- Ausgangskorb (#132): null Policies, wie `push_log` und `group_admins`.
-- „Schreiben ja, lesen nein" ist an der Tabelle selbst nicht zu haben —
-- `insert ... on conflict do update` verlangt das SELECT-Recht, und mit
-- Recht, aber ohne SELECT-Policy scheitert es an „new row violates row-level
-- security policy". Deshalb läuft der Schreibpfad über
-- `publish_push_outbox` (SECURITY DEFINER, siehe oben).
alter table public.push_outbox enable row level security;

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

-- Und sofort wieder weg für den Ausgangskorb (#132). Der Sammel-Grant oben
-- gibt Rechte auf JEDE Tabelle — ohne diese Rücknahme stünde dem Client der
-- direkte Weg an `publish_push_outbox` vorbei offen, und der Riegel hinge
-- allein daran, dass niemand später eine Policy ergänzt.
-- `test/e2e/rls_e2e_test.dart` beweist am echten Postgres, dass ein Client
-- hier weder lesen noch schreiben kann.
revoke all on public.push_outbox from anon, authenticated;
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

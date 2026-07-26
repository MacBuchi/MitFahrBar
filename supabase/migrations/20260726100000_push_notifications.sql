-- Push-Benachrichtigungen für den Wochenplaner (Issue #101).
--
-- Der Wunsch aus der Gruppe: am Vorabend erfahren, wie der nächste Tag
-- aussieht — und mitbekommen, wenn sich bis zur Abfahrt noch etwas ändert.
--
-- Drei Tabellen, drei verschiedene Aufgaben:
--   push_devices        WOHIN  (ein FCM-Token je Gerät)
--   notification_prefs  WANN   (Uhrzeiten je Person)
--   push_log            WAS SCHON RAUS IST (Versand-Gedächtnis)
--
-- Was hier bewusst NICHT steht: der vorgeschlagene Fahrer. Er bleibt eine
-- berechnete Kennzahl (KONZEPT.md §4, lib/core/fairness.dart) — `push_log`
-- hält nur einen Hash des Tageszustands, damit der Versand-Job erkennt, ob
-- sich seit der letzten Nachricht etwas geändert hat. Ein gespeicherter
-- Fahrer wäre die zweite Wahrheit über den Tag.
--
-- Mindestversion wird NICHT gehoben: Es wird nichts entfernt oder
-- umbenannt, was ein veröffentlichter Client liest. Ältere Clients kennen
-- die Tabellen schlicht nicht und bekommen keine Benachrichtigungen.

-- ----------------------------------------------------------------- Geräte

-- Ein Gerät = eine Zeile. Der Primärschlüssel ist der Token, NICHT
-- (group_id, token): FCM-Token sind global eindeutig, eine Kollision
-- zwischen Gruppen ist konstruktiv unmöglich. Und ein Gerät gehört zu genau
-- EINER Gruppe — meldet es sich in einer anderen an, muss die alte Zeile
-- weichen statt danebenzustehen. Die „group_id gehört in den Schlüssel"-
-- Regel zielt auf fachliche Schlüssel (plan_date, person_id …), die ohne
-- group_id über alle Gruppen eindeutig wären; ein Token ist das nicht.
create table public.push_devices (
  token text primary key,
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  -- Wer an diesem Gerät benachrichtigt wird. Das ist KEIN Login: Jeder kann
  -- jeden wählen, genauso wie im Planer jeder für jeden einträgt. Es ist
  -- eine Zustelladresse, kein Identitätsnachweis — „eine Gruppe = ein
  -- Login" bleibt unangetastet. NULL = registriert, aber noch niemandem
  -- zugeordnet, bekommt also nichts.
  person_id uuid references public.persons(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index push_devices_group_idx on public.push_devices (group_id);
create index push_devices_person_idx
  on public.push_devices (group_id, person_id);

-- ------------------------------------------------------------ Einstellungen

-- Uhrzeiten je PERSON, nicht je Gerät: Wer Handy und Laptop registriert hat,
-- soll nicht zwei Einstellungen pflegen müssen.
--
-- Alle Zeiten sind Europe/Berlin. Eine Fahrgemeinschaft fährt an einem Ort
-- zur Arbeit; eine Zeitzone je Person wäre Aufwand ohne jeden Nutzen.
--
-- **Keine Zeile = keine Benachrichtigungen.** Die Zeile entsteht, wenn
-- jemand im Screen einschaltet. Damit gibt es genau eine Wahrheit darüber,
-- wer etwas bekommt — der Versand-Job braucht keine Vorgabewerte zu kennen
-- und kann keine an den DB-Defaults vorbeidriften.
create table public.notification_prefs (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  evening_enabled boolean not null default true,
  -- Der Abend-Push für den Folgetag.
  evening_time time not null default '21:00',
  -- Ende des Änderungs-Fensters. Danach nützt keine Nachricht mehr — und ein
  -- nachgeholter Lauf nach einem Ausfall darf niemanden nachts wecken.
  departure_time time not null default '07:30',
  changes_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (group_id, person_id)
);

-- ------------------------------------------------------- Versand-Gedächtnis

-- Was ist für (Person, Tag, Art) schon raus — und mit welchem Tageszustand?
-- `digest` ist ein Hash über das, was die Person gesehen hätte, NICHT der
-- Plan selbst (siehe Kopfkommentar).
--
-- Eine Zeile je Art: 'evening' wird einmal geschrieben, 'change' bei jeder
-- gemeldeten Änderung fortgeschrieben; `sent_at` trägt dabei den
-- Mindestabstand zwischen zwei Änderungs-Meldungen.
--
-- Kein `default auth.uid()` auf group_id: Diese Tabelle schreibt
-- ausschließlich der Versand-Job mit dem service_role-Key, und der hat
-- keine auth.uid().
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

-- Der Job liest das Fenster um „heute/morgen" und räumt Altes ab.
create index push_log_date_idx on public.push_log (plan_date);

-- --------------------------------------------------------------- Funktionen

-- Registrierung über SECURITY DEFINER statt direktem Upsert.
--
-- Grund: Wechselt ein Gerät die Gruppe, liegt seine alte Zeile unter fremder
-- group_id — die RLS zeigt sie nicht, der Upsert liefe also in eine
-- Unique-Verletzung auf einer Zeile, die der Client nicht einmal sehen darf.
-- Dieselbe Falle wie seinerzeit bei plan_overrides. Die Funktion räumt die
-- alte Zeile weg und legt sauber neu an.
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
  -- Die Person muss zur eigenen Gruppe gehören, sonst könnte eine Gruppe
  -- Zustellungen an fremde Personen-Ids hängen.
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

-- Abmelden räumt die eigene Zeile weg. Das geht auch per DELETE über die
-- RLS-Policy — die Funktion existiert, damit der Client denselben Weg für
-- An- und Abmelden nimmt und nicht am Token vorbei löschen kann.
create or replace function public.unregister_push_device(
  device_token text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.push_devices
   where token = device_token and group_id = auth.uid();
end $$;

-- --------------------------------------------------------------------- RLS

alter table public.push_devices       enable row level security;
alter table public.notification_prefs enable row level security;
-- Bewusst KEINE Policy auf push_log: Das Versand-Gedächtnis gehört allein
-- dem Job (service_role umgeht RLS). Eine Client-Policy gäbe jedem Mitglied
-- die Möglichkeit, Nachrichten zu unterdrücken oder erneut auszulösen —
-- dasselbe Muster wie bei group_admins.
alter table public.push_log           enable row level security;

create policy push_devices_isolated on public.push_devices
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

create policy notification_prefs_isolated on public.notification_prefs
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

-- ------------------------------------------------------------------ Grants
-- Explizit statt über `alter default privileges`, gleiche Begründung wie in
-- 20260723090000: Was die Client-Rollen dürfen, soll im File stehen.

grant select, insert, update, delete
  on public.push_devices, public.notification_prefs to anon, authenticated;
grant all
  on public.push_devices, public.notification_prefs, public.push_log
  to service_role;
grant execute on function
  public.register_push_device(text, uuid, text),
  public.unregister_push_device(text)
  to anon, authenticated, service_role;

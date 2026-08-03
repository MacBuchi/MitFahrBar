-- Erinnerung kurz vor der Abfahrt (#164) — hin und zurück.
--
-- Der Wunsch aus der Gruppe: „eine Meldung, wenn es gleich losgeht". Möglich
-- wird das erst durch #139 — vorher gab es keine Uhrzeit, an die sich eine
-- Erinnerung hängen ließe.
--
-- **Opt-in, Vorgabe AUS.** Anders als der Abend-Blick meldet sich diese
-- Nachricht an einem Tag, an dem gar nichts passiert ist; wer das nicht will,
-- soll es nicht einmal abschalten müssen.
--
-- Rein additiv: Neue Spalten mit Vorgabewerten, ein erweiterter CHECK, eine
-- neu geschriebene `push_due()`. Ein veröffentlichter Client (0.57.0) ruft
-- `publish_push_outbox` ohne die neuen Felder — die bleiben dann NULL, und
-- ohne Kopfzeile entsteht keine Erinnerung. `min_supported_version` bleibt,
-- wo sie ist.

-- ------------------------------------------------- notification_prefs
-- Ein Vorlauf für beide Richtungen: Wer morgens fünf Minuten braucht,
-- braucht sie abends auch. Zwei Regler für dieselbe Frage wären einer zu
-- viel. Die Vorgabe 15 muss mit `defaultReminderLead` in
-- `lib/models/notification_prefs.dart` übereinstimmen.
alter table public.notification_prefs
  add column reminders_enabled boolean not null default false,
  add column reminder_lead_minutes integer not null default 15
    check (reminder_lead_minutes between 0 and 120);

-- --------------------------------------------------------- push_log
-- Zwei neue Arten. Der CHECK trägt keinen selbst vergebenen Namen — er
-- entstand als Spalten-Constraint in 20260726100000. Statt den generierten
-- Namen zu raten, wird er über seine Definition gesucht: Ein danebenliegender
-- Name ließe den `drop` ins Leere laufen, der neue CHECK stünde daneben, und
-- die alte Bedingung wiese jede Erinnerung ab — still, denn ein abgewiesenes
-- Protokoll sieht wie ein nie gesendeter Push aus.
do $$
declare existing text;
begin
  select conname into existing
    from pg_constraint
   where conrelid = 'public.push_log'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) like '%kind%';
  if existing is not null then
    execute format('alter table public.push_log drop constraint %I', existing);
  end if;
end $$;

alter table public.push_log add constraint push_log_kind_check
  check (kind in ('evening', 'change', 'departure_out', 'departure_return'));

-- -------------------------------------------------------- push_outbox
-- Zwei weitere Kopfzeilen, aus demselben Grund wie die ersten beiden: Welche
-- Art die Meldung wird, weiß erst der Versand — und deutsche Wörter bleiben
-- in Dart. NULL heißt „für diese Richtung gibt es keine Gruppenzeit".
alter table public.push_outbox
  add column title_out text,
  add column title_return text;

-- Der Entprell-Trigger vergleicht die beiden NEUEN Spalten bewusst nicht.
--
-- Grund ist der Alt-Client: 0.57.0 schreibt sie als NULL, der stündliche Job
-- schreibt sie gefüllt. Stünden sie im Vergleich, wechselte der Inhalt
-- zwischen beiden Schreibern hin und her, und jede Änderung schöbe `due_at`
-- 60 Sekunden nach hinten — die Zeile wäre nie fällig, und zwar für ALLE
-- Meldungen dieser Person. Der Preis ist klein: Eine geänderte Abfahrtszeit
-- allein löst keinen Versand aus. Sie soll es auch nicht (#139).
--
-- Damit ein Alt-Client eine gefüllte Kopfzeile nicht wieder ausleert, hält
-- der Upsert unten sie mit `coalesce` fest. Eine wirklich entfernte
-- Gruppenzeit macht das nicht rückgängig: Ohne `outbound_time` findet
-- `push_due()` kein Fenster, die stehengebliebene Kopfzeile wird nie benutzt.
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
    group_id, person_id, plan_date, digest, body,
    title_evening, title_change, title_out, title_return
  )
  select
    gid,
    person.id,
    (entry->>'plan_date')::date,
    entry->>'digest',
    entry->>'body',
    entry->>'title_evening',
    entry->>'title_change',
    entry->>'title_out',
    entry->>'title_return'
  from jsonb_array_elements(coalesce(entries, '[]'::jsonb)) as entry
  join public.persons person
    on person.id = (entry->>'person_id')::uuid
   and person.group_id = gid
  on conflict (group_id, person_id, plan_date) do update
    set digest = excluded.digest,
        body = excluded.body,
        title_evening = excluded.title_evening,
        title_change = excluded.title_change,
        title_out = coalesce(excluded.title_out, push_outbox.title_out),
        title_return = coalesce(
          excluded.title_return, push_outbox.title_return);
end $$;

-- ----------------------------------------------------------- push_due
-- Jetzt zwei Fenster statt einem, und das ist der Kern dieser Migration.
--
-- Der Plan-Teil reicht vom Abend davor bis zur persönlichen `departure_time`.
-- Die Rückfahrt-Erinnerung liegt weit dahinter — in einem gemeinsamen Fenster
-- wäre sie nie fällig geworden. Deshalb ein eigener Zweig mit eigener
-- Bedingung, zusammengeführt per `union all`.
--
-- `'raus'` (removedDigest) und `'fix'` (confirmedDigest) stehen hier ein
-- zweites Mal; `test/schema_test.dart` hält sie mit `push_digest.dart`
-- zusammen. Die Erinnerung schließt nur `'raus'` aus — an einem
-- eingetragenen Tag fährt die Gruppe gerade, das ist der Moment, für den sie
-- gebaut wurde.
--
-- **`at time zone 'Europe/Berlin'` ist auch hier Pflicht**: Postgres läuft in
-- UTC, und ein Fehler liefe zweimal im Jahr eine Stunde daneben, ohne dass
-- ein Test es sähe.
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
  with plan_ready as (
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
            when prefs.evening_enabled
              and box.digest <> 'raus'
              and box.digest <> 'fix'
            then 'evening'
          end
        when prefs.changes_enabled
          and box.digest <> 'fix'
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
  ),
  reminder_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      leg.kind,
      leg.title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      join public.group_defaults gd on gd.group_id = box.group_id
      -- Zwei Beine aus einer Zeile: derselbe Riegel, dieselbe Rechnung,
      -- einmal geschrieben. `lateral`, weil die Werte aus gd und box kommen.
      cross join lateral (values
        ('departure_out'::text, gd.outbound_time, box.title_out),
        ('departure_return'::text, gd.return_time, box.title_return)
      ) as leg(kind, leg_time, title)
      -- Zeitgetrieben, also genau einmal: Ein Nachholen wäre die Erinnerung
      -- an eine Abfahrt, die schon war. Kein `due_at`, kein Digest-Vergleich.
      left join public.push_log sent
        on sent.group_id = box.group_id
       and sent.person_id = box.person_id
       and sent.plan_date = box.plan_date
       and sent.kind = leg.kind
    where prefs.reminders_enabled
      and box.digest <> 'raus'
      and leg.leg_time is not null
      and leg.title is not null
      and sent.person_id is null
      and box.plan_date = (at at time zone 'Europe/Berlin')::date
      and at >= ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
                 - make_interval(mins => prefs.reminder_lead_minutes)
      and at <  ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
  ),
  ready as (
    select
      group_id, person_id, plan_date, digest, kind,
      case when kind = 'evening' then title_evening else title_change end
        as title,
      body
    from plan_ready
    where kind is not null
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from reminder_ready
  )
  select
    device.token,
    ready.group_id,
    ready.person_id,
    ready.plan_date,
    ready.kind,
    ready.digest,
    ready.title,
    ready.body
  from ready
    join public.push_devices device
      on device.group_id = ready.group_id
     and device.person_id = ready.person_id;
$$;

revoke all on function public.push_due(timestamptz) from anon, authenticated;

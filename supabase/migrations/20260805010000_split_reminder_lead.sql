-- 20260805010000_split_reminder_lead.sql
-- Ein eigener Vorlauf je Richtung (Issue #168).
--
-- REVIDIERT die Begründung aus 20260803140000: „Wer morgens fünf Minuten
-- braucht, braucht sie abends auch. Zwei Regler für dieselbe Frage wären
-- einer zu viel." Die Annahme war falsch, und der Grund ist konkret: Hin-
-- und Rückweg starten nicht am selben Ort. Zum Treffpunkt am Morgen sind es
-- fünfzehn Minuten, zum Treffpunkt für die Rückfahrt dreißig — das ist nicht
-- dieselbe Frage, sondern zwei.
--
-- **Additiv, und `reminder_lead_minutes` behält seinen Namen.** Umbenennen
-- hieße, eine Spalte zu entfernen, die ein veröffentlichter Client (0.58.0
-- bis 0.61.0) liest und schreibt — dann müsste `min_supported_version`
-- hoch, und das wirft jeden alten Client auf den Sperr-Schirm. Der alte
-- Name ist ab hier die **Hinfahrt**; die Rückfahrt kommt daneben. Ein
-- Alt-Client schreibt nur die Hinfahrt und lässt die neue Spalte auf ihrer
-- Vorgabe stehen — er verliert nichts, er kennt nur die Hälfte.
--
-- `min_supported_version` bleibt deshalb, wo sie ist.

-- ------------------------------------------------- notification_prefs
alter table public.notification_prefs
  add column if not exists reminder_lead_return_minutes integer not null
    default 15
    check (reminder_lead_return_minutes between 0 and 120);

-- ---------------------------------------------------------- push_due
-- Der Erinnerungs-Zweig holt den Vorlauf jetzt aus derselben Zeile wie
-- Uhrzeit und Kopfzeile: Das `values`-Paar trägt ihn als vierte Spalte, und
-- `make_interval` rechnet mit `leg.lead_minutes` statt mit dem einen Wert
-- aus `prefs`. Damit bleibt es bei EINER Rechnung für beide Beine — genau
-- die Eigenschaft, für die das `lateral` überhaupt da ist.
--
-- Alles andere ist unverändert; die Funktion steht vollständig, weil
-- `create or replace` keinen Teilaustausch kennt.

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
    where box.kind = 'plan'
      and at >= ((box.plan_date - 1)::timestamp + prefs.evening_time)
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
      cross join lateral (values
        ('departure_out'::text, gd.outbound_time, box.title_out,
         prefs.reminder_lead_minutes),
        ('departure_return'::text, gd.return_time, box.title_return,
         prefs.reminder_lead_return_minutes)
      ) as leg(kind, leg_time, title, lead_minutes)
      left join public.push_log sent
        on sent.group_id = box.group_id
       and sent.person_id = box.person_id
       and sent.plan_date = box.plan_date
       and sent.kind = leg.kind
    where box.kind = 'plan'
      and prefs.reminders_enabled
      and box.digest <> 'raus'
      and leg.leg_time is not null
      and leg.title is not null
      and sent.person_id is null
      and box.plan_date = (at at time zone 'Europe/Berlin')::date
      and at >= ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
                 - make_interval(mins => leg.lead_minutes)
      and at <  ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
  ),
  roster_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      'roster'::text as kind,
      -- Wer raus ist, liest „Ausgetragen" — dieselbe Kopfzeile, die auch
      -- die Änderungs-Meldung dafür benutzt. Ein zweites Wort für dieselbe
      -- Sache wäre eine zweite Sprache.
      case when box.digest = 'raus' then box.title_change else box.title_roster
        end as title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      left join public.push_log sent
        on sent.group_id = box.group_id
       and sent.person_id = box.person_id
       and sent.plan_date = box.plan_date
       and sent.kind = 'roster'
    where box.kind = 'plan'
      and prefs.instant_enabled
      and box.roster_due_at is not null
      and box.roster_due_at <= at
      and box.digest is distinct from sent.digest
      and box.title_roster is not null
      and box.plan_date >= (at at time zone 'Europe/Berlin')::date
      and (box.plan_date > (at at time zone 'Europe/Berlin')::date
           or at < (box.plan_date::timestamp + prefs.departure_time)
                     at time zone 'Europe/Berlin')
  ),
  trip_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      'trip'::text as kind,
      box.title_change as title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
    where box.kind = 'trip'
      and prefs.instant_enabled
      and box.due_at is not null
      and box.due_at <= at
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
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from roster_ready
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from trip_ready
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

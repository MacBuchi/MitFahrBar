-- Der Ausgangskorb bekommt eine Art (#163, Schritt 1 von 2: Struktur).
--
-- Bisher hielt `push_outbox` genau eine Zeile je (Gruppe, Person, Tag) — den
-- Zustand der PLANUNG. Für die Meldung über eine geänderte oder gelöschte
-- FAHRT braucht es daneben eine zweite Zeile zum selben Tag: Beide können
-- gleichzeitig offen sein (die laufende Woche wird umgeplant, während jemand
-- eine alte Fahrt korrigiert), und sie sagen Verschiedenes.
--
-- Deshalb wandert `kind` in den Primärschlüssel. Diese Migration ändert
-- ausschließlich die Struktur; das Verhalten kommt in der zweiten.
--
-- **Ein veröffentlichter Client merkt davon nichts**: Er ruft
-- `publish_push_outbox` ohne `kind`, der Default macht daraus 'plan' — genau
-- die Zeilen, die er bisher schrieb. `min_supported_version` bleibt.

alter table public.push_outbox
  add column kind text not null default 'plan'
    check (kind in ('plan', 'trip'));

alter table public.push_outbox drop constraint push_outbox_pkey;
alter table public.push_outbox
  add constraint push_outbox_pkey
  primary key (group_id, person_id, plan_date, kind);

-- Der Schreibweg zieht nach: `kind` aus der Nutzlast, vierspaltiges
-- Konfliktziel — und ein Purge, der **nur** Plan-Zeilen anfasst.
--
-- **Der Purge-Filter ist der teuerste Einzelfehler dieser Migration.** Ohne
-- `kind = 'plan'` löschte jeder Schreibvorgang des Clients alle Zeilen vor
-- der Planwoche — also genau die Meldungen über ältere Fahrten, für die es
-- diese Änderung gibt. Sie stürben, bevor sie eine Minute später verschickt
-- würden, und im Log stünde nichts. Trip-Zeilen räumt der Versand selbst
-- weg (nach Zustellung) und `tool/notify.dart` als Boden (nach sieben Tagen).
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
    where group_id = gid and kind = 'plan' and plan_date < keep_from;

  insert into public.push_outbox (
    group_id, person_id, plan_date, kind, digest, body,
    title_evening, title_change, title_out, title_return
  )
  select
    gid,
    person.id,
    (entry->>'plan_date')::date,
    coalesce(entry->>'kind', 'plan'),
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
  on conflict (group_id, person_id, plan_date, kind) do update
    set digest = excluded.digest,
        body = excluded.body,
        title_evening = excluded.title_evening,
        title_change = excluded.title_change,
        title_out = coalesce(excluded.title_out, push_outbox.title_out),
        title_return = coalesce(
          excluded.title_return, push_outbox.title_return);
end $$;

-- Die bestehenden Zweige der Auswahl gelten ab jetzt ausdrücklich für die
-- Planung. Ohne den Filter läse der Abend-Blick eine Trip-Zeile als Plan des
-- Tages — und schickte den Text einer Fahrtänderung als „Morgen (Do)".
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
        ('departure_out'::text, gd.outbound_time, box.title_out),
        ('departure_return'::text, gd.return_time, box.title_return)
      ) as leg(kind, leg_time, title)
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

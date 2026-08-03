-- Sofort-Meldungen (#163, Schritt 2 von 2: Verhalten).
--
-- Zwei Wünsche aus der Gruppe, ein Schalter:
--
--   1. „Wenn mich jemand anderes ein- oder austrägt, will ich das sofort
--      erfahren" — nicht erst am Abend.
--   2. „Wenn jemand eine eingetragene Fahrt ändert oder löscht, sollen es
--      die Beteiligten erfahren" — auch bei älteren Fahrten.
--
-- Beide feuern AUSSERHALB des Abend-Fensters. Sie an den Abend-Blick zu
-- hängen hieße, sie genau dann abzuschalten, wenn sie gebraucht werden;
-- deshalb ein eigener Schalter, Vorgabe AN. Er wirkt nur für Personen, die
-- Benachrichtigungen überhaupt eingeschaltet haben — ohne Zeile in
-- `notification_prefs` kommt nach wie vor gar nichts.
alter table public.notification_prefs
  add column instant_enabled boolean not null default true;

-- `suppress_roster` ist die Selbst-Unterdrückung: Wer selbst tippt, braucht
-- keine Meldung darüber. Sie ist **best effort** und keine Zugriffskontrolle
-- — sie hängt an der Geräte-Zuordnung „Ich bin" (#121), und die ist
-- ausdrücklich kein Login. Der stündliche Job schreibt sie als `false` und
-- überstimmt damit im Reparaturfall: Lieber eine Meldung zu viel als eine
-- verlorene.
--
-- `roster_due_at` ist eine ZWEITE Fälligkeit neben `due_at`. Eine gemeinsame
-- ginge nicht: Der Abend-Blick quittiert mit `due_at = null`, und eine
-- Roster-Meldung, die noch offen ist, wäre damit stillschweigend erledigt.
alter table public.push_outbox
  add column suppress_roster boolean not null default false,
  add column roster_due_at timestamptz,
  add column title_roster text;

create index push_outbox_roster_idx on public.push_outbox (roster_due_at)
  where roster_due_at is not null;

-- `roster` kommt dazu, `trip` bewusst NICHT: Trip-Zeilen werden nach dem
-- Versand GELÖSCHT statt quittiert. Ein Protokolleintrag wäre die zweite
-- Buchführung über dasselbe — und die Zeile trägt keinen wiederkehrenden
-- Zustand, über den er wachen könnte.
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
  check (kind in ('evening', 'change', 'departure_out', 'departure_return',
                  'roster'));

-- Der Roster-Detektor sitzt im Entprell-Trigger, und das ist der Kern
-- dieser Migration.
--
-- **`tg_op = 'UPDATE'` ist keine Vorsicht, sondern der Riegel.** Beim ersten
-- Füllen des Korbs entstehen Zeilen für JEDE Person — eine neue Gruppe, ein
-- Wochenwechsel, ein Gerät, das den Korb erstmals schreibt. Ohne die
-- Bedingung weckte das die halbe Gruppe mit „Eingetragen" für Tage, an denen
-- sich nichts geändert hat.
--
-- **Er ist doppelt, und die zweite Hälfte ist unsichtbar:** Beim INSERT ist
-- `old` nicht belegt, `old.digest <> 'fix'` ergibt also NULL und die ganze
-- Bedingung wird NULL — sie feuert nicht. Wer sie eines Tages „null-sicher"
-- macht (`coalesce(old.digest, '')`), nimmt genau diese Hälfte weg; erst dann
-- trägt `tg_op` allein. Beides zusammen wurde am echten Postgres rot
-- verifiziert: null-sicher UND ohne tg_op → die erste Korb-Füllung weckt die
-- ganze Gruppe.
--
-- **`fix` ist ausgeschlossen, weil sonst zwei Meldungen entstünden:** Wird
-- eine Fahrt eingetragen, wechselt der Digest derer, die nicht mitfuhren, auf
-- `raus` — für diesen Fall gibt es die Fahrt-Meldung, die den Editor-Weg
-- abdeckt. Ohne den Ausschluss käme zusätzlich ein „Ausgetragen".
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

  if tg_op = 'UPDATE'
    and new.kind = 'plan'
    and (old.digest = 'raus') is distinct from (new.digest = 'raus')
    and old.digest <> 'fix'
    and new.digest <> 'fix'
    and not new.suppress_roster
  then
    new.roster_due_at := now() + interval '60 seconds';
  end if;

  return new;
end $$;

-- Der Schreibweg reicht die beiden neuen Felder durch. `suppress_roster`
-- kommt aus der Nutzlast (das schreibende Gerät weiß, wer es ist),
-- `title_roster` wie die übrigen Kopfzeilen aus Dart.
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
    title_evening, title_change, title_out, title_return,
    title_roster, suppress_roster
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
    entry->>'title_return',
    entry->>'title_roster',
    coalesce((entry->>'suppress_roster')::boolean, false)
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
          excluded.title_return, push_outbox.title_return),
        title_roster = coalesce(
          excluded.title_roster, push_outbox.title_roster),
        suppress_roster = excluded.suppress_roster;
end $$;

-- Vier Zweige statt zwei. Neu:
--
--   `roster` — hängt an `roster_due_at` und nicht an `due_at`, feuert
--   außerhalb jedes Abend-Fensters, aber nie in die Vergangenheit: künftige
--   Tage immer, der heutige bis zur persönlichen `departure_time`. Der
--   Vergleich mit dem letzten Protokolleintrag macht daraus **eine Meldung
--   je Zustand** — wer hin- und hergetragen wird, hört jede Wendung einmal,
--   nicht jede Schreibrunde.
--
--   `trip` — kein Fenster, kein Digest-Vergleich, keine Quittung: Die Zeile
--   entsteht nur, wenn wirklich jemand eine Fahrt geändert oder gelöscht
--   hat, und wird nach dem Versand gelöscht. Ein Fenster wäre hier falsch:
--   Die Fahrt kann von letzter Woche sein.
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

revoke all on function public.push_due(timestamptz) from anon, authenticated;

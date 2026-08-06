-- Abweichende Zeiten und Treffpunkt für EINEN Tag (#183, Stufe A).
--
-- Die Erinnerung (#164, #168) feuert aus `group_defaults` — eine Zeit für
-- die ganze Gruppe, jeden Tag. Die Wirklichkeit weicht ab: „heute fahren wir
-- eine halbe Stunde früher". Bisher ging das nur als Anmerkung am Plantag
-- (#127), und genau das ist seit #164 **irreführend**: Die Anmerkung sagt,
-- der Plan habe sich geändert, während das Handy weiter zur Vorgabezeit
-- weckt. Eine Anmerkung kann keine Erinnerung verschieben.
--
-- **Das revidiert die Absage aus #127** („Tages-Abweichungen bleiben
-- Anmerkungen; wer hier einen Zeitwähler je Tag ergänzt, baut das Raster
-- um"). Die war richtig, solange eine Zeit nur Text war. Seit #164
-- entscheidet sie, wann das Telefon klingelt — die Begründung ist
-- weggefallen, nicht die Regel war falsch. Dieselbe Form wie die
-- Spritpreis-Revision in v0.53.0. Für alles, was weder Zeit noch Ort ist,
-- bleibt die Anmerkung der Weg.
--
-- **Eigene Tabelle statt Spalten an `plan_availability`.** Die Abweichung
-- gilt dem TAG, nicht einer Person: Sie steht einmal da und gilt für alle,
-- die an dem Tag mitfahren. An der Verfügbarkeit hinge sie je Person und
-- müsste bei Widerspruch entscheiden, wessen Zeit gilt.
--
-- **`group_id` gehört in den Primärschlüssel.** Ohne sie wäre `plan_date`
-- über alle Gruppen eindeutig, und die zweite Gruppe liefe beim Speichern in
-- eine Unique-Verletzung auf einer Zeile, die die RLS ihr nicht einmal
-- zeigt — genau so lag `plan_overrides` bis v0.15.0.
--
-- **Stufe B baut das nicht um, sondern legt eine Ebene darüber.** Zeiten je
-- AUTO bekommen später einen eigenen Schlüssel `(group_id, plan_date,
-- driver_id)`, und die Auflösung wird dreistufig: Auto → Tag → Gruppe. Das
-- ist nicht nur billiger als ein Umbau, es ist ehrlicher: „heute fahren alle
-- früher" ist etwas anderes als „Auto 2 fährt später" — und ohne die
-- Tages-Ebene müsste man bei zwei Autos dieselbe Zeit zweimal eintragen.
create table public.plan_defaults (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  -- Dieselben drei Felder wie `group_defaults`, damit dieselbe
  -- `GroupDefaults.fromJson` beide Zeilen liest. NULL heißt hier wie dort
  -- „nicht gesetzt" — und weil feldweise aufgelöst wird, behält ein Tag, der
  -- nur den Treffpunkt ändert, die Zeiten der Gruppe.
  --
  -- Bewusst KEINE Vorgabewerte: Eine feste Vorgabe, die Verhalten trägt, ist
  -- eine stille Verhaltensänderung im Gewand einer sicheren Vorgabe (die
  -- Lehre aus der Untersuchung zu #178).
  outbound_time time,
  return_time time,
  meeting_point text
    check (char_length(btrim(meeting_point)) between 1 and 120),
  updated_at timestamptz not null default now(),
  primary key (group_id, plan_date)
);

alter table public.plan_defaults enable row level security;

create policy plan_defaults_isolated on public.plan_defaults
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

grant select, insert, update, delete on public.plan_defaults
  to anon, authenticated;
grant all on public.plan_defaults to service_role;

-- ------------------------------------------------------- push_outbox
-- Die WIRKSAME Zeit reist je Zeile mit, gerechnet vom Client — genau wie
-- `title_out`/`title_return` und aus demselben Grund: Bei mehreren Autos
-- (Stufe B) hängt sie daran, in welchem Auto die Person sitzt, und diese
-- Zuordnung kommt aus `planWeek`. `push_due()` darf sie nicht nachrechnen,
-- sonst entstünde neben `fairness.dart` die zweite Wahrheit über die
-- Fairness-Regel — der Grund, aus dem der Ausgangskorb überhaupt existiert.
--
-- Schon in Stufe A so herum, obwohl die Tageszeit für alle gleich ist: Sonst
-- müsste Stufe B die Leitung noch einmal neu legen.
alter table public.push_outbox
  add column if not exists outbound_time time,
  add column if not exists return_time time;

-- **Bewusst NICHT in `push_outbox_debounce()`.** Das ist die `title_out`-
-- Lehre aus v0.58.0: Ein Client von vor diesem Release schreibt die Spalten
-- als NULL, ein anderer Schreiber gefüllt — im Vergleich wechselte der
-- Inhalt hin und her und schöbe `due_at` endlos vor sich her, für ALLE
-- Meldungen dieser Person. Ausgelöst wird die Meldung trotzdem, denn der
-- `digest` trägt die Abweichung und steht im Vergleich.

-- ------------------------------------------------ publish_push_outbox
-- Wie bei den Kopfzeilen hält `coalesce` die Werte fest: Ein Alt-Client, der
-- die Felder nicht kennt, darf eine gesetzte Zeit nicht ausleeren. Eine
-- wirklich entfernte Abweichung macht das nicht rückgängig — dann steht in
-- `plan_defaults` keine Zeile mehr, der nächste Schreibvorgang eines
-- aktuellen Clients trägt die Gruppenzeit ein, und die ist wieder die
-- wirksame.
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
    title_roster, suppress_roster, outbound_time, return_time
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
    coalesce((entry->>'suppress_roster')::boolean, false),
    (entry->>'outbound_time')::time,
    (entry->>'return_time')::time
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
        suppress_roster = excluded.suppress_roster,
        outbound_time = coalesce(
          excluded.outbound_time, push_outbox.outbound_time),
        return_time = coalesce(
          excluded.return_time, push_outbox.return_time);
end $$;

-- ----------------------------------------------------------- push_due
-- Zwei Änderungen im Erinnerungs-Zweig, sonst unverändert; die Funktion
-- steht vollständig, weil `create or replace` keinen Teilaustausch kennt.
--
-- 1. `coalesce(box.<leg>_time, gd.<leg>_time)` — die Zeile schlägt die
--    Gruppenvorgabe. Der Griff sitzt im `values`-Paar, damit es bei EINER
--    Rechnung für beide Beine bleibt; dieselbe Stelle, an der #168 den
--    Vorlauf je Richtung ergänzt hat.
-- 2. `group_defaults` wird **left** gejoint. Vorher war es ein innerer Join:
--    Eine Gruppe ohne gepflegte Vorgaben bekam nie eine Erinnerung. Das war
--    richtig, solange die Vorgabe die einzige Quelle war — jetzt kann ein
--    einzelner Tag eine Zeit tragen, ohne dass die Gruppe je eine gesetzt
--    hat, und der innere Join verschluckte genau diesen Fall.
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
      left join public.group_defaults gd on gd.group_id = box.group_id
      cross join lateral (values
        ('departure_out'::text,
         coalesce(box.outbound_time, gd.outbound_time), box.title_out,
         prefs.reminder_lead_minutes),
        ('departure_return'::text,
         coalesce(box.return_time, gd.return_time), box.title_return,
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

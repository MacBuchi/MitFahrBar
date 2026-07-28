-- Ausgangskorb für Push-Nachrichten (Issue #132, löst #115).
--
-- **Warum überhaupt.** Der Versand hängt heute an einem GitHub-Actions-Cron
-- („alle 10 Minuten"). GitHub verwirft geplante Läufe unter Last und holt
-- sie nicht nach — gemessen am 26.07.2026: 15:14, 16:27, 17:38 UTC. Für den
-- Abend-Blick ist das belanglos, für eine Änderung um 7:05 heißt es: Die
-- Meldung kommt nach der Abfahrt, also nie.
--
-- **Warum das bisher nicht ging.** Issue #115 hat den ereignisgetriebenen
-- Weg verworfen mit „Edge Function entscheidet → bräuchte planWeek in
-- TypeScript = zweite Wahrheit". Diese Begründung wirft drei Dinge
-- zusammen: auslösen, entscheiden, senden. Trennt man sie, muss nichts nach
-- TypeScript:
--
--   Inhalt   → Dart im Client (planWeek, composeBody, composeTitle)
--   Auslöser → Trigger auf dieser Tabelle
--   Versand  → pg_cron ruft eine Function, die nur noch Buchhaltung macht
--
-- Der dritte Einwand aus #115 gilt unverändert und wird hier nie berührt:
-- **kein Repo-Token in der Datenbank.** Dieser Weg ruft GitHub nicht.
--
-- **Die Ausnahme, die das kostet.** Hier steht der vorgeschlagene Fahrer im
-- Klartext — CLAUDE.md sagt sonst „wird nie gespeichert", und diese Regel
-- ist richtig: Ein zweiter Ort, an dem steht, wer fährt, driftet irgendwann
-- von `fairness.dart` ab. Die Ausnahme trägt deshalb einen Riegel, keine
-- Absichtserklärung: **Die Tabelle hat null Policies und keine
-- Client-Rechte** — wie `push_log` und `group_admins`. Geschrieben wird
-- ausschließlich über `publish_push_outbox` unten, gelesen nur mit dem
-- service_role-Key. Was der Client nicht lesen kann, kann keine zweite
-- Wahrheit werden; `computeStats` sieht es ohnehin nie.
--
-- **Was hier NICHT steht: die Uhrzeiten.** Die liegen in
-- `notification_prefs` und werden beim Senden gelesen. Kopierte man sie
-- hierher, wirkte eine geänderte Weckzeit erst nach dem nächsten
-- Schreiben — und niemand fände den Grund.
--
-- Mindestversion wird NICHT gehoben: Es wird nichts entfernt oder
-- umbenannt, was ein veröffentlichter Client liest. Alte Clients schreiben
-- die Tabelle schlicht nicht; der stündliche Job holt das nach.

create table public.push_outbox (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  plan_date date not null,

  -- Derselbe Hash, den `push_log` führt: Daran erkennt der Versand, ob sich
  -- der Tag für diese Person geändert hat.
  digest text not null,

  -- Der fertige Text. Zeitunabhängig — `composeBody` nimmt kein `now`.
  body text not null,

  -- **Zwei Kopfzeilen, nicht eine.** Welche Art eine Meldung ist (erster
  -- Abend-Blick oder Änderung), entscheidet `push_log` — und das darf der
  -- Client nicht lesen. Also legt er beide Fassungen ab und der Versender
  -- wählt. So wandert kein einziges deutsches Wort nach TypeScript.
  title_evening text not null,
  title_change text not null,

  -- Fällig ab. NULL heißt „nichts offen": Der Versand setzt es zurück,
  -- nachdem er die Zeile abgearbeitet hat. Der Trigger unten setzt es neu,
  -- sobald sich der INHALT ändert — das ist das Entprellen.
  due_at timestamptz,

  updated_at timestamptz not null default now(),

  -- `group_id` gehört in fachliche Schlüssel: Ohne sie wäre
  -- (person_id, plan_date) über alle Gruppen eindeutig, und die zweite
  -- Gruppe liefe beim Schreiben in eine Unique-Verletzung auf einer Zeile,
  -- die sie nicht einmal sehen darf.
  primary key (group_id, person_id, plan_date)
);

-- Der Versand fragt genau danach: Was ist fällig? Der partielle Index hält
-- ihn winzig — im Normalfall ist nichts offen.
create index push_outbox_due_idx on public.push_outbox (due_at)
  where due_at is not null;

-- ------------------------------------------------------------- Entprellen
--
-- Fünf Taps im Planer sind fünf Schreibvorgänge auf dieselben Zeilen und
-- sollen EINE Meldung ergeben, nicht fünf. Jede Inhaltsänderung schiebt die
-- Fälligkeit 60 Sekunden nach hinten; wer weiterklickt, schiebt weiter.
--
-- **Das Entprellen sitzt bewusst hier und nicht in der App.** Ein Timer im
-- Client stirbt mit der App, dem Browser-Tab oder dem Bildschirm — die
-- Änderung stünde dann in `plan_availability` und niemand erführe davon.
-- Sofort schreiben und in der Datenbank warten überlebt das.
--
-- **Der `is distinct from`-Vergleich ist der Kern, nicht Sparsamkeit.** Der
-- stündliche Reparatur-Job schreibt dieselben Zeilen immer wieder. Setzte
-- der Trigger die Fälligkeit auch bei unverändertem Inhalt neu, schöbe er
-- sie stündlich vor sich her und es würde **nie** etwas gesendet.
--
-- Und wenn sich nichts geändert hat, bleibt `new.due_at` unangetastet — nur
-- so kann der Versand seinerseits mit `due_at = null` quittieren, ohne dass
-- der Trigger die Zeile sofort wieder fällig stellt.
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
end;
$$;

create trigger push_outbox_debounce_trg
  before insert or update on public.push_outbox
  for each row execute function public.push_outbox_debounce();

-- ----------------------------------------------------------- Schreibpfad
--
-- **Warum eine Funktion und nicht Tabellenrechte plus Policies.** Der
-- Wunsch war „schreiben ja, lesen nein". Direkt an der Tabelle geht das
-- nicht: Postgres verlangt für `insert ... on conflict do update` das
-- SELECT-Recht (sonst „permission denied"), und gibt man es, scheitert der
-- Upsert an der fehlenden SELECT-Policy mit „new row violates row-level
-- security policy" — die bestehende Zeile ist für den Aufrufer unsichtbar,
-- also kann der Konflikt nicht aufgelöst werden. Beides am echten Postgres
-- ausprobiert, bevor dieser Weg gewählt wurde.
--
-- Also dasselbe Muster wie `register_push_device`: SECURITY DEFINER. Der
-- Client bekommt keinerlei Rechte auf der Tabelle, und die Zusage ist
-- absolut statt knapp.
--
-- **Die Grenze der Funktion.** CLAUDE.md warnt zu Recht davor, dass
-- `authenticated` EXECUTE auf jede Funktion bekommt — eine Funktion, die
-- Zugehörigkeit verändert, wäre die Übernahme-Lücke. Diese hier kann das
-- nicht: Die `group_id` kommt aus `auth.uid()` und **nie** aus der
-- Nutzlast, und Einträge zu gruppenfremden Personen fallen im Join
-- stillschweigend heraus. Sie schreibt also ausschließlich in den eigenen
-- Ausgangskorb.
--
-- `keep_from` räumt die Zeilen vergangener Tage weg. Ohne das wüchse die
-- Tabelle mit jedem Tag, und die Zusage „beschränkt auf Personen ×
-- Planwoche" wäre falsch. Wer hier absichtlich ein spätes Datum schickt,
-- löscht nur den eigenen Korb — der stündliche Job füllt ihn wieder.
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
end;
$$;

-- --------------------------------------------------------------------- RLS
--
-- Null Policies, wie `push_log` und `group_admins`. Geschrieben wird über
-- die Funktion oben, gelesen nur mit dem service_role-Key.

alter table public.push_outbox enable row level security;

-- ------------------------------------------------------------------ Grants
--
-- **Das `revoke` ist Pflicht, nicht Gürtel-und-Hosenträger.** `schema.sql`
-- führt `alter default privileges ... grant select, insert, update, delete
-- on tables to anon, authenticated` — jede NEU angelegte Tabelle bekommt
-- damit automatisch Rechte. Ohne die Rücknahme stünde dem Client der
-- direkte Weg an der Funktion vorbei offen (die RLS bliebe zwar davor, aber
-- der Riegel soll nicht von einer später ergänzten Policy abhängen).

revoke all on public.push_outbox from anon, authenticated;
grant all on public.push_outbox to service_role;

-- Feste Vorgaben der Gruppe: Abfahrt hin, Abfahrt zurück, Treffpunkt (#139).
--
-- Der Wunsch kam aus der Gruppe: Die Zeiten stehen heute in WhatsApp und
-- niemand weiß, welche gerade gilt. Sie gehören in die App — aber NICHT in
-- `settings`: Die Tabelle ist `(group_id, key) -> value numeric` und kann
-- weder eine Uhrzeit noch einen Treffpunkt tragen. Eine Zweckentfremdung
-- (Minuten seit Mitternacht als Zahl) hätte den Treffpunkt trotzdem nicht
-- untergebracht.
--
-- **Warum die Spalten NICHT `departure_time` heißen.** Der Name ist in
-- `notification_prefs` bereits vergeben — dort ist er die persönliche
-- Deadline, ab der eine Meldung niemanden mehr erreicht. Zwei Bedeutungen
-- unter einem Namen wären genau die Falle, die man beim Lesen einer Query
-- nicht sieht. Hier heißt es deshalb `outbound_time` / `return_time`.
--
-- Keine Zeile und jede Spalte NULL bedeuten dasselbe: Das Feature ist aus,
-- Banner und Benachrichtigung sagen kein Wort davon. Deshalb gibt es weder
-- einen Seed noch einen Eintrag in `handle_new_group()` — eine Vorgabezeit
-- zu erfinden hieße, sie der Gruppe unterzuschieben.
--
-- Rein additiv: Ein veröffentlichter Client liest diese Tabelle nicht und
-- läuft unverändert weiter. `min_supported_version` bleibt, wo sie ist.
create table public.group_defaults (
  group_id uuid primary key default auth.uid()
    references public.groups(id) on delete cascade,
  -- Abfahrt der Hinfahrt und der Rückfahrt, Europe/Berlin wie alle Zeiten
  -- in diesem Projekt. NULL = nicht gepflegt.
  outbound_time time,
  return_time time,
  -- Freier Text, kein Ort im Sinne einer Koordinate: „Parkplatz Rathaus"
  -- ist genau das, was die Gruppe einander sagt. Die Obergrenze hält ihn
  -- push-tauglich — eine Benachrichtigung wird ohnehin abgeschnitten.
  meeting_point text
    check (char_length(btrim(meeting_point)) between 1 and 120),
  updated_at timestamptz not null default now()
);

alter table public.group_defaults enable row level security;

create policy group_defaults_isolated on public.group_defaults
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

grant select, insert, update, delete on public.group_defaults
  to anon, authenticated;
grant all on public.group_defaults to service_role;

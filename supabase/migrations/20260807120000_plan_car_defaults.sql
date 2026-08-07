-- Abweichende Zeiten und Treffpunkt für EIN AUTO eines Tages (#183, Stufe B).
--
-- Der ursprüngliche Anlass des Issues: An einem Tag mit zwei Autos fahren die
-- beiden nicht zwingend gleichzeitig los. Bis hierher galt eine Zeit für den
-- ganzen Tag — wer im anderen Auto saß, bekam seine Erinnerung zur fremden
-- Zeit.
--
-- **Die dritte Ebene, kein Umbau der zweiten.** Aufgelöst wird ab jetzt
-- `Auto → Tag → Gruppe`, weiterhin feldweise: Was das Auto nicht setzt, kommt
-- vom Tag, und was auch der Tag nicht setzt, von der Gruppe. Die Tages-Ebene
-- bleibt genau deshalb bestehen — „heute fahren alle früher" ist eine andere
-- Aussage als „Auto 2 fährt später", und ohne sie müsste man bei zwei Autos
-- dieselbe Zeit zweimal eintragen.
--
-- **Der Schlüssel ist der von `plan_overrides`**, und das ist keine Analogie,
-- sondern dieselbe Sache: Ein Auto EXISTIERT in der Datenbank nur als „diese
-- Person fährt an diesem Tag". Die Autos selbst sind berechnet (`planWeek`)
-- und werden nie gespeichert — ein Auto-Datensatz wäre die zweite Wahrheit
-- über den Tag.
--
-- **Daraus folgt die Regel, die im Client sitzt: Wer für sein Auto eine Zeit
-- setzt, schreibt den Fahrer fest** (`plan_overrides`). Ohne das hinge morgen
-- eine 6:45 an einer Zeile, deren `driver_id` an dem Tag gar nicht mehr fährt
-- — der Fahrer-Vorschlag kippt, sobald jemand seine Verfügbarkeit ändert.
-- Erzwungen wird das hier bewusst NICHT: Ein Fremdschlüssel auf
-- `plan_overrides` machte aus zwei Schreibvorgängen einen, der in der
-- falschen Reihenfolge scheitert, und eine verwaiste Zeile ist harmlos —
-- sie fällt beim Auflösen einfach heraus (siehe unten).
--
-- **Verwaiste Zeilen sind zulässig und werden nicht aufgeräumt.** Wechselt
-- der Fahrer, bleibt die alte Zeile stehen und wirkt nicht mehr; kommt er
-- zurück, gilt sie wieder. Ein Aufräum-Trigger müsste dafür den Plan
-- nachrechnen — also `planWeek` in SQL, genau das, was der Ausgangskorb
-- vermeidet.
create table public.plan_car_defaults (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  driver_id uuid not null references public.persons(id) on delete cascade,
  -- Dieselben drei Felder wie `group_defaults` und `plan_defaults`, damit
  -- dieselbe `GroupDefaults.fromJson` alle drei Zeilen liest.
  outbound_time time,
  return_time time,
  meeting_point text
    check (char_length(btrim(meeting_point)) between 1 and 120),
  updated_at timestamptz not null default now(),
  -- `group_id` gehört in den Schlüssel: Ohne ihn wäre er über alle Gruppen
  -- eindeutig, und die zweite Gruppe liefe beim Speichern in eine
  -- Unique-Verletzung auf einer Zeile, die die RLS ihr nicht einmal zeigt.
  primary key (group_id, plan_date, driver_id)
);

alter table public.plan_car_defaults enable row level security;

create policy plan_car_defaults_isolated on public.plan_car_defaults
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

grant select, insert, update, delete on public.plan_car_defaults
  to anon, authenticated;
grant all on public.plan_car_defaults to service_role;

-- **Kein Eingriff an `push_due()` und `publish_push_outbox`.** Die wirksame
-- Zeit steht seit Stufe A je Person in `push_outbox.outbound_time` /
-- `.return_time`, gerechnet vom Client. Genau dafür wurde sie dort abgelegt:
-- Welche Zeit für jemanden gilt, hängt daran, in welchem Auto er sitzt — und
-- diese Zuordnung kommt aus `planWeek`. Zwei Personen desselben Tages tragen
-- ab hier verschiedene Zeiten in ihren Zeilen, und der Versand merkt davon
-- nichts. Er entscheidet weiterhin nur, OB und WANN.

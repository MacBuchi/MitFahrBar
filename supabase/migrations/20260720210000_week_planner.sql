-- Wochenplaner: Wer kann wann, und wer fährt dann.
--
-- Bewusst NICHT gespeichert wird der vorgeschlagene Fahrer. Er ist eine
-- berechnete Kennzahl wie Punkte oder Quote (KONZEPT.md §4) und würde sonst
-- veralten, sobald jemand eine Fahrt einträgt. Gespeichert wird nur, was
-- Menschen entschieden haben: Verfügbarkeit und ein etwaiges Übersteuern.
--
-- Ebenfalls kein „bestätigt"-Kennzeichen: Die Bestätigung erzeugt eine echte
-- Fahrt in `trips`, deren Existenz am jeweiligen Tag ist also die Bestätigung.
-- Damit kann Geplantes die Punkte nie verfälschen — `computeStats` sieht
-- ausschließlich gefahrene Fahrten.

-- Wer kann an welchem Tag mitfahren. Eine Zeile je Person und Tag.
create table public.plan_availability (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (plan_date, person_id)
);

-- Nur vorhanden, wenn der Vorschlag von Hand übersteuert wurde. Fehlt die
-- Zeile, gilt der berechnete Vorschlag.
create table public.plan_overrides (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  driver_id uuid not null references public.persons(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (plan_date)
);

create index plan_availability_group_idx on public.plan_availability (group_id);
create index plan_overrides_group_idx on public.plan_overrides (group_id);

alter table public.plan_availability enable row level security;
alter table public.plan_overrides enable row level security;

-- Dieselbe Mandanten-Isolation wie alle Datentabellen. Ohne sie lecken
-- Planungsdaten zwischen Gruppen.
create policy plan_availability_isolated on public.plan_availability
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

create policy plan_overrides_isolated on public.plan_overrides
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

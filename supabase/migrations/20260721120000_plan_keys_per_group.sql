-- Planungs-Schlüssel pro Gruppe statt global.
--
-- `plan_overrides` hatte `primary key (plan_date)` — also **global** eindeutig
-- über alle Gruppen hinweg. Sobald zwei Gruppen am selben Tag einen Fahrer von
-- Hand setzen, läuft die zweite in eine Unique-Verletzung: Ihr `upsert` trifft
-- auf eine Zeile, die die RLS ihr gar nicht zeigt, und Postgres bricht mit
-- einem Constraint-Fehler ab, statt still nichts zu tun. Kein Datenleck, aber
-- ein harter Fehlschlag — und er tritt erst auf, wenn die zweite Gruppe
-- anfängt zu planen.
--
-- `plan_availability` konnte praktisch nicht kollidieren, weil `person_id` als
-- UUID gruppenübergreifend eindeutig ist. Der Schlüssel wird trotzdem
-- mitgezogen: Die Tabelle daneben ist die Vorlage, von der die nächste
-- Planungstabelle abgeschrieben wird, und dann stimmt die Annahme nicht mehr.

alter table public.plan_overrides drop constraint plan_overrides_pkey;
alter table public.plan_overrides add primary key (group_id, plan_date);

alter table public.plan_availability drop constraint plan_availability_pkey;
alter table public.plan_availability
  add primary key (group_id, plan_date, person_id);

-- 1-way in der Wochenplanung.
--
-- Bisher war Verfügbarkeit ja/nein: Eine Zeile hieß „kann an dem Tag". Wer nur
-- eine Richtung mitfährt, konnte das nicht ausdrücken — im Fahrten-Editor
-- dagegen gibt es 1-way seit jeher.
--
-- Bewusst ein Boolean und kein Status-Enum wie in `trip_participations`: Der
-- Fahrer wird im Plan nie gespeichert (er ist eine berechnete Kennzahl), also
-- bleibt als Unterscheidung nur „ganz" gegen „nur eine Richtung". Ein Enum mit
-- einem `driver`-Wert, den hier niemand setzen darf, wäre eine Einladung.
--
-- Bestandszeilen sind volle Mitfahrten — genau das, was sie bisher bedeutet
-- haben. Deshalb `default false` und kein Backfill.

alter table public.plan_availability
  add column one_way boolean not null default false;

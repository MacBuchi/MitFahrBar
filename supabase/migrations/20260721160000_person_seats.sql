-- Sitzplätze je Person (Issue #28).
--
-- Gespeichert wird die Zahl **inklusive Fahrer** — die aus dem Fahrzeugschein,
-- die man von seinem Auto kennt. Mitfahrer-Plätze zu speichern hieße, bei jeder
-- Eingabe eins abzuziehen.
--
-- Vorgabe 5 (Fahrer + 4): der normale PKW. Damit wirkt die Sitzplatz-Prüfung
-- vom ersten Tag an, ohne dass jemand etwas pflegen muss — `not null` mit
-- Default füllt auch alle Bestandszeilen. Wer einen Van oder einen Zweisitzer
-- fährt, korrigiert es einmal.
--
-- Mindestens 2: Ein Einsitzer kann keine Fahrgemeinschaft fahren, und eine 1
-- wäre fast immer ein Vertipper.

alter table public.persons
  add column seats int not null default 5 check (seats > 1);

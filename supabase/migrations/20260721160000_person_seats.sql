-- Sitzplätze je Person (Issue #28).
--
-- Gespeichert wird die Zahl **inklusive Fahrer** — die aus dem Fahrzeugschein,
-- die man von seinem Auto kennt. Mitfahrer-Plätze zu speichern hieße, bei jeder
-- Eingabe eins abzuziehen.
--
-- Mindestens 2: Ein Einsitzer kann keine Fahrgemeinschaft fahren, und eine 1
-- wäre fast immer ein Vertipper. `null` bleibt erlaubt und heißt „unbekannt";
-- daraus darf nie eine Warnung oder ein Ausschluss folgen.

alter table public.persons add column seats int check (seats > 1);

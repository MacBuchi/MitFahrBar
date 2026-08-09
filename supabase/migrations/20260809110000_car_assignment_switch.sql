-- Gruppen-Schalter für die Auto-Zuordnung (#213).
--
-- Neue Gruppen starten OHNE Zuordnung: feste Zeiten für alle, keine Abfahrt
-- je Auto, keine Zusage, keine Auto-Wahl. Deshalb steht hier **kein** Eintrag
-- in `handle_new_group()` — fehlt die Zeile, liest der Client die Vorgabe
-- `false`. Dieselbe Bauart wie `charging_price_per_kwh` und
-- `e10_price_per_liter`, die dort ebenfalls fehlen.
--
-- Bestehende Gruppen benutzen das Feature seit v0.64.0. Ihnen die Zuordnung
-- durch eine neue Vorgabe wegzunehmen wäre keine Vorgabe, sondern ein
-- Entzug — sie bekommen deshalb ausdrücklich eine 1. Abschalten bleibt ein
-- Tap im Parameter-Screen.
--
-- **Die Mindestversion wird NICHT gehoben**, und das ist geprüft, nicht
-- vermutet: Es fällt nichts weg und nichts wird umbenannt, und
-- `saveSettings` ist ein Upsert je Schlüssel — ein Client von vor v0.71.0
-- kennt `car_assignment_enabled` nicht, schreibt ihn also auch nicht und
-- lässt die Zeile stehen. Er zeigt die Zuordnung weiterhin an; wo der
-- Schalter auf 1 steht (also überall, wo sie heute in Gebrauch ist), ist das
-- genau richtig.
insert into public.settings (group_id, key, value)
select id, 'car_assignment_enabled', 1
from public.groups
on conflict (group_id, key) do nothing;

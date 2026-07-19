-- Mehrere Fahrten pro Tag zulassen: an manchen Tagen fährt die Gruppe
-- in zwei (oder mehr) getrennten Autos – jede Fahrt hat einen eigenen
-- Fahrer und eigene Mitfahrer. Die ursprüngliche UNIQUE-Annahme
-- (eine Fahrt pro Kalendertag) war falsch.
alter table public.trips drop constraint if exists trips_trip_date_key;

-- trip_date bleibt häufigstes Sortier-/Filterkriterium -> normaler Index.
create index if not exists trips_trip_date_idx on public.trips (trip_date);

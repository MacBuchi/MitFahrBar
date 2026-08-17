-- Merker für Wochen, die das Archiv nie füllen wird (#256-Vorbedingung:
-- der Nachfüll-Lauf bekommt einen nächtlichen Zeitplan).
--
-- Bisher lief `fuel-history.yml` nur von Hand, und der dokumentierte Grund
-- war genau diese Tabelle: Ohne Merker zöge ein nächtlicher Lauf für eine
-- Woche, die das Archiv nicht hat (Archivlücke, keine Stationen im
-- Umkreis, zu dünne Daten), jede Nacht dieselben sieben 30-MB-Dateien —
-- die Lücke bliebe ja bestehen. Der Anlass, den Zeitplan jetzt zu bauen:
-- Nachgetragene oder umdatierte Fahrten in vormals fahrfreien Wochen und
-- der CSV-Import einer Gruppe erzeugen neue Lücken, und niemand stößt den
-- Lauf danach an — real passiert mit 2023-W48 (DaciaRacing), die die
-- Ersparnis-Kurve zweieinhalb Jahre lang gestrichelt hat.
--
-- Der Aufbau in Kürze:
-- - Geschrieben und gelesen wird die Tabelle NUR vom Nachfüll-Job
--   (service_role). Null Policies, `revoke all` — ein Client hat hier
--   nichts zu suchen: Lesen bräuchte er nicht (Lücken zeigt die
--   Preisreihe selbst), und Schreiben könnte den Lauf für fremde Wochen
--   stilllegen. Dasselbe Muster wie `price_sample` und `push_outbox`.
-- - `region_key` hält fest, für WELCHES Gebiet die Entscheidung fiel.
--   Verschiebt eine Gruppe ihr Gebiet, passt der Schlüssel nicht mehr und
--   die Woche wird automatisch neu versucht — die Marke bleibt stehen und
--   wirkt nicht (verwaiste-Zeilen-Regel, wie bei plan_car_defaults).
-- - `reason` ist der Wortlaut aus dem Job-Log („alle sieben Tagesdateien
--   fehlen", „keine Stationen im Umkreis", …) — nur Diagnose, nie Namen.
-- - Aufgeräumt wird von Hand (SQL), falls das Archiv eine Lücke doch noch
--   füllt; das ist bewusst kein Selbstbedienungsweg.
create table public.price_week_skip (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  iso_year int not null check (iso_year between 2014 and 2100),
  iso_week int not null check (iso_week between 1 and 53),
  region_key text not null,
  reason text not null,
  decided_at timestamptz not null default now(),
  primary key (group_id, iso_year, iso_week)
);

alter table public.price_week_skip enable row level security;

-- `alter default privileges` gibt jeder neuen Tabelle den Sammel-Grant —
-- die Rücknahme muss deshalb hier stehen, nicht nur in schema.sql.
revoke all on public.price_week_skip from anon, authenticated;
grant all on public.price_week_skip to service_role;

-- Die Mindestversion bleibt unberührt: Es kommt nur eine Tabelle hinzu,
-- die kein Client kennt oder je liest.

-- schema.sql – Gesamtbild der Datenbank (Doku/Frischinstallation).
-- Eingespielt wird NICHT diese Datei, sondern supabase/migrations/
-- (Supabase-GitHub-Integration, automatisch bei Push auf main).
-- Bei Schema-Änderungen: neue Migrationsdatei anlegen UND dieses
-- Gesamtbild nachziehen.
--
-- Sicherheitsmodell: Multi-Tenant. Eine Gruppe = ein Login (auth user),
-- group_id = auth.uid(). Jede Gruppe sieht nur ihre eigenen Daten (RLS),
-- und nur wenn sie 'active' ist. Der Publishable-Key im Client ist
-- öffentlich; die Zugriffskontrolle liegt vollständig hier.
--
-- Gruppen entstehen in der Verwalter-Konsole (Edge Function `request-group`)
-- und sind sofort aktiv und verknüpft. 'pending' ist nur noch der inerte
-- Ruhezustand für Fremd-Signups gegen die Gruppen-Domain: Ein direktes
-- `auth.signUp` ist nie abstellbar (die Verwalter-Registrierung braucht
-- offenes Signup), der Trigger unten macht daraus eine Zeile, die nichts
-- lesen und nichts schreiben kann. Eine FREIGABE gibt es seit #108 nicht
-- mehr — mit ihr fielen `groups.is_admin`, `is_group_admin()` und jede
-- Update-Policy auf `groups`.
--
-- Je Gruppe steht EIN Verwalter-Konto (echte E-Mail, account_type = 'admin'
-- in den Metadata); ein Konto trägt bis zu 5 Gruppen. Es sieht keine
-- Gruppendaten (anderer uid) und kann über SECURITY-DEFINER-Funktionen
-- ausschließlich das Gruppenpasswort neu setzen, die Verknüpfung lösen und
-- die Gruppe löschen. Passwort-Reset läuft über Supabases Mailfluss (Code,
-- kein Link — siehe #102) — ohne Betreiber.

-- crypt()/gen_salt() für die Passwortprüfungen der Konsolen-Funktionen.
create extension if not exists pgcrypto;
-- Der Minutentakt, der den Ausgangskorb abholt (#132), und der HTTP-Ruf,
-- mit dem er die Edge Function weckt. **Beide ausdrücklich anlegen** — der
-- lokale CLI-Stack bringt pg_net vorinstalliert mit, Produktion nicht.
-- Genau diese Differenz hat am 29.07.2026 den Versand still stehen lassen:
-- `flush_due_push()` scheiterte jede Minute, sichtbar nur in
-- `cron.job_run_details`, und kein Test auf dem Teststack konnte es zeigen.
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------- Tabellen

create table public.groups (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text unique not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'rejected', 'archived')),
  created_at timestamptz not null default now(),
  -- Wann die Gruppe ihren Verwalter verloren hat. Eine aktive Gruppe ohne
  -- Verknüpfung ist nur als Übergabefenster vorgesehen; der Zeitstempel
  -- macht sie von einer echten Waise unterscheidbar. 'archived' ist der
  -- vorgesehene Ruhezustand — `my_group_active()` prüft auf 'active', eine
  -- archivierte Gruppe ist damit über alle Policies hinweg still,
  -- verlustfrei und umkehrbar.
  released_at timestamptz
);

create table public.persons (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  name text not null,
  active boolean not null default true,
  vehicle text,
  energy_type text check (energy_type in ('electric', 'diesel', 'petrol')),
  consumption_per_100km numeric check (consumption_per_100km > 0),
  -- Sitzplätze inklusive Fahrer (Fahrzeugschein-Zahl). Vorgabe 5 = normaler
  -- PKW, damit die Prüfung ohne Pflegeaufwand greift.
  seats int not null default 5 check (seats > 1),
  created_at timestamptz not null default now()
);

-- Ein Name gehört in EINER Gruppe genau einer Person (Issue #109) — über
-- Gruppengrenzen hinweg dagegen frei, zwei Fahrgemeinschaften dürfen beide
-- eine „Anna" haben. Bis v0.41.0 stand hier ein globaler `unique (name)` aus
-- der Zeit vor der Mandantentrennung; er sperrte die zweite Gruppe aus und
-- verriet ihr dabei, dass der Name woanders existiert.
--
-- Index statt Constraint, weil normalisiert verglichen wird: `lower(btrim())`
-- ist genau die Abbildung, mit der `core/csv_import.dart` Namen auf Personen
-- zuordnet. Inaktive zählen mit — wer zurückkommt, wird reaktiviert, nicht
-- neu angelegt (eine zweite Zeile spaltete seine Punkte-Historie).
create unique index persons_group_name_key
  on public.persons (group_id, lower(btrim(name)));

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  -- Pro Tag sind mehrere Fahrten möglich (z. B. zwei getrennte Autos),
  -- deshalb bewusst NICHT unique.
  trip_date date not null,
  note text,
  created_at timestamptz not null default now()
);

create table public.trip_participations (
  trip_id uuid not null references public.trips(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  status text not null check (status in ('driver', 'passenger', 'one_way')),
  primary key (trip_id, person_id)
);

-- Höchstens ein Fahrer pro Fahrt.
create unique index trip_one_driver_uidx
  on public.trip_participations (trip_id)
  where (status = 'driver');

create index trips_trip_date_idx on public.trips (trip_date);
create index persons_group_idx on public.persons (group_id);
create index trips_group_idx on public.trips (group_id);
create index trip_participations_group_idx on public.trip_participations (group_id);

-- settings pro Gruppe.
create table public.settings (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  key text not null,
  value numeric not null,
  primary key (group_id, key)
);

-- Feste Vorgaben der Gruppe (#139): Abfahrt hin, Abfahrt zurück, Treffpunkt.
-- Eine eigene Tabelle, weil `settings` nur Zahlen trägt — eine Uhrzeit als
-- Minutenzahl wäre unterzubringen, ein Treffpunkt nicht.
--
-- Die Zeitspalten heißen bewusst NICHT `departure_time`: Der Name ist in
-- `notification_prefs` als persönliche Fenster-Deadline vergeben, und zwei
-- Bedeutungen unter einem Namen sieht man beim Lesen einer Query nicht.
--
-- Keine Zeile = alles NULL = Feature aus. Kein Seed, kein Eintrag in
-- `handle_new_group()`: Eine erfundene Vorgabezeit wäre der Gruppe
-- untergeschoben.
create table public.group_defaults (
  group_id uuid primary key default auth.uid()
    references public.groups(id) on delete cascade,
  outbound_time time,
  return_time time,
  meeting_point text
    check (char_length(btrim(meeting_point)) between 1 and 120),
  updated_at timestamptz not null default now()
);

-- In-App-Feedback; der Feedback-Bot macht daraus GitHub-Issues.
create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  type text not null default 'feature' check (type in ('feature', 'bug')),
  message text not null check (char_length(message) between 3 and 2000),
  app_version text,
  platform text,
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create index feedback_unprocessed_idx on public.feedback (created_at)
  where processed_at is null;

-- Fehlerberichte (#136): gefangene Fehler, automatisch aus der App. Bewusst
-- KEIN Crash-Dienst (kein Sentry, Issue #18) — eigene Tabelle im eigenen
-- Projekt, gelesen nur mit dem service_role-Key: Der Feedback-Bot macht
-- daraus ein Issue je ISO-Woche und löscht nach 90 Tagen.
create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable, anders als sonst: Die wertvollsten Fehler passieren VOR dem
  -- Login. Die Kaskade hält das Löschversprechen von admin_delete_group.
  group_id uuid default auth.uid()
    references public.groups(id) on delete cascade,
  -- Aufrufstelle, z. B. der Provider- oder Handler-Name.
  context text not null check (char_length(context) between 1 and 100),
  error_type text not null check (char_length(error_type) <= 100),
  -- In der App gekürzt; die Limits halten die Tabelle schlank.
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);

create index error_reports_created_idx
  on public.error_reports (created_at desc);

-- Ein Verwalter-Konto trägt auth.uid() ohne groups-Zeile — der Default
-- liefe in den Fremdschlüssel. Der Trigger löst unter der RLS des
-- Aufrufers auf: Wer "seine" Gruppe nicht sieht (Verwalter, anon,
-- pending), meldet gruppenlos statt gar nicht.
create or replace function public.error_reports_resolve_group()
returns trigger language plpgsql set search_path = public as $$
begin
  select id into new.group_id from public.groups where id = new.group_id;
  return new;
end $$;

create trigger error_reports_resolve_group
  before insert on public.error_reports
  for each row execute function public.error_reports_resolve_group();

-- Gruppenübergreifende Konfiguration. **Einzige Tabelle ohne `group_id`** —
-- sie enthält keine Gruppendaten, alle Gruppen müssen denselben Wert sehen,
-- und Clients dürfen sie nur lesen (Issue #19). Der Wert wird ausschließlich
-- von Migrationen gesetzt.
create table public.app_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

-- Wochenplaner. Gespeichert wird nur, was Menschen entschieden haben:
-- Verfügbarkeit und ein etwaiges Übersteuern des Fahrer-Vorschlags. Der
-- Vorschlag selbst ist berechnet (KONZEPT.md §4) und steht deshalb nirgends;
-- ein „bestätigt"-Kennzeichen gibt es ebenfalls nicht — die Bestätigung
-- erzeugt eine Zeile in `trips`, deren Existenz am Tag ist die Bestätigung.
create table public.plan_availability (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  -- Nur eine Richtung. Kein Status-Enum: Der Fahrer wird im Plan nie
  -- gespeichert, also bleibt nur „ganz" gegen „eine Richtung".
  one_way boolean not null default false,
  created_at timestamptz not null default now(),
  -- `group_id` gehört in den Schlüssel: Ohne ihn wäre er global eindeutig
  -- und zwei Gruppen kämen sich am selben Tag ins Gehege.
  primary key (group_id, plan_date, person_id)
);

create table public.plan_overrides (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  driver_id uuid not null references public.persons(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- Eine Zeile je Fahrer: Das Übersteuern eines Tages ist die MENGE seiner
  -- Zeilen (Issue #62, mehrere Autos pro Tag). `group_id` gehört in den
  -- Schlüssel, sonst kämen sich zwei Gruppen am selben Tag ins Gehege.
  primary key (group_id, plan_date, driver_id)
);

-- Anmerkungen zu einem Plantag (Issue #127, deckt #120 mit ab): „komme erst
-- um 9". **Kein Chat** — keine Threads, kein Gelesen-Status, keine Antworten;
-- KONZEPT.md §1 („Kommunikation bleibt in WhatsApp") gilt weiter. Der Name
-- sagt genau das: eine Notiz am Plantag, neben den beiden Tabellen darüber.
--
-- Der Schlüssel ist eine generierte UUID, kein fachlicher — mehrere
-- Anmerkungen je Tag und Person sind der Normalfall. Vorlage ist deshalb
-- `feedback`, nicht `plan_availability`. `btrim` im Längen-Check, weil
-- `between 1 and 500` allein 500 Leerzeichen durchließe.
--
-- `person_id` ist der Verfasser und kein Identitätsnachweis: Jeder kann für
-- jeden schreiben, wie im Planer jeder für jeden einträgt.
create table public.plan_notes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

create index plan_availability_group_idx on public.plan_availability (group_id);
create index plan_overrides_group_idx on public.plan_overrides (group_id);
-- Gelesen wird immer eine Spanne von Tagen (die Planwoche) einer Gruppe.
create index plan_notes_day_idx on public.plan_notes (group_id, plan_date);

-- Push-Benachrichtigungen zum Wochenplaner (Issue #101). Drei Aufgaben:
-- push_devices = wohin, notification_prefs = wann, push_log = was schon raus
-- ist. Der vorgeschlagene Fahrer steht auch hier NICHT — push_log hält nur
-- einen Hash des Tageszustands, damit der Versand-Job Änderungen erkennt.

-- Ein Gerät = eine Zeile. Primärschlüssel ist der Token, NICHT
-- (group_id, token): FCM-Token sind global eindeutig, eine Kollision
-- zwischen Gruppen ist konstruktiv unmöglich — und ein Gerät gehört zu genau
-- EINER Gruppe, meldet es sich in einer anderen an, muss die alte Zeile
-- weichen. Die „group_id in den Schlüssel"-Regel zielt auf fachliche
-- Schlüssel, die ohne sie über alle Gruppen eindeutig wären; ein Token ist
-- das nicht.
create table public.push_devices (
  token text primary key,
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  -- Wer an diesem Gerät benachrichtigt wird. KEIN Login: Jeder kann jeden
  -- wählen, wie im Planer jeder für jeden einträgt. Zustelladresse, kein
  -- Identitätsnachweis. NULL = noch niemandem zugeordnet, bekommt nichts.
  person_id uuid references public.persons(id) on delete cascade,
  platform text not null check (platform in ('android', 'web')),
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

-- Uhrzeiten je PERSON (nicht je Gerät), alle in Europe/Berlin.
-- **Keine Zeile = keine Benachrichtigungen**: Die Zeile entsteht beim
-- Einschalten im Screen. So gibt es genau eine Wahrheit darüber, wer etwas
-- bekommt, und der Versand-Job braucht keine Vorgabewerte zu kennen.
create table public.notification_prefs (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  evening_enabled boolean not null default true,
  evening_time time not null default '21:00',
  -- Ende des Änderungs-Fensters: Danach nützt keine Nachricht mehr, und ein
  -- nachgeholter Lauf darf niemanden nachts wecken.
  departure_time time not null default '07:30',
  changes_enabled boolean not null default true,
  -- Erinnerung kurz vor der Abfahrt (#164), hin und zurück. **Opt-in**:
  -- Anders als der Abend-Blick meldet sie sich an einem Tag, an dem gar
  -- nichts passiert ist. Ein Vorlauf für beide Richtungen — zwei Regler für
  -- dieselbe Frage wären einer zu viel. Die Vorgabe 15 muss mit
  -- `defaultReminderLead` in lib/models/notification_prefs.dart übereinstimmen.
  reminders_enabled boolean not null default false,
  -- Getrennt je Richtung (#168): Hin- und Rückweg starten nicht am selben
  -- Ort. Der alte Name ist die Hinfahrt und bleibt, damit ein
  -- veröffentlichter Client weiterläuft.
  reminder_lead_minutes integer not null default 15
    check (reminder_lead_minutes between 0 and 120),
  reminder_lead_return_minutes integer not null default 15
    check (reminder_lead_return_minutes between 0 and 120),
  -- Sofort-Meldungen (#163): Ein- und Ausgetragen-Werden durch andere, und
  -- geänderte oder gelöschte Fahrten. Bewusst NICHT an den Abend-Blick
  -- gekoppelt — sie feuern außerhalb jedes Fensters, ihn zu koppeln hieße,
  -- sie genau dann abzuschalten, wenn sie gebraucht werden.
  instant_enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (group_id, person_id)
);

-- Versand-Gedächtnis. Kein `default auth.uid()`: Hier schreibt nur der
-- Versand-Job mit dem service_role-Key, und der hat keine auth.uid().
create table public.push_log (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  plan_date date not null,
  -- 'trip' fehlt hier bewusst: Trip-Zeilen werden nach dem Versand
  -- GELÖSCHT statt quittiert — ein Protokolleintrag wäre die zweite
  -- Buchführung über dasselbe.
  kind text not null constraint push_log_kind_check
    check (kind in ('evening', 'change', 'departure_out',
                    'departure_return', 'roster')),
  digest text not null,
  sent_at timestamptz not null default now(),
  primary key (group_id, person_id, plan_date, kind)
);

-- Ausgangskorb (#132): was gesagt WÜRDE. Der Client rechnet den Text mit dem
-- echten `planWeek`/`composeBody` aus und legt ihn hier ab; ein Trigger macht
-- die Zeile 60 Sekunden später fällig, pg_cron holt sie ab. So bleibt die
-- Fairness-Regel in Dart, obwohl der Versand ereignisgetrieben ist.
--
-- Hier steht der vorgeschlagene Fahrer im Klartext — die einzige Ausnahme von
-- „wird nie gespeichert", und sie hängt an einem Riegel: **null Policies und
-- keine Client-Rechte**, wie bei `push_log`. Geschrieben wird ausschließlich
-- über `publish_push_outbox`, gelesen nur mit dem service_role-Key. Was der
-- Client nicht lesen kann, kann keine zweite Wahrheit werden.
--
-- Die Uhrzeiten stehen NICHT hier, sondern in `notification_prefs` — sonst
-- wirkte eine geänderte Weckzeit erst nach dem nächsten Schreiben.
create table public.push_outbox (
  group_id uuid not null
    references public.groups(id) on delete cascade,
  person_id uuid not null references public.persons(id) on delete cascade,
  plan_date date not null,
  -- Die Art steht seit #163 IM Schlüssel: Zum selben Tag können eine
  -- Plan-Zeile und eine Fahrt-Meldung gleichzeitig offen sein, und sie sagen
  -- Verschiedenes. Der Purge im Schreibweg fasst deshalb ausdrücklich nur
  -- 'plan' an — ohne den Filter stürbe jede Meldung über eine ältere Fahrt,
  -- bevor sie eine Minute später verschickt würde.
  kind text not null default 'plan' check (kind in ('plan', 'trip')),
  digest text not null,
  body text not null,
  -- Zwei Kopfzeilen: Welche Art die Meldung ist, entscheidet `push_log`, und
  -- das darf der Client nicht lesen. Er legt beide ab, der Versand wählt —
  -- so wandert kein deutsches Wort nach TypeScript.
  title_evening text not null,
  title_change text not null,
  -- Die Kopfzeilen der Abfahrts-Erinnerungen (#164). NULL heißt „für diese
  -- Richtung gibt es keine Gruppenzeit" — ohne Zeit keine Erinnerung, ohne
  -- Erinnerung keine Kopfzeile. Der Entprell-Trigger vergleicht sie bewusst
  -- NICHT (Begründung an der Funktion unten).
  title_out text,
  title_return text,
  -- Die Kopfzeile der Eintrag-Meldung (#163). Wer RAUS ist, liest statt
  -- ihrer `title_change` („Ausgetragen") — ein zweites Wort für dieselbe
  -- Sache wäre eine zweite Sprache.
  title_roster text,
  -- NULL = nichts offen. Der Versand quittiert damit.
  due_at timestamptz,
  -- Eine ZWEITE Fälligkeit, und die braucht es: Der Abend-Blick quittiert
  -- mit `due_at = null`, und eine noch offene Sofort-Meldung wäre damit
  -- stillschweigend erledigt.
  roster_due_at timestamptz,
  -- Selbst-Unterdrückung: Wer selbst tippt, braucht keine Meldung darüber.
  -- **Best effort, keine Zugriffskontrolle** — sie hängt an der
  -- Geräte-Zuordnung „Ich bin" (#121), und die ist ausdrücklich kein Login.
  -- Der stündliche Job schreibt `false` und überstimmt im Reparaturfall.
  suppress_roster boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (group_id, person_id, plan_date, kind)
);

create index push_devices_group_idx on public.push_devices (group_id);
create index push_devices_person_idx
  on public.push_devices (group_id, person_id);
create index push_log_date_idx on public.push_log (plan_date);
create index push_outbox_due_idx on public.push_outbox (due_at)
  where due_at is not null;
create index push_outbox_roster_idx on public.push_outbox (roster_due_at)
  where roster_due_at is not null;

-- Verknüpfung Verwalter-Konto ↔ Gruppe. Ein Konto trägt bis zu 5 Gruppen
-- (Deckel im Trigger unten), deshalb der zusammengesetzte Schlüssel.
-- `group_id unique` bleibt: höchstens EIN Verwalter je Gruppe (#55). Eine
-- bestehende Gruppe übernimmt man weiter mit dem Gruppen-Login
-- (claim_admin_group); neue entstehen bereits verknüpft.
create table public.group_admins (
  user_id uuid references auth.users(id) on delete cascade,
  group_id uuid unique not null references public.groups(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, group_id)
);

-- Preisarchiv: EIN Wert je Gruppe und ISO-Woche für Diesel, E5, E10,
-- Hausstrom und Tankstellenstrom. Die drei Kraftstoffe werden gemessen, die
-- beiden Strom-Reihen sind vorerst Konstanten aus `settings`.
--
-- Die Kosten-/Ersparnisrechnung rührt das nicht an: `fairness.dart` und
-- `computeStats` sehen diese Tabellen nie. Solange nicht für JEDE gefahrene
-- Woche ein Wert vorliegt, wäre eine Umstellung eine Rechnung mit Löchern.

-- Wo diese Gruppe tankt. Kein Eintrag = Feature aus. `region_key` fasst nahe
-- beieinander liegende Gruppen zusammen (zwei Nachkommastellen ≈ 1 km): Zwei
-- Gruppen derselben Gegend teilen sich eine Abfrage statt zwei.
create table public.price_area (
  group_id uuid primary key default auth.uid()
    references public.groups(id) on delete cascade,
  label text not null check (char_length(label) between 1 and 200),
  lat numeric(9, 6) not null check (lat between -90 and 90),
  lng numeric(9, 6) not null check (lng between -180 and 180),
  -- Tankerkönig deckelt die Umkreissuche bei 25 km.
  radius_km numeric(4, 1) not null default 20
    check (radius_km between 1 and 25),
  region_key text generated always as (
    round(lat, 2)::text || ',' || round(lng, 2)::text || ',' ||
    round(radius_km, 1)::text
  ) stored,
  updated_at timestamptz not null default now()
);

create index price_area_region_idx on public.price_area (region_key);

-- Rohschicht: was die API zu einem Zeitpunkt gemeldet hat. Bewusst OHNE
-- group_id — hier stehen keine Gruppendaten, sondern öffentliche Marktdaten,
-- die zufällig für eine Gruppe abgefragt wurden. Der Riegel ist derselbe wie
-- bei push_outbox: null Policies, revoke all. Kein Client liest sie je.
--
-- Die Werte sind Zwischenprodukt, kein Archiv: Sobald eine Woche verdichtet
-- ist, werden sie weggeräumt. Dieselben sieben Tage wären zugleich die
-- Grundlage eines späteren „Tankdaumens" (aktueller Preis gegen das
-- Perzentil der Region) — deshalb hängt die Tabelle an der Region.
create table public.price_sample (
  region_key text not null,
  captured_at timestamptz not null,
  station_id uuid not null,
  -- Nullable je Sorte: Nicht jede Station führt alle drei. Ein fehlender
  -- Wert darf nicht als 0 in ein Perzentil laufen.
  e5 numeric(5, 3) check (e5 > 0),
  e10 numeric(5, 3) check (e10 > 0),
  diesel numeric(5, 3) check (diesel > 0),
  primary key (region_key, captured_at, station_id)
);

create index price_sample_sweep_idx
  on public.price_sample (region_key, captured_at);

-- Die Wochenschicht — der Vertrag, in dem später gerechnet wird. Der Wert
-- ist das 10. Perzentil aller Stichproben der Woche, nicht das Minimum: Man
-- tankt nie genau beim billigsten Anbieter zum billigsten Zeitpunkt. Es ist
-- zudem die einzige Definition, die für gemessene UND später importierte
-- Daten dieselbe Frage beantwortet — sonst entstünde an der Naht zwischen
-- Import und Messung eine Stufe, die keine Preisänderung ist.
--
-- Hausstrom und Tankstellenstrom stehen hier NICHT: Konstanten werden nicht
-- gespeichert, sonst müsste eine Parameteränderung die Historie umschreiben
-- und eine abgelegte Konstante sähe später aus wie eine Messung. Der
-- Lesepfad (core/price_series.dart) füllt und markiert sie.
create table public.price_week (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  iso_year int not null check (iso_year between 2014 and 2100),
  iso_week int not null check (iso_week between 1 and 53),
  series text not null check (series in ('e5', 'e10', 'diesel')),
  value numeric(6, 3) not null check (value > 0),
  -- Bei wenigen Stationen ist ein 10-%-Perzentil faktisch „der günstigste
  -- von dreien"; das soll die Oberfläche sagen können.
  sample_count int not null check (sample_count > 0),
  station_count int not null check (station_count > 0),
  -- `mixed` entsteht genau einmal: an der Naht zwischen importierter
  -- Vergangenheit und gemessener Gegenwart.
  origin text not null check (origin in ('measured', 'imported', 'mixed')),
  computed_at timestamptz not null default now(),
  primary key (group_id, iso_year, iso_week, series)
);

-- --------------------------------------------------------------- Funktionen

-- SECURITY-DEFINER-Helfer: liest groups ohne RLS-Rekursion. Hieran hängt
-- jede Datentabellen-Policy — 'archived' zu setzen macht eine Gruppe damit
-- über alle Policies hinweg still, verlustfrei und umkehrbar.
create or replace function public.my_group_active()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select status = 'active' from public.groups where id = auth.uid()), false);
$$;

-- Jeder neue Auth-User wird zu einer 'pending'-Gruppe (+ Default-Settings).
-- Der Trigger traut den Metadata eines Signups nur den Gruppennamen zu:
-- Ein gebasteltes `auth.signUp` gegen die Gruppen-Domain darf keine aktive
-- oder fremd verknüpfte Gruppe erzeugen. Aktiv und verknüpft wird eine
-- Gruppe ausschließlich in der Edge Function `request-group`.
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  -- Konsolen-Registrierungen erzeugen keine Geister-„pending"-Gruppe.
  if new.raw_user_meta_data->>'account_type' = 'admin' then
    return new;
  end if;
  insert into public.groups (id, name, handle, status)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'group_name', ''), new_handle),
          new_handle, 'pending');
  insert into public.settings (group_id, key, value) values
    (new.id, 'commute_km', 30),
    (new.id, 'one_way_factor', 0.5),
    (new.id, 'electricity_price_per_kwh', 0.35),
    (new.id, 'diesel_price_per_liter', 1.70),
    (new.id, 'petrol_price_per_liter', 1.78),
    (new.id, 'points_weight', 1.0);
  return new;
end $$;

create trigger on_auth_user_created_group
  after insert on auth.users
  for each row execute function public.handle_new_group();

-- ------------------------------------------------- Verwalter-Konsole (#55)

-- Deckel: 5 Gruppen je Verwalter-Konto (#106), serverseitig. Ein Deckel nur
-- im UI ist kein Deckel.
--
-- Bewusst ein TRIGGER und keine aufrufbare Funktion: `alter default
-- privileges` unten gibt `authenticated` execute auf jede Funktion. Eine
-- Funktion `adopt_group(gruppe, konto)` wäre damit die Übernahme-Lücke —
-- jedes angemeldete Konto könnte sich an jede unverknüpfte Gruppe hängen,
-- ohne das Gruppenpasswort zu kennen. Der Vorschuss-Lock verhindert, dass
-- zwei gleichzeitige Anlagen beide den Stand vor der anderen zählen.
create or replace function public.enforce_group_admin_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(hashtext('group_admins:' || new.user_id::text));
  if (select count(*) from public.group_admins
       where user_id = new.user_id) >= 5 then
    raise exception 'group limit reached';
  end if;
  return new;
end $$;

create trigger group_admins_cap
  before insert on public.group_admins
  for each row execute function public.enforce_group_admin_cap();

-- Verliert eine Gruppe ihren Verwalter, wird der Zeitpunkt vermerkt — beim
-- absichtlichen Lösen UND bei der Kaskade eines gelöschten Verwalter-Kontos
-- (der zweite Fall wäre sonst eine stille Waise). Bewusst nur der
-- Zeitstempel, kein Statuswechsel: Eine Übergabe darf die Gruppe nicht
-- aussperren, die Mitfahrer fahren ja weiter.
create or replace function public.mark_group_released()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.groups set released_at = now() where id = old.group_id;
  return old;
end $$;

create trigger group_admins_released
  after delete on public.group_admins
  for each row execute function public.mark_group_released();

-- Entprellen des Ausgangskorbs (#132): Fünf Taps im Planer sind fünf Upserts
-- auf dieselben Zeilen und sollen EINE Meldung ergeben. Jede Inhaltsänderung
-- schiebt die Fälligkeit 60 Sekunden nach hinten.
--
-- Der `is distinct from`-Vergleich ist der Kern: Der stündliche Reparatur-Job
-- schreibt dieselben Zeilen immer wieder. Setzte der Trigger die Fälligkeit
-- auch bei unverändertem Inhalt neu, schöbe er sie stündlich vor sich her und
-- es würde **nie** etwas gesendet. Und weil `new.due_at` bei unverändertem
-- Inhalt unangetastet bleibt, kann der Versand mit `due_at = null`
-- quittieren, ohne dass die Zeile sofort wieder fällig wird.
--
-- **`title_out` und `title_return` (#164) stehen bewusst NICHT im Vergleich.**
-- Ein Client von vor v0.58.0 schreibt sie als NULL, der stündliche Job
-- gefüllt. Im Vergleich wechselte der Inhalt zwischen beiden Schreibern hin
-- und her, jede Änderung schöbe `due_at` 60 Sekunden nach hinten — die Zeile
-- wäre nie fällig, und zwar für ALLE Meldungen dieser Person. Der Preis: Eine
-- geänderte Abfahrtszeit allein löst keinen Versand aus. Sie soll es auch
-- nicht (#139).
-- **Der Roster-Detektor unten feuert nur bei UPDATE** (#163). Beim ersten
-- Füllen des Korbs entstehen Zeilen für JEDE Person — eine neue Gruppe, ein
-- Wochenwechsel, ein Gerät, das den Korb erstmals schreibt; ohne die
-- Bedingung weckte das die halbe Gruppe mit „Eingetragen" für Tage, an denen
-- sich nichts geändert hat. Der Riegel ist doppelt, und die zweite Hälfte ist
-- unsichtbar: Beim INSERT ist `old` nicht belegt, `old.digest <> 'fix'` ergibt
-- NULL und die ganze Bedingung wird NULL. Wer sie „null-sicher" macht, nimmt
-- genau diese Hälfte weg.
--
-- `raus` <-> `fix` ist ausgeschlossen: Wird eine Fahrt eingetragen, wechselt
-- der Digest derer, die nicht mitfuhren, auf `raus` — diesen Fall deckt die
-- Fahrt-Meldung ab, sonst käme zusätzlich ein „Ausgetragen".
create or replace function public.push_outbox_debounce()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  if tg_op = 'INSERT'
    or new.digest is distinct from old.digest
    or new.body is distinct from old.body
    or new.title_evening is distinct from old.title_evening
    or new.title_change is distinct from old.title_change
  then
    new.due_at := now() + interval '60 seconds';
  end if;

  if tg_op = 'UPDATE'
    and new.kind = 'plan'
    and (old.digest = 'raus') is distinct from (new.digest = 'raus')
    and old.digest <> 'fix'
    and new.digest <> 'fix'
    and not new.suppress_roster
  then
    new.roster_due_at := now() + interval '60 seconds';
  end if;

  return new;
end $$;

create trigger push_outbox_debounce_trg
  before insert or update on public.push_outbox
  for each row execute function public.push_outbox_debounce();

-- Der einzige Schreibweg in den Ausgangskorb (#132). SECURITY DEFINER wie
-- `register_push_device`, und aus einem harten Grund: „schreiben ja, lesen
-- nein" ist an der Tabelle nicht zu haben — Postgres verlangt für
-- `on conflict do update` das SELECT-Recht, und mit Recht, aber ohne
-- SELECT-Policy scheitert der Upsert daran, dass die bestehende Zeile für
-- den Aufrufer unsichtbar ist.
--
-- Die Funktion kann keine Zugehörigkeit verändern: Die `group_id` kommt aus
-- `auth.uid()` und nie aus der Nutzlast, und Einträge zu gruppenfremden
-- Personen fallen im Join heraus. `keep_from` räumt vergangene Tage weg,
-- damit die Tabelle auf Personen × Planwoche beschränkt bleibt.
create or replace function public.publish_push_outbox(
  entries jsonb,
  keep_from date
)
returns void language plpgsql security definer set search_path = public as $$
declare
  gid uuid := auth.uid();
begin
  if gid is null or not public.my_group_active() then
    raise exception 'not allowed' using errcode = '42501';
  end if;

  delete from public.push_outbox
    where group_id = gid and kind = 'plan' and plan_date < keep_from;

  insert into public.push_outbox (
    group_id, person_id, plan_date, kind, digest, body,
    title_evening, title_change, title_out, title_return,
    title_roster, suppress_roster
  )
  select
    gid,
    person.id,
    (entry->>'plan_date')::date,
    coalesce(entry->>'kind', 'plan'),
    entry->>'digest',
    entry->>'body',
    entry->>'title_evening',
    entry->>'title_change',
    entry->>'title_out',
    entry->>'title_return',
    entry->>'title_roster',
    coalesce((entry->>'suppress_roster')::boolean, false)
  from jsonb_array_elements(coalesce(entries, '[]'::jsonb)) as entry
  join public.persons person
    on person.id = (entry->>'person_id')::uuid
   and person.group_id = gid
  on conflict (group_id, person_id, plan_date, kind) do update
    set digest = excluded.digest,
        body = excluded.body,
        title_evening = excluded.title_evening,
        title_change = excluded.title_change,
        title_out = coalesce(excluded.title_out, push_outbox.title_out),
        title_return = coalesce(
          excluded.title_return, push_outbox.title_return),
        title_roster = coalesce(
          excluded.title_roster, push_outbox.title_roster),
        suppress_roster = excluded.suppress_roster;
end $$;

-- Übernimmt eine BESTEHENDE Gruppe: für Gruppen von vor #106 und für die
-- Übergabe an eine Nachfolgerin. Beweis ist das Gruppen-Login (Handle +
-- Gruppenpasswort) — und nur, solange die Gruppe noch keinen Admin hat.
-- Grenze des geteilten Logins: Das erste Postfach gewinnt.
create or replace function public.claim_admin_group(
  claim_handle text,
  group_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  caller record;
  target record;
  stored text;
begin
  select id, raw_user_meta_data into caller
    from auth.users where id = auth.uid();
  if caller.id is null
     or caller.raw_user_meta_data->>'account_type' is distinct from 'admin' then
    raise exception 'not an admin account';
  end if;

  select g.id into target from public.groups g
    where g.handle = claim_handle and g.status = 'active';
  if target.id is null then
    raise exception 'wrong group credentials';
  end if;

  select encrypted_password into stored from auth.users where id = target.id;
  if stored is null or stored <> crypt(group_password, stored) then
    raise exception 'wrong group credentials';
  end if;

  if exists (select 1 from public.group_admins where group_id = target.id) then
    raise exception 'group already claimed';
  end if;

  insert into public.group_admins (user_id, group_id)
  values (auth.uid(), target.id);

  update public.groups set released_at = null where id = target.id;
end $$;

-- Alle verknüpften Gruppen fürs Konsolen-UI (leer, wenn keine). Die frühere
-- Einzelform könnte bei mehreren Gruppen nur eine beliebige davon zeigen.
create or replace function public.my_admin_groups()
returns table (group_id uuid, handle text, name text)
language sql stable security definer set search_path = public as $$
  select g.id, g.handle, g.name
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid()
   order by g.created_at;
$$;

-- Setzt das Passwort des GRUPPEN-Kontos neu — die Rettungsleine, wenn das
-- geteilte Passwort verloren ging oder jemand alle ausgesperrt hat.
-- Alle drei Aktionen nennen IHRE Gruppe. Die Eigentumsprüfung
-- `user_id = auth.uid() and group_id = target_group` ist der eigentliche
-- Inhalt der Signaturen — ohne sie träfe ein Verwalter die Gruppe eines
-- anderen.
create or replace function public.admin_reset_group_password(
  target_group uuid,
  new_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not exists (select 1 from public.group_admins
                  where user_id = auth.uid() and group_id = target_group) then
    raise exception 'not linked';
  end if;
  if length(coalesce(new_password, '')) < 8 then
    raise exception 'password too short';
  end if;
  update auth.users
     set encrypted_password = crypt(new_password, gen_salt('bf'))
   where id = target_group;
end $$;

-- Löst die Verknüpfung (Issue #73) — die Übergabe. Sudo-Muster: eigenes
-- Admin-Passwort erneut. Danach kann ein anderes Konto über claim_admin_group
-- neu einrasten; Gruppendaten und Verwalter-Konto bleiben unberührt, der
-- Trigger vermerkt den Zeitpunkt in `released_at`.
-- Bewusste Grenze: Wer Postfach UND Passwort verliert, kommt an seine
-- Gruppen nicht mehr heran — Selbstbedienung daran vorbei wäre die
-- Übernahme-Lücke, die das Einrasten gerade verhindert (jedes Mitglied kennt
-- das Gruppenpasswort). Vorgesehen dafür ist eine Übernahme mit
-- Widerspruchsfrist, nicht ein zweiter Schlüssel hier.
create or replace function public.admin_release_group(
  target_group uuid,
  admin_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  own text;
begin
  if not exists (select 1 from public.group_admins
                  where user_id = auth.uid() and group_id = target_group) then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;

  delete from public.group_admins
   where user_id = auth.uid() and group_id = target_group;
end $$;

-- Löscht DIE GRUPPE. Sudo-Muster: eigenes Admin-Passwort erneut plus
-- getippter Handle. Der Gruppen-Auth-User zieht über die Kaskade
-- (groups.id -> auth.users, Datentabellen -> groups) alles mit.
--
-- Das Verwalter-Konto überlebt: Bei bis zu 5 Gruppen wäre ein Selbst-Löschen
-- Datenverlust an den übrigen. Deshalb wird hier genau EINE Zeile in
-- `auth.users` entfernt — die der Zielgruppe. `test/schema_test.dart` zählt
-- das nach.
create or replace function public.admin_delete_group(
  target_group uuid,
  admin_password text,
  handle_confirmation text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target_handle text;
  own text;
begin
  select g.handle into target_handle
    from public.group_admins ga
    join public.groups g on g.id = ga.group_id
   where ga.user_id = auth.uid() and ga.group_id = target_group;
  if target_handle is null then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;
  if handle_confirmation is distinct from target_handle then
    raise exception 'handle mismatch';
  end if;

  delete from auth.users where id = target_group;
end $$;

-- ------------------------------------------------ Push-Registrierung (#101)

-- Registrierung über SECURITY DEFINER statt direktem Upsert: Wechselt ein
-- Gerät die Gruppe, liegt seine alte Zeile unter fremder group_id — die RLS
-- zeigt sie nicht, der Upsert liefe in eine Unique-Verletzung auf einer
-- unsichtbaren Zeile (dieselbe Falle wie seinerzeit bei plan_overrides).
create or replace function public.register_push_device(
  device_token text,
  person uuid,
  device_platform text
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null or not public.my_group_active() then
    raise exception 'not allowed';
  end if;
  if coalesce(device_token, '') = '' then
    raise exception 'missing token';
  end if;
  if device_platform not in ('android', 'web') then
    raise exception 'unknown platform';
  end if;
  if person is not null and not exists (
    select 1 from public.persons p
     where p.id = person and p.group_id = me
  ) then
    raise exception 'unknown person';
  end if;

  delete from public.push_devices where token = device_token;
  insert into public.push_devices (token, group_id, person_id, platform)
  values (device_token, me, person, device_platform);
end $$;

create or replace function public.unregister_push_device(
  device_token text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.push_devices
   where token = device_token and group_id = auth.uid();
end $$;

-- Was ist fällig? (#132) Dieselben Regeln wie `dueMessages` in
-- `lib/core/push_digest.dart`, nur ohne den Teil, der den Text macht — der
-- steht schon im Korb. Das Fenster reicht von der Abendzeit des Vortages bis
-- zur Abfahrtszeit; **`at time zone 'Europe/Berlin'` ist Pflicht**, weil
-- Postgres in UTC läuft und ein Fehler hier zweimal im Jahr eine Stunde
-- danebenläge, ohne dass ein Test es sähe.
--
-- `'raus'` ist `removedDigest` aus push_digest.dart. Der Wert steht hier ein
-- zweites Mal; `test/schema_test.dart` hält beide zusammen.
create or replace function public.push_due(at timestamptz default now())
returns table (
  token text,
  group_id uuid,
  person_id uuid,
  plan_date date,
  kind text,
  digest text,
  title text,
  body text
)
language sql security definer set search_path = public as $$
  with plan_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      box.body,
      box.title_evening,
      box.title_change,
      case
        when evening.digest is null then
          case
            when prefs.evening_enabled
              and box.digest <> 'raus'
              and box.digest <> 'fix'
            then 'evening'
          end
        when prefs.changes_enabled
          and box.digest <> 'fix'
          and box.digest is distinct from coalesce(change.digest, evening.digest)
          and box.due_at is not null
          and box.due_at <= at
          and (change.sent_at is null
               or at - change.sent_at >= interval '30 minutes')
        then 'change'
      end as kind
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      left join public.push_log evening
        on evening.group_id = box.group_id
       and evening.person_id = box.person_id
       and evening.plan_date = box.plan_date
       and evening.kind = 'evening'
      left join public.push_log change
        on change.group_id = box.group_id
       and change.person_id = box.person_id
       and change.plan_date = box.plan_date
       and change.kind = 'change'
    where box.kind = 'plan'
      and at >= ((box.plan_date - 1)::timestamp + prefs.evening_time)
                  at time zone 'Europe/Berlin'
      and at <  (box.plan_date::timestamp + prefs.departure_time)
                  at time zone 'Europe/Berlin'
  ),
  reminder_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      leg.kind,
      leg.title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      join public.group_defaults gd on gd.group_id = box.group_id
      cross join lateral (values
        ('departure_out'::text, gd.outbound_time, box.title_out,
         prefs.reminder_lead_minutes),
        ('departure_return'::text, gd.return_time, box.title_return,
         prefs.reminder_lead_return_minutes)
      ) as leg(kind, leg_time, title, lead_minutes)
      left join public.push_log sent
        on sent.group_id = box.group_id
       and sent.person_id = box.person_id
       and sent.plan_date = box.plan_date
       and sent.kind = leg.kind
    where box.kind = 'plan'
      and prefs.reminders_enabled
      and box.digest <> 'raus'
      and leg.leg_time is not null
      and leg.title is not null
      and sent.person_id is null
      and box.plan_date = (at at time zone 'Europe/Berlin')::date
      and at >= ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
                 - make_interval(mins => leg.lead_minutes)
      and at <  ((box.plan_date::timestamp + leg.leg_time)
                   at time zone 'Europe/Berlin')
  ),
  roster_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      'roster'::text as kind,
      -- Wer raus ist, liest „Ausgetragen" — dieselbe Kopfzeile, die auch
      -- die Änderungs-Meldung dafür benutzt. Ein zweites Wort für dieselbe
      -- Sache wäre eine zweite Sprache.
      case when box.digest = 'raus' then box.title_change else box.title_roster
        end as title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      left join public.push_log sent
        on sent.group_id = box.group_id
       and sent.person_id = box.person_id
       and sent.plan_date = box.plan_date
       and sent.kind = 'roster'
    where box.kind = 'plan'
      and prefs.instant_enabled
      and box.roster_due_at is not null
      and box.roster_due_at <= at
      and box.digest is distinct from sent.digest
      and box.title_roster is not null
      and box.plan_date >= (at at time zone 'Europe/Berlin')::date
      and (box.plan_date > (at at time zone 'Europe/Berlin')::date
           or at < (box.plan_date::timestamp + prefs.departure_time)
                     at time zone 'Europe/Berlin')
  ),
  trip_ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      'trip'::text as kind,
      box.title_change as title,
      box.body
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
    where box.kind = 'trip'
      and prefs.instant_enabled
      and box.due_at is not null
      and box.due_at <= at
  ),
  ready as (
    select
      group_id, person_id, plan_date, digest, kind,
      case when kind = 'evening' then title_evening else title_change end
        as title,
      body
    from plan_ready
    where kind is not null
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from reminder_ready
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from roster_ready
    union all
    select group_id, person_id, plan_date, digest, kind, title, body
    from trip_ready
  )
  select
    device.token,
    ready.group_id,
    ready.person_id,
    ready.plan_date,
    ready.kind,
    ready.digest,
    ready.title,
    ready.body
  from ready
    join public.push_devices device
      on device.group_id = ready.group_id
     and device.person_id = ready.person_id;
$$;

revoke all on function public.push_due(timestamptz) from anon, authenticated;

-- ---------------------------------------------------------------- Abholer
--
-- Der Minutentakt weckt nur; entschieden und gesendet wird in der Function
-- `flush-push`. Der Umweg ist Absicht: FCM braucht ein Dienstkonto, und das
-- gehört zu den übrigen Server-Geheimnissen, nicht in die Datenbank.
--
-- **Zugangsdaten aus dem Vault, nicht aus einer Tabelle.** Eine Spalte mit
-- dem Job-Geheimnis stünde für jeden mit service_role-Zugang im Klartext und
-- landete in jedem Datenbank-Abzug. Fehlen die Einträge, tut die Funktion
-- **nichts** — so bleibt der lokale Teststack und jede Frischinstallation
-- lauffähig, ohne dass jemand Geheimnisse anlegen muss.
--
-- Einmalig einzurichten (Betreiber, nicht im Repo):
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
create or replace function public.flush_due_push()
returns void language plpgsql security definer
set search_path = public, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';
  if base_url is null or job_secret is null or service_key is null then
    return;
  end if;

  -- Nichts zu tun heißt: nicht anklopfen. Spart im Normalfall 1440 Aufrufe
  -- am Tag, und die Abfrage ist ein Index-Treffer.
  if not exists (select 1 from public.push_due()) then
    return;
  end if;

  perform net.http_post(
    url := base_url || '/flush-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', job_secret,
      'apikey', service_key
    ) || case
      when service_key like 'eyJ%'
        then jsonb_build_object('Authorization', 'Bearer ' || service_key)
      else '{}'::jsonb
    end,
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function public.flush_due_push() from anon, authenticated;

select cron.schedule(
  'flush-due-push',
  '* * * * *',
  $$select public.flush_due_push()$$
);

-- Abtast-Takt fürs Preisarchiv: dreimal am Tag eine Umkreisabfrage je
-- Region. Feste Uhrzeiten statt „alle acht Stunden", weil der Tagesgang der
-- Spritpreise ausgeprägt ist (früh teuer, abends billig) und weil nur feste
-- Zeitpunkte sich später aus dem Preiswechsel-Archiv rekonstruieren lassen.
-- pg_cron rechnet in UTC: 05:05/11:05/17:05 sind im Sommer 07:05/13:05/19:05,
-- im Winter eine Stunde früher — die Verschiebung ist in Kauf genommen. Die
-- Minute 5 statt 0, weil die Nutzungsbedingungen um versetzte Zeiten bitten.
--
-- `push_functions_url` und `push_service_key` werden mitbenutzt: Beides ist
-- Infrastruktur und kein Push-Detail. Das Job-Geheimnis ist dagegen eigen —
-- ein Leck im Push-Weg soll nicht auch diesen öffnen.
--   select vault.create_secret('<FUEL_JOB_SECRET>', 'fuel_job_secret');
create or replace function public.sample_fuel_prices()
returns void language plpgsql security definer
set search_path = public, vault, net as $$
declare
  base_url text;
  job_secret text;
  service_key text;
begin
  select decrypted_secret into base_url
    from vault.decrypted_secrets where name = 'push_functions_url';
  select decrypted_secret into job_secret
    from vault.decrypted_secrets where name = 'fuel_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';
  if base_url is null or job_secret is null or service_key is null then
    return;
  end if;

  -- Keine Region hinterlegt heißt: nicht anklopfen. Solange keine Gruppe das
  -- Feature eingerichtet hat, wird kein fremder Dienst befragt.
  if not exists (select 1 from public.price_area) then
    return;
  end if;

  perform net.http_post(
    url := base_url || '/fuel-sample',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-fuel-secret', job_secret,
      'apikey', service_key
    ) || case
      when service_key like 'eyJ%'
        then jsonb_build_object('Authorization', 'Bearer ' || service_key)
      else '{}'::jsonb
    end,
    body := '{}'::jsonb
  );
end;
$$;

revoke all on function public.sample_fuel_prices() from anon, authenticated;

select cron.schedule(
  'sample-fuel-prices',
  '5 5,11,17 * * *',
  $$select public.sample_fuel_prices()$$
);

-- Verdichtung: aus den Stichproben wird je Gruppe, ISO-Woche und Sorte EIN
-- Wert — das 10. Perzentil, nicht das Minimum (man tankt nie genau beim
-- billigsten Anbieter zum billigsten Zeitpunkt).
--
-- Hier in SQL statt in Dart, weil `percentile_cont` zeichengenau dieselbe
-- Definition ist wie `percentile` in lib/core/price_series.dart und der
-- spätere Import der Vergangenheit ohnehin in Python läuft: EINE
-- Implementierung ist nicht zu haben, EINE Definition schon.
-- test/schema_test.dart hält den Anteil mit `defaultPercentile` zusammen.
--
-- Gerechnet wird in deutscher Zeit: Eine Messung Sonntag 23:30 UTC ist in
-- Deutschland schon Montag und gehört in die Folgewoche.
create or replace function public.rollup_fuel_weeks()
returns void language plpgsql security definer
set search_path = public as $$
declare
  -- Ab Montag der VORwoche: die laufende wächst noch, die abgeschlossene
  -- wird einmal mehr gerechnet, damit eine späte Sonntagsstichprobe zählt.
  from_local timestamp := date_trunc(
    'week', (now() at time zone 'Europe/Berlin') - interval '7 days'
  );
begin
  with unpivoted as (
    -- Eine Zeile je (Stichprobe, Sorte); fehlende Sorten fallen raus statt
    -- als 0 mitzuzählen — eine Null zöge das Perzentil gegen den Boden.
    select s.region_key,
           extract(
             isoyear from s.captured_at at time zone 'Europe/Berlin'
           )::int as iso_year,
           extract(
             week from s.captured_at at time zone 'Europe/Berlin'
           )::int as iso_week,
           s.station_id,
           x.series,
           x.price
      from public.price_sample s
      cross join lateral (values
        ('e5', s.e5), ('e10', s.e10), ('diesel', s.diesel)
      ) as x(series, price)
     where s.captured_at >= (from_local at time zone 'Europe/Berlin')
       and x.price is not null
  )
  insert into public.price_week as w (
    group_id, iso_year, iso_week, series,
    value, sample_count, station_count, origin
  )
  -- Der Join über `region_key` ist der Grund, warum die Rohschicht an der
  -- Region hängt: Zwei Gruppen derselben Gegend bekommen eigene
  -- Wochenzeilen aus EINER Abfrage.
  select a.group_id, u.iso_year, u.iso_week, u.series,
         (percentile_cont(0.10) within group (order by u.price))::numeric,
         count(*),
         count(distinct u.station_id),
         'measured'
    from unpivoted u
    join public.price_area a on a.region_key = u.region_key
   group by a.group_id, u.iso_year, u.iso_week, u.series
  on conflict (group_id, iso_year, iso_week, series) do update
     set value = excluded.value,
         sample_count = excluded.sample_count,
         station_count = excluded.station_count,
         -- Eine importierte Woche mit zusätzlichen Messungen wird `mixed`
         -- statt still `measured` — an der Naht soll das Diagramm den
         -- Übergang zeigen können, statt ihn zu verschweigen.
         origin = case
           when w.origin in ('imported', 'mixed') then 'mixed'
           else excluded.origin
         end,
         computed_at = now();

  -- Rohwerte sind Zwischenprodukt, kein Archiv. 21 Tage Abstand: verdichtet
  -- wird höchstens die Vorwoche, gelöscht erst drei Wochen zurück, damit ein
  -- ausgefallener Lauf nichts kostet. Die letzten 7 Tage stehen damit immer
  -- bereit — sie wären die Grundlage eines späteren „Tankdaumens".
  delete from public.price_sample
   where captured_at < now() - interval '21 days';
end;
$$;

revoke all on function public.rollup_fuel_weeks() from anon, authenticated;

-- Zwanzig Minuten nach dem Abtasten: pg_net schickt asynchron, die
-- Stichproben treffen erst Sekunden später ein.
select cron.schedule(
  'rollup-fuel-weeks',
  '25 5,11,17 * * *',
  $$select public.rollup_fuel_weeks()$$
);

-- --------------------------------------------------------------------- RLS

alter table public.groups              enable row level security;
alter table public.persons             enable row level security;
alter table public.trips               enable row level security;
alter table public.trip_participations enable row level security;
alter table public.settings            enable row level security;
alter table public.group_defaults      enable row level security;
alter table public.plan_availability   enable row level security;
alter table public.plan_overrides      enable row level security;
alter table public.plan_notes          enable row level security;
alter table public.push_devices        enable row level security;
alter table public.notification_prefs  enable row level security;
-- Bewusst KEINE Policies auf group_admins: Kein Client liest oder schreibt
-- die Verknüpfung direkt, alles läuft über die Konsolen-Funktionen.
alter table public.group_admins        enable row level security;
-- Ebenso ohne Policy: Das Versand-Gedächtnis gehört allein dem Job
-- (service_role umgeht RLS). Eine Client-Policy gäbe jedem Mitglied die
-- Möglichkeit, Nachrichten zu unterdrücken oder erneut auszulösen.
alter table public.push_log            enable row level security;

-- Nur die eigene Gruppe lesen. Insert macht der Trigger.
--
-- Bewusst KEINE Update-Policy (#108): Eine Gruppe ändert sich ausschließlich
-- über die SECURITY-DEFINER-Funktionen der Konsole und künftig über den
-- vorgesehenen Aufräum-Job mit Service-Role-Key. Könnte ein Client `status`
-- schreiben, könnte er sich selbst freischalten — genau das machte die alte
-- Freigabe-Policy nötig und mit ihr die Sonderrolle einer Admin-Gruppe.
create policy groups_select on public.groups for select to authenticated
  using (id = auth.uid());

create policy persons_isolated on public.persons for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy trips_isolated on public.trips for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy participations_isolated on public.trip_participations for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy settings_isolated on public.settings for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy group_defaults_isolated on public.group_defaults
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy plan_availability_isolated on public.plan_availability
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy plan_overrides_isolated on public.plan_overrides
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy plan_notes_isolated on public.plan_notes
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy push_devices_isolated on public.push_devices
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());
create policy notification_prefs_isolated on public.notification_prefs
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

-- Ausgangskorb (#132): null Policies, wie `push_log` und `group_admins`.
-- „Schreiben ja, lesen nein" ist an der Tabelle selbst nicht zu haben —
-- `insert ... on conflict do update` verlangt das SELECT-Recht, und mit
-- Recht, aber ohne SELECT-Policy scheitert es an „new row violates row-level
-- security policy". Deshalb läuft der Schreibpfad über
-- `publish_push_outbox` (SECURITY DEFINER, siehe oben).
alter table public.push_outbox enable row level security;

-- Konfiguration: nur lesen. Bewusst keine Schreib-Policy — sonst könnte ein
-- Client die Mindestversion hochsetzen und damit alle aussperren. `anon`
-- darf lesen, damit der Sperr-Schirm schon vor dem Login greift.
alter table public.app_config enable row level security;
create policy app_config_read on public.app_config
  for select to anon, authenticated using (true);

-- Feedback: eigenes einreichen und nachlesen, mehr nicht.
create policy feedback_insert on public.feedback for insert to authenticated
  with check (group_id = auth.uid() and public.my_group_active());
create policy feedback_select_own on public.feedback for select to authenticated
  using (group_id = auth.uid());

-- Fehlerberichte: schreiben darf jeder, auch anon — sonst fehlen genau die
-- Fehler aus dem Login. Eine fremde group_id lässt sich nicht unterschieben:
-- entweder null oder die eigene. Lesen darf über die API NIEMAND — bewusst
-- keine select-Policy; die Rücknahme des Sammel-Grants steht unten.
alter table public.error_reports enable row level security;
create policy error_reports_insert on public.error_reports for insert
  with check (group_id is null or group_id = auth.uid());

-- Preisarchiv: Der Bereich gehört der Gruppe. Die Wochenwerte darf sie nur
-- LESEN — geschrieben wird allein vom Verdichtungslauf mit service_role,
-- denn eine gefälschte Preiskurve fiele niemandem auf. Die Rohschicht sieht
-- niemand: null Policies wie bei push_outbox, Rücknahme des Sammel-Grants
-- steht unten.
alter table public.price_area   enable row level security;
alter table public.price_sample enable row level security;
alter table public.price_week   enable row level security;

create policy price_area_isolated on public.price_area
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

create policy price_week_read on public.price_week
  for select to authenticated
  using (group_id = auth.uid() and public.my_group_active());

-- ------------------------------------------------------------------ Grants
-- Explizit statt Plattform-Default: Neuere Stacks (lokaler CLI-Stack,
-- Postgres-17-Image) sind „secure by default" und geben Client-Rollen ohne
-- Grant weder DML noch EXECUTE — die App fände auf einem frischen Stack
-- keine Tabelle vor. Die Zugriffskontrolle bleibt vollständig bei den
-- RLS-Policies oben; service_role braucht die Rechte für den Feedback-Bot
-- und die E2E-Tests.

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete
  on all tables in schema public to anon, authenticated;
grant all on all tables in schema public to service_role;

-- Und sofort wieder weg für den Ausgangskorb (#132). Der Sammel-Grant oben
-- gibt Rechte auf JEDE Tabelle — ohne diese Rücknahme stünde dem Client der
-- direkte Weg an `publish_push_outbox` vorbei offen, und der Riegel hinge
-- allein daran, dass niemand später eine Policy ergänzt.
-- `test/e2e/rls_e2e_test.dart` beweist am echten Postgres, dass ein Client
-- hier weder lesen noch schreiben kann.
revoke all on public.push_outbox from anon, authenticated;
-- Fehlerberichte (#136): nur einwerfen, nie zurücklesen. Der Sammel-Grant
-- gäbe select/update/delete — zurück auf insert; ein Fehlertext kann in
-- Ausnahmefällen Serverdetails tragen, und die Berichte aller Gruppen
-- gehen keinen Client etwas an.
revoke all on public.error_reports from anon, authenticated;
grant insert on public.error_reports to anon, authenticated;
-- Preisarchiv: Die Rohschicht bekommt gar nichts — sie ist Zwischenprodukt
-- und trägt keine Gruppendaten, es gibt für einen Client nichts darin zu
-- suchen. Die Wochenwerte nur lesen: Schreiben ist Sache des
-- Verdichtungslaufs, sonst könnte ein Gerät die Historie fälschen.
revoke all on public.price_sample from anon, authenticated;
revoke all on public.price_week from anon, authenticated;
grant select on public.price_week to authenticated;
grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;
grant execute on all functions in schema public
  to anon, authenticated, service_role;
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

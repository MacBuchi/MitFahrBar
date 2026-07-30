-- Fehlerberichte (#136): gefangene Fehler landen in einer eigenen Tabelle.
--
-- MitFahrBar wird an den Stores vorbei ausgeliefert — keine Play-Vitals,
-- keine Crash-Statistik. Ein Fehler zeigt heute eine SnackBar und
-- verschwindet; wer abstürzt, meldet nicht, der deinstalliert. Die Senke
-- ist bewusst KEIN Crash-Dienst (kein Sentry, Issue #18): eigene Tabelle
-- im eigenen Projekt, kein Dritter, keine Dependency. Muster von PilzBuddy
-- (patch_009 dort), angepasst an die Mandantentrennung dieses Projekts.
--
-- Gelesen wird ausschließlich mit dem service_role-Key: Der Feedback-Bot
-- macht daraus ein Issue je ISO-Woche und löscht Berichte nach 90 Tagen.

create table public.error_reports (
  id uuid primary key default gen_random_uuid(),
  -- Nullable, anders als sonst: Die wertvollsten Fehler passieren VOR dem
  -- Login. Der Default füllt für angemeldete Gruppen; der Trigger unten
  -- nimmt Kennungen zurück, die keine Gruppe sind (Verwalter-Konten).
  -- Die Kaskade hält das Löschversprechen: admin_delete_group nimmt die
  -- Berichte der Gruppe mit.
  group_id uuid default auth.uid()
    references public.groups(id) on delete cascade,
  -- Aufrufstelle, z. B. der Provider- oder Handler-Name.
  context text not null check (char_length(context) between 1 and 100),
  -- Laufzeittyp des Fehlers, z. B. "PostgrestException".
  error_type text not null check (char_length(error_type) <= 100),
  -- In der App gekürzt; die Limits halten die Tabelle schlank und
  -- verhindern, dass sie als Ablage missbraucht wird.
  message text check (char_length(message) <= 1000),
  stack text check (char_length(stack) <= 4000),
  app_version text check (char_length(app_version) <= 40),
  platform text check (char_length(platform) <= 20),
  created_at timestamptz not null default now()
);

create index error_reports_created_idx
  on public.error_reports (created_at desc);

alter table public.error_reports enable row level security;

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

-- Schreiben darf jeder, auch anon — sonst fehlen genau die Fehler aus dem
-- Login. Eine fremde group_id lässt sich nicht unterschieben: entweder
-- null oder die eigene.
create policy error_reports_insert on public.error_reports for insert
  with check (group_id is null or group_id = auth.uid());

-- Lesen darf über die API NIEMAND — bewusst keine select-Policy, und der
-- Sammel-Grant (alter default privileges) wird auf insert zurückgeschnitten:
-- Ein Fehlertext kann in Ausnahmefällen Serverdetails tragen, und die
-- Berichte aller Gruppen gehen keinen Client etwas an.
revoke all on public.error_reports from anon, authenticated;
grant insert on public.error_reports to anon, authenticated;

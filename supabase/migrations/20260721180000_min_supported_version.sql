-- Mindestversion, die veraltete Clients aussperrt (Issue #19).
--
-- Migrationen laufen automatisch beim Push auf `main`; ein installiertes APK
-- bleibt aber, wo es ist. Die Datenbank kann dem Client also davonlaufen —
-- der scheitert dann still oder zeigt Teildaten.
--
-- Der Wert liegt bewusst **hier** und nicht in einer Datei im Repo: Nur die
-- Datenbank weiß, ob sie migriert ist. Im Repo könnte er ihr vorauseilen
-- (Release da, Migration verzögert) und Leute aussperren, obwohl ihr Client
-- noch passt. Hier wird er von derselben Migration gesetzt, die das Schema
-- ändert, und kann deshalb nicht driften.
--
-- **Diese Tabelle hat absichtlich kein `group_id`** und ist damit die einzige
-- Ausnahme von der Mandanten-Leitplanke. Sie enthält keine Gruppendaten, alle
-- Gruppen müssen denselben Wert sehen, und Clients dürfen sie **nur lesen**:
-- Es gibt bewusst keine Insert-/Update-/Delete-Policy, sonst könnte ein Client
-- seine eigene Gruppe (oder alle) aussperren. Geändert wird der Wert
-- ausschließlich durch eine Migration.
--
-- `anon` darf lesen, damit der Schirm schon vor dem Login greift — wer
-- ausgesperrt ist, soll sich gar nicht erst anmelden.

create table public.app_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

-- 0.0.0 sperrt niemanden aus. Erhöht wird der Wert künftig in derselben
-- Migration, die etwas entfernt oder umbenennt, das ein veröffentlichter
-- Client liest.
insert into public.app_config (key, value)
  values ('min_supported_version', '0.0.0');

alter table public.app_config enable row level security;

create policy app_config_read on public.app_config
  for select to anon, authenticated using (true);

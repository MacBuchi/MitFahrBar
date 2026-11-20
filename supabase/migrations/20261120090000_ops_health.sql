-- Migration 20261120090000: ops_health() – Statusabfrage für den Betreiber.
--
-- Wozu: Ein Monitoring des Betreibers außerhalb dieses Repos fragt ab, ob
-- die App gesund ist. Dafür braucht es ein paar ZÄHLWERTE aus der
-- Datenbank – keine Zeile, keinen Text, keine ID.
--
-- Wie geschützt: Die Funktion ist für anon ausführbar (das Monitoring
-- hat nur den Publishable Key), verlangt aber einen Token. In der Datenbank
-- liegt nur dessen sha256 in app_internal.ops_config (Schema über die API
-- nicht erreichbar, RLS mit Sperr-Policy, keine Grants). Falscher oder
-- fehlender Token ⇒ 42501, ohne zu verraten, ob schon ein Hash gesetzt ist.
-- Den Hash setzt der Betreiber einmal im SQL-Editor (nicht über ein Repo):
--   insert into app_internal.ops_config (id, token_sha256)
--   values (true, encode(sha256(convert_to('<TOKEN>', 'UTF8')), 'hex'))
--   on conflict (id) do update set token_sha256 = excluded.token_sha256,
--                                  updated_at = now();
--
-- Security Advisor: „anon kann eine SECURITY-DEFINER-Funktion ausführen“
-- bleibt für ops_health bewusst stehen (Entscheidung Betreiber 2026-11-20);
-- der Token ist die Grenze, die Antwort enthält nur Zahlen.
-- Fester, leerer search_path: alles ist ausgeschrieben.
-- Kein neues Recht für die App, kein Bump von min_supported_version.

create schema if not exists app_internal;
revoke all on schema app_internal from public, anon, authenticated;

create table if not exists app_internal.ops_config (
  id boolean primary key default true check (id),
  token_sha256 text not null check (token_sha256 ~ '^[0-9a-f]{64}$'),
  updated_at timestamptz not null default now()
);
alter table app_internal.ops_config enable row level security;
create policy ops_config_no_client on app_internal.ops_config
  for all to anon, authenticated using (false) with check (false);
revoke all on table app_internal.ops_config from public, anon, authenticated;

create or replace function public.ops_health(p_token text)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_hash text;
begin
  select c.token_sha256 into v_hash from app_internal.ops_config c where c.id;
  if v_hash is null or p_token is null
     or encode(sha256(convert_to(p_token, 'UTF8')), 'hex') <> v_hash then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'db_size_mb', pg_database_size(current_database()) / 1048576,
    'errors_24h', (select count(*) from public.error_reports
                    where created_at > now() - interval '24 hours'),
    'errors_7d', (select count(*) from public.error_reports
                   where created_at > now() - interval '7 days'),
    'feedback_open', (select count(*) from public.feedback where processed_at is null),
    'feedback_7d', (select count(*) from public.feedback
                     where created_at > now() - interval '7 days'),
    'devices_active_7d', (select count(*) from public.push_devices
                           where last_seen_at > now() - interval '7 days'),
    -- push_outbox behält alte Zeilen als Digest-Speicher: kein Stau-Signal hier
    'push_stuck', null,
    'push_last_at', (select extract(epoch from max(sent_at))::bigint from public.push_log),
    'min_version', (select value from public.app_config where key = 'min_supported_version'),
    'extra', jsonb_build_array(
      jsonb_build_array('Gruppen', (select count(*) from public.groups)),
      jsonb_build_array('Personen', (select count(*) from public.persons)),
      jsonb_build_array('Fahrten (nächste 7 Tage)', (select count(*) from public.trips
                                                      where trip_date between current_date and current_date + 7)),
      jsonb_build_array('Fahrten (letzte 30 Tage)', (select count(*) from public.trips
                                                      where trip_date between current_date - 30 and current_date - 1)))
  );
end;
$$;
revoke all on function public.ops_health(text) from public;
grant execute on function public.ops_health(text) to anon;

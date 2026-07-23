-- Mehrere Fahrer je Tag übersteuern (Issue #62).
--
-- `plan_overrides` hielt genau EINEN Fahrer je (Gruppe, Tag) — der PK
-- (group_id, plan_date) erzwang das. Ab jetzt ist jede Zeile ein Fahrer;
-- das Übersteuern eines Tages ist die Menge seiner Zeilen. Bestehende
-- Zeilen bleiben gültig: Sie sind Mengen der Größe 1.
--
-- Der Schlüsselwechsel bricht veröffentlichte Clients: Ihr Upsert nennt
-- `onConflict: 'group_id,plan_date'`, und dieses Konfliktziel hat nach dem
-- Umbau keinen passenden Unique-Constraint mehr — Postgres lehnt jedes
-- Speichern eines Fahrer-Übersteuerns ab („no unique or exclusion
-- constraint matching the ON CONFLICT specification"). Deshalb steigt IM
-- SELBEN FILE die Mindestversion (die Regel aus CLAUDE.md, angelegt mit
-- 20260721180000_min_supported_version.sql — dies ist ihre erste echte
-- Nutzung): Sobald das 0.27.0-Release existiert, führt der Sperr-Schirm
-- ältere Clients zum Update, statt sie still scheitern zu lassen.

alter table public.plan_overrides
  drop constraint plan_overrides_pkey;
alter table public.plan_overrides
  add primary key (group_id, plan_date, driver_id);

update public.app_config
   set value = '0.27.0', updated_at = now()
 where key = 'min_supported_version';

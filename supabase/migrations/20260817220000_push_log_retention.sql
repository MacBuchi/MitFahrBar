-- `push_log` behält 90 Tage — es ist ein Versand-Gedächtnis, kein Archiv
-- (Befund aus der Finanzierungs-Analyse, doc/finanzierung-und-skalierung.md).
--
-- Bisher wuchs die Tabelle unbegrenzt: eine Zeile je Person, Plantag und
-- Meldungsart, für immer. Stand 17.08.2026 sind das 55 Zeilen — der Posten
-- ist Vorsorge, kein Brand; er ist nur der einzige, der ohne Gegenmaßnahme
-- prinzipiell endlos wächst.
--
-- Warum Löschen hier nichts erneut auslösen kann: `push_due()` liest
-- `push_log` ausschließlich im Join gegen `push_outbox`, und der Korb hält
-- nie Tage vor `keep_from` (der aktuellen Planungswoche) —
-- `publish_push_outbox` räumt Älteres bei jedem Schreiben weg. Eine Zeile,
-- deren `plan_date` 90 Tage zurückliegt, kann also weder eine Erinnerung
-- entsperren noch in einen Digest-Vergleich geraten. Die Grenze ist bewusst
-- um ein Vielfaches großzügiger als der eine Planungshorizont, den der
-- Versand braucht: Die jüngere Geschichte bleibt für Diagnosen lesbar —
-- genau so wurden #175 und #180 untersucht.
--
-- Gelöscht wird nach `plan_date`, nicht `sent_at`: Das ist die fachliche
-- Achse der Zeile (und `push_log_date_idx` liegt darauf). `current_date - 90`
-- statt `interval '90 days'`, damit der Vergleich im date-Typ bleibt.
--
-- Muster wie `rollup_fuel_weeks` (dort 21 Tage für `price_sample`):
-- Funktion mit `revoke all`, täglich per pg_cron zur krummen Minute.
--
-- Die Mindestversion bleibt unberührt: Kein Client liest `push_log`
-- (null Policies), es fällt nichts weg, das ein veröffentlichter Client
-- kennt.

create or replace function public.prune_push_log()
returns void language plpgsql security definer
set search_path = public as $$
begin
  -- 90 Tage: weit jenseits jedes Digest- und Erinnerungs-Horizonts (eine
  -- Woche), nah genug, dass die Tabelle im Gleichgewicht bleibt.
  delete from public.push_log
   where plan_date < current_date - 90;
end;
$$;

revoke all on function public.prune_push_log() from anon, authenticated;

select cron.schedule(
  'prune-push-log',
  '45 2 * * *',
  $$select public.prune_push_log()$$
);

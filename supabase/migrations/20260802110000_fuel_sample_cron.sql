-- Abtast-Takt fürs Preisarchiv (Schritt 1, Fortsetzung von 20260802100000).
--
-- Dreimal am Tag eine Umkreisabfrage je Region. Der Wochenwert ist später
-- das 10. Perzentil dieser Stichproben — nicht das Minimum, weil man nie
-- genau beim billigsten Anbieter zum billigsten Zeitpunkt tankt.
--
-- **Warum feste Uhrzeiten und nicht „alle acht Stunden":** Der Tagesgang der
-- Spritpreise ist ausgeprägt (früh teuer, abends billig). Drei feste
-- Zeitpunkte decken ihn ab — und nur mit festen Zeitpunkten lässt sich
-- dieselbe Stichprobe später aus dem Tankerkönig-Preiswechsel-Archiv
-- rekonstruieren. Ohne diese gemeinsame Definition entstünde an der Naht
-- zwischen importierter Vergangenheit und gemessener Gegenwart eine Stufe,
-- die keine Preisänderung ist.
--
-- pg_cron rechnet in UTC. 05:05/11:05/17:05 UTC sind im Sommer 07:05/13:05/
-- 19:05 und im Winter eine Stunde früher. Die Verschiebung ist bewusst in
-- Kauf genommen: Eine zeitzonenrichtige Planung bräuchte einen zweiten
-- Mechanismus für einen Effekt, den ein Wochenperzentil kaum sieht.
-- Die Minute 5 statt 0, weil die Nutzungsbedingungen ausdrücklich um
-- versetzte Abfragezeiten bitten.
--
-- **Noch kein Aufräumen.** Die Rohschicht wird erst weggeräumt, wenn der
-- Verdichtungslauf existiert — vorher gelöscht wäre sie verloren, bevor
-- irgendjemand sie zu einem Wochenwert gemacht hat.

-- Zugangsdaten aus dem Vault, gleiche Begründung wie bei `flush_due_push`:
-- Eine Spalte mit dem Geheimnis stünde für jeden mit service_role-Zugang im
-- Klartext und landete in jedem Datenbank-Abzug. Fehlen die Einträge, tut
-- die Funktion **nichts** — der lokale Teststack bleibt lauffähig.
--
-- `push_functions_url` und `push_service_key` werden mitbenutzt: Beides ist
-- Infrastruktur und kein Push-Detail, und ein zweiter Eintrag mit demselben
-- Wert wäre eine Stelle mehr, die auseinanderlaufen kann. Das Job-Geheimnis
-- ist dagegen eigen — ein Leck im Push-Weg soll nicht auch diesen öffnen.
--
-- Einmalig einzurichten (Betreiber, nicht im Repo):
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
  -- Feature eingerichtet hat, wird auch kein fremder Dienst befragt.
  if not exists (select 1 from public.price_area) then
    return;
  end if;

  -- Der `apikey`-Header ist Pflicht: Das Supabase-Gateway weist einen Aufruf
  -- ohne ihn ab, BEVOR die Function läuft — und pg_net schickt asynchron,
  -- die Antwort landet nur in `net._http_response`. Das Symptom wäre „es
  -- passiert nichts, und nirgends steht ein Fehler". `Authorization` nur bei
  -- JWT-artigen Schlüsseln; neue `sb_secret_*`-Keys sind keine JWTs mehr.
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

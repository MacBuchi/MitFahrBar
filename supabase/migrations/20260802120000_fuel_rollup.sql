-- Verdichtungslauf fürs Preisarchiv (Schritt 1, Abschluss).
--
-- Aus den Stichproben in `price_sample` wird je Gruppe, ISO-Woche und Sorte
-- EIN Wert in `price_week`: das 10. Perzentil. Nicht das Minimum — man tankt
-- nie genau beim billigsten Anbieter zum billigsten Zeitpunkt. Gemessen an
-- der realen Zielregion ist der Unterschied deutlich: Im 20-km-Umkreis um
-- Bad Rappenau wandert das Minimum um 11 ct, sobald der Kreis wächst, das
-- Perzentil steht still.
--
-- **Warum hier in SQL und nicht in Dart.** `percentile_cont` ist zeichengenau
-- dieselbe Definition wie `percentile` in `lib/core/price_series.dart`
-- (lineare Interpolation zwischen den Rangwerten), und der spätere Import der
-- Vergangenheit läuft in Python — eine einzige Implementierung ist gar nicht
-- zu haben. Zu haben ist EINE Definition, an die jede Seite festgenagelt
-- wird: `test/schema_test.dart` hält den Anteil hier mit `defaultPercentile`
-- in Dart zusammen. Dasselbe Muster wie beim Push-Digest.
--
-- **In deutscher Zeit gerechnet.** Die ISO-Woche einer Stichprobe entscheidet
-- die Ortszeit, nicht UTC: Eine Messung am Sonntag 23:30 UTC ist in
-- Deutschland bereits Montag und gehört in die Folgewoche. Bei den festen
-- Abtastzeiten (7/13/19 Uhr) tritt der Fall zwar nicht auf — aber die
-- Zeitpunkte sind eine Cron-Zeile, und die ändert irgendwann jemand.

create or replace function public.rollup_fuel_weeks()
returns void language plpgsql security definer
set search_path = public as $$
declare
  -- Ab Montag der VORwoche: Die laufende Woche wird bei jedem Lauf neu
  -- gerechnet (sie wächst noch), die abgeschlossene einmal mehr, damit eine
  -- Stichprobe kurz vor Mitternacht am Sonntag nicht verlorengeht.
  from_local timestamp := date_trunc(
    'week', (now() at time zone 'Europe/Berlin') - interval '7 days'
  );
begin
  with unpivoted as (
    -- Eine Zeile je (Stichprobe, Sorte). Fehlende Sorten fallen raus statt
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
  -- Region hängt und nicht an der Gruppe: Zwei Gruppen derselben Gegend
  -- bekommen ihre eigenen Wochenzeilen aus EINER Abfrage.
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
         -- Eine importierte Woche, die zusätzlich Messungen bekommt, wird
         -- `mixed` statt still zu `measured`. Das passiert genau einmal, an
         -- der Naht zwischen Vergangenheit und Gegenwart — und dort soll das
         -- Diagramm es zeigen können, statt einen Sprung zu verschweigen.
         origin = case
           when w.origin in ('imported', 'mixed') then 'mixed'
           else excluded.origin
         end,
         computed_at = now();

  -- Rohwerte sind Zwischenprodukt, kein Archiv (so gewollt: „nur zum
  -- Verarbeiten speichern"). 21 Tage ist der Sicherheitsabstand — verdichtet
  -- wird höchstens die Vorwoche, gelöscht erst drei Wochen zurück, damit ein
  -- ausgefallener Lauf nichts kostet. Die letzten 7 Tage wären zugleich die
  -- Grundlage eines späteren „Tankdaumens"; die stehen also immer bereit.
  delete from public.price_sample
   where captured_at < now() - interval '21 days';
end;
$$;

revoke all on function public.rollup_fuel_weeks() from anon, authenticated;

-- Zwanzig Minuten nach dem Abtasten: `pg_net` schickt asynchron, die
-- Stichproben treffen erst Sekunden später ein. Ein Lauf im selben Moment
-- verdichtete zuverlässig den Stand von vorhin.
select cron.schedule(
  'rollup-fuel-weeks',
  '25 5,11,17 * * *',
  $$select public.rollup_fuel_weeks()$$
);

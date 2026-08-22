-- Der geplante Live-Takt fällt. Wochenwerte kommen ab hier ausschließlich
-- aus dem Archiv (`tool/import_fuel_history.py`).
--
-- **Der Grund ist eine Grenze, die Geld nicht verschiebt.** Tankerkönig
-- deckelt je Schlüssel auf eine Abfrage je Minute und nennt zwei Dinge
-- ausdrücklich als Sperrgrund: flächendeckendes Abfragen und „regelmäßige,
-- nicht explizit vom User initiierte Requests". Genau das war dieser Takt:
-- je Gebiet dreimal täglich, gedeckelt auf fünf Gebiete pro Lauf. Und der
-- Deckel schnitt OHNE Sortierung und ohne Cursor ab — „vertagt" wurde
-- nichts, ab dem sechsten Gebiet wäre dauerhaft dasselbe leer ausgegangen.
-- Bei zwei Gebieten war das folgenlos; mit der Gruppenzahl wäre es still
-- falsch geworden.
--
-- **Für Clients ändert sich nichts, und deshalb wird
-- `min_supported_version` NICHT gehoben.** Gelesen wird ausschließlich
-- `price_week` — die Tabelle bleibt samt Policy, Grants und Bedeutung, nur
-- ihre Quelle wechselt. Kein veröffentlichter Client bricht, keiner zeigt
-- falsche Daten; ein alter wie ein neuer sieht dieselbe Reihe. Der einzige
-- sichtbare Unterschied: Die laufende Woche bekommt ihren Wert erst, wenn
-- sie vorbei und im Archiv ist, statt tagesaktuell — bis dahin hält der
-- Lesepfad den letzten bekannten Wert, wie bei jeder anderen Lücke auch.
--
-- Die Kennzahl bleibt dieselbe: Der Nachfüller rechnet seit jeher das 10.
-- Perzentil derselben Stichprobe, die auch gemessen wurde (drei Stichzeiten
-- an sieben Tagen). Es entsteht also keine Stufe an der Naht — genau dafür
-- war diese Deckungsgleichheit gebaut.
--
-- Reihenfolge trägt: erst die Zeitpläne (sie rufen die Funktionen), dann die
-- Funktionen, dann die Tabelle (die der Verdichter liest).

-- Über die Job-Tabelle statt `cron.unschedule('name')`: Letzteres wirft,
-- wenn der Job fehlt, und ließe die Migration auf einem Stack scheitern,
-- der ihn nie hatte (lokaler Teststack, frische Datenbank).
select cron.unschedule(jobid)
  from cron.job
 where jobname in ('sample-fuel-prices', 'rollup-fuel-weeks');

drop function if exists public.sample_fuel_prices();
drop function if exists public.rollup_fuel_weeks();

-- Die Rohschicht war Zwischenprodukt, nie Archiv — verdichtete Stichproben
-- wurden nach 21 Tagen ohnehin weggeräumt. Ohne Verdichter hat sie keinen
-- Leser mehr. Ein Client konnte sie nie sehen (null Policies, `revoke all`),
-- es fällt also auch keine Sichtbarkeit weg.
drop table if exists public.price_sample;

-- **Die Geheimnisse bleiben liegen, und das ist Absicht.** `fuel_job_secret`
-- (Vault) und der Tankerkönig-API-Schlüssel (Function-Secret) haben ab hier
-- keinen Aufrufer mehr. Sie zu entfernen ist eine Dashboard-Handlung, keine
-- Migration — und der Schlüssel soll bleiben: Ein späterer „Tankdaumen"
-- (aktueller Preis gegen das Wochen-Perzentil) ist eine NUTZERAKTION und
-- damit genau die Nutzung, um die Tankerkönig bittet. Neu beantragen müsste
-- man ihn sonst.

-- Anmerkungen zu einem Plantag (Issue #127, deckt #120 mit ab).
--
-- Der Wunsch kam zweimal in derselben Woche: einmal als „Uhrensymbol für
-- abweichende Zeiten" (#120, aus der App eingereicht), einmal als „Chat an
-- der Wer-fährt-Kachel" mit dem Beispiel „falls jemand erst ab 9 mitfahren
-- kann" (#127). Umgesetzt ist die zweite Fassung: Ein Symbol ohne Uhrzeit
-- sagt nichts, mit Uhrzeit bräuchte das Raster einen Zeitwähler, wo heute
-- ein Tap steht — freier Text deckt beides ab und noch das, wofür sonst
-- jedes Mal ein neues Symbol nötig wäre („ich parke woanders").
--
-- **Was das hier NICHT ist: ein Chat.** KONZEPT.md §1 zieht die Grenze
-- („Kommunikation bleibt in WhatsApp") und sie gilt weiter — es gibt keine
-- Threads, kein Gelesen-Status, keine Antworten. Deshalb `plan_notes` und
-- nicht `chat_messages`: Der Name steht neben `plan_availability` und
-- `plan_overrides` und sagt, was er ist — eine Notiz am Plantag. Zugestellt
-- wird über den bestehenden 10-Minuten-Job (real ~70 min, Issue #115); wer
-- etwas JETZT sagen muss, greift zum Telefon.
--
-- **Die Punkte bleiben unberührt.** Wie `plan_availability` speichert diese
-- Tabelle nur, was Menschen geschrieben haben; `lib/core/fairness.dart`
-- sieht sie nie. Eine Anmerkung ist keine Planungsentscheidung.
--
-- Mindestversion wird NICHT gehoben: Es wird nichts entfernt oder
-- umbenannt, was ein veröffentlichter Client liest. Ältere Clients kennen
-- die Tabelle schlicht nicht und zeigen keine Anmerkungen.

-- Der Schlüssel ist eine generierte UUID, KEIN fachlicher: Mehrere
-- Anmerkungen je Tag und Person sind der Normalfall. Die Regel „group_id
-- gehört in den Schlüssel" zielt auf fachliche Schlüssel, die ohne sie über
-- alle Gruppen eindeutig wären — eine UUID ist das ohnehin. Vorlage ist
-- deshalb `feedback`, nicht `plan_availability`.
--
-- `btrim` im Längen-Check ist nicht kosmetisch: `between 1 and 500` allein
-- ließe 500 Leerzeichen durch, und die Anzeige stünde vor einer leeren
-- Zeile, die sie nicht erklären kann.
--
-- `person_id` ist der Verfasser und wie überall sonst KEIN Identitäts-
-- nachweis: Jeder kann für jeden schreiben, genau wie im Planer jeder für
-- jeden einträgt („eine Gruppe = ein Login"). Die Geräte-Zuordnung aus #121
-- belegt das Feld nur vor.
create table public.plan_notes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  person_id uuid not null references public.persons(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);

-- Gelesen wird immer eine Spanne von Tagen (die Planwoche) innerhalb einer
-- Gruppe — genau in dieser Reihenfolge liegt der Index.
create index plan_notes_day_idx on public.plan_notes (group_id, plan_date);

-- --------------------------------------------------------------------- RLS

alter table public.plan_notes enable row level security;

create policy plan_notes_isolated on public.plan_notes
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

-- ------------------------------------------------------------------ Grants
-- Explizit statt über `alter default privileges`, gleiche Begründung wie in
-- 20260723090000: Was die Client-Rollen dürfen, soll im File stehen.

grant select, insert, update, delete on public.plan_notes
  to anon, authenticated;
grant all on public.plan_notes to service_role;

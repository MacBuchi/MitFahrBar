-- Zustimmung eines Mitfahrers zu den Bedingungen eines Autos (#189, Stufe B2).
--
-- Der Wunsch im Issue lautete „Mitfahrer sollten bei mehreren Autos ihr Auto
-- wählen können". Gebaut ist bewusst etwas anderes und Engeres: **nicht die
-- freie Wahl eines Autos, sondern das Einverständnis mit einer Abfahrt.**
-- Entschieden am 07.08. — der Anlass ist nicht Bequemlichkeit, sondern dass
-- ein Fahrer seit #183 die Abfahrtszeit seines Autos verschieben kann. Wer
-- um 07:30 zugesagt hat, darf davon nicht stillschweigend auf 05:30 gezogen
-- werden.
--
-- Daraus folgen die zwei Werte von `accepted`:
--
--   true  — **Pin.** „Mit diesem Fahrer und zu diesen Bedingungen, ja."
--           `planWeek` setzt die Person in genau dieses Auto.
--   false — **Ausschluss.** „Zu diesen Bedingungen nicht." Die Person wird
--           NICHT in dieses Auto gesetzt; reicht der Rest nicht, entsteht
--           dadurch ein zweites Auto. Genau das ist der Zweck.
--
-- **`terms` ist der Kern der Tabelle, nicht Beiwerk.** Gespeichert wird, WOZU
-- jemand ja gesagt hat — die wirksame Abweichung dieses Autos als kanonischer
-- Text (`hh:mm|hh:mm|Ort`, leer = die festen Vorgaben der Gruppe). Ohne diese
-- Spalte wäre eine Zusage ein Blankoscheck: Man stimmt 06:45 zu, der Fahrer
-- stellt auf 05:30 um, und das alte Ja gälte weiter. Stimmt der gespeicherte
-- Text nicht mehr mit dem aktuellen überein, ist die Entscheidung **veraltet
-- und wirkt nicht** — der Client fragt dann neu. Dasselbe gilt für den
-- Ausschluss, und zwar in die andere Richtung: Nimmt der Fahrer seine
-- Abweichung zurück, verfällt auch die Ablehnung, sonst gäbe es dauerhaft
-- zwei Autos wegen einer Zeit, die es nicht mehr gibt.
--
-- **`decided_at` entscheidet bei Überfüllung**: Wollen fünf Leute in einen
-- Vierer, bleibt, wer zuerst gepinnt hat (entschieden 07.08.). Das ist der
-- einzige Grund für die Spalte — sie geht damit in die Plan-Rechnung ein und
-- ist kein Protokollfeld.
--
-- **Verwaiste Zeilen sind zulässig und werden nicht aufgeräumt** — dieselbe
-- Linie wie bei `plan_car_defaults`: Fährt die `driver_id` an dem Tag nicht,
-- fällt die Zeile beim Auflösen heraus und wirkt nicht; fährt er wieder, gilt
-- sie wieder. Ein Aufräum-Trigger müsste `planWeek` in SQL nachbauen.
--
-- **Kein Eingriff an `push_due()` oder `publish_push_outbox`.** Wer in
-- welchem Auto sitzt, rechnet weiterhin allein der Client; der Versand
-- entscheidet nur, OB und WANN. Die Sitzwahl verschiebt zwar die wirksame
-- Zeit einer Person — aber die reist seit #183 Stufe A fertig im
-- Ausgangskorb, genau dafür ist sie dort abgelegt.
create table public.plan_seat_choices (
  group_id uuid not null default auth.uid()
    references public.groups(id) on delete cascade,
  plan_date date not null,
  -- Wer entscheidet.
  person_id uuid not null references public.persons(id) on delete cascade,
  -- Über wessen Auto. Ein Auto existiert in der Datenbank nur als „diese
  -- Person fährt an diesem Tag" — dieselbe Begründung wie bei
  -- `plan_car_defaults`, und derselbe Schlüsselteil.
  driver_id uuid not null references public.persons(id) on delete cascade,
  accepted boolean not null,
  -- Die Bedingungen, zu denen entschieden wurde. Leerer Text = die festen
  -- Vorgaben der Gruppe galten. NICHT null-bar: „keine Abweichung" ist eine
  -- Aussage und muss sich von „unbekannt" unterscheiden lassen.
  terms text not null default '',
  decided_at timestamptz not null default now(),
  -- `group_id` gehört in den Schlüssel, sonst wäre er über alle Gruppen
  -- eindeutig und die zweite Gruppe liefe in eine Unique-Verletzung auf einer
  -- Zeile, die die RLS ihr nicht einmal zeigt.
  primary key (group_id, plan_date, person_id, driver_id),
  -- Niemand entscheidet über sein eigenes Auto: Wer fährt, sitzt darin.
  constraint plan_seat_choices_not_self check (person_id <> driver_id)
);

alter table public.plan_seat_choices enable row level security;

create policy plan_seat_choices_isolated on public.plan_seat_choices
  for all to authenticated
  using (group_id = auth.uid() and public.my_group_active())
  with check (group_id = auth.uid() and public.my_group_active());

grant select, insert, update, delete on public.plan_seat_choices
  to anon, authenticated;
grant all on public.plan_seat_choices to service_role;

-- **Die Mindestversion wird NICHT gehoben.** Ein Client von vor v0.67.0 liest
-- die Tabelle nicht und rechnet ohne sie: Er zeigt die automatische
-- Verteilung, also denselben Plan wie bisher. Das ist keine falsche Angabe
-- über einen Tag, sondern ein Plan ohne die neue Feinheit — und eine
-- Mindestversion wirft jeden veralteten Client auf den Sperr-Schirm, aus dem
-- man sich nicht heraus-releasen kann. Gehoben wird, wenn ein alter Client
-- falsche Daten ZEIGT oder in eine Exception läuft; beides ist hier nicht der
-- Fall.

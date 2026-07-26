-- persons.name: eindeutig je GRUPPE statt global (Issue #109).
--
-- `20260719000000_initial_schema.sql` schrieb `name text unique not null` —
-- damals richtig, denn es gab genau einen Login. Die Multi-Tenant-Migration
-- ergänzte überall `group_id` und RLS, ließ diesen Constraint aber stehen.
-- Folge in Produktion (nachgemessen am 26.07.2026:
-- `persons_name_key | UNIQUE (name)`):
--
--   * Sobald IRGENDEINE andere Gruppe eine „Anna" hat, kann die eigene keine
--     anlegen. Bei zwei realen Fahrgemeinschaften ist ein gemeinsamer
--     Vorname der Normalfall, nicht der Ausnahmefall.
--   * Der Fehlschlag ist ein Orakel: Wer einen Namen ausprobiert, erfährt,
--     ob er in einer fremden Gruppe existiert. Klein, aber genau die Sorte
--     Querverweis, die die RLS sonst unmöglich macht.
--
-- Ersetzt wird durch einen INDEX, nicht durch eine `unique (…)`-Klausel:
-- Eindeutig soll der Name unabhängig von Groß-/Kleinschreibung und
-- Rand-Leerzeichen sein, und ein Constraint kann keinen Ausdruck tragen.
--
-- `lower(btrim(name))` ist **genau** die Normalisierung, mit der
-- `lib/core/csv_import.dart` Namen auf Personen abbildet
-- (`person.name.trim().toLowerCase()`). Driftete beides auseinander, fände
-- der Import zu einem Namen zwei Zeilen und nähme willkürlich die erste —
-- und schriebe damit Fahrten auf die falsche Person.
--
-- Inaktive zählen mit (bewusst KEIN `where active`): Wer zurückkommt, wird
-- reaktiviert, nicht neu angelegt. Eine zweite Zeile spaltete seine
-- Punkte-Historie und verschöbe damit rückwirkend die Quote aller anderen —
-- dieselbe Begründung, aus der es kein `deletePerson` gibt.
--
-- Gefahrlos auf den Bestandsdaten, und das ist geprüft statt angenommen: Der
-- globale Unique garantiert, dass es heute nirgends zwei identische Namen
-- gibt. Bliebe die Möglichkeit „anna" neben „Anna" — dagegen lief am
-- 26.07.2026 eine Abfrage über die Produktions-DB, gruppiert nach
-- `lower(btrim(name))`: keine Treffer. Ohne diese Prüfung wäre die Migration
-- ein Vabanquespiel, denn sie scheitert beim Push auf `main` und lässt einen
-- halben Deploy zurück.
--
-- Die Mindestversion wird NICHT gehoben: Ein veröffentlichter Client liest
-- keinen Constraint. Er bricht nicht und zeigt nichts Falsches — er kann
-- danach mehr als vorher. Heben würde jeden alten Client auf den Sperr-Schirm
-- werfen, und das ist nach der Regel in CLAUDE.md der Ausnahmefall, nicht der
-- Normalfall einer Migration.

alter table public.persons drop constraint persons_name_key;

create unique index persons_group_name_key
  on public.persons (group_id, lower(btrim(name)));

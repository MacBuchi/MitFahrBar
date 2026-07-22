-- Explizite Grants für die Client-Rollen (Fund aus dem E2E-Testsetup).
--
-- Bisher verließ sich das Schema auf die impliziten Default-Privileges der
-- Supabase-Plattform: anon/authenticated bekamen DML automatisch, nur
-- service_role brauchte den expliziten Grant auf feedback (Feedback-Bot).
-- Neuere Stacks sind „secure by default" — der lokale CLI-Stack (Postgres-
-- 17-Image) gibt Client-Rollen ohne expliziten Grant weder SELECT noch
-- INSERT/UPDATE/DELETE und Funktionen kein EXECUTE. Ohne diese Datei fände
-- die App auf einem frischen Stack (Teststack, VM, CI) keine einzige
-- Tabelle vor und kein RPC wäre aufrufbar.
--
-- Die Zugriffskontrolle liegt unverändert VOLLSTÄNDIG in den RLS-Policies —
-- Grants sind nur die Postgres-Basisrechte, auf denen RLS überhaupt greift
-- (exakt das Modell, das auf Prod bisher implizit galt: anon sieht leere
-- Ergebnisse statt Fehler, Schreiben scheitert an RLS).

grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete
  on all tables in schema public to anon, authenticated;
grant all on all tables in schema public to service_role;

grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

grant execute on all functions in schema public
  to anon, authenticated, service_role;

-- Künftige Tabellen/Funktionen aus Migrationen verhalten sich genauso
-- (gilt für Objekte, die die Migrationsrolle `postgres` anlegt).
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
alter default privileges in schema public
  grant all on tables to service_role;
alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;

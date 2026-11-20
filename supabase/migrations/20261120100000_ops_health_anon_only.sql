-- Migration 20261120100000: ops_health() nur für anon, nicht für angemeldete Nutzer.
--
-- 20261120090000_ops_health entzog EXECUTE nur PUBLIC. Supabase vergibt für
-- neue Funktionen in `public` aber per Default-Privileges eigene Grants an
-- anon UND authenticated – die blieben stehen (Security Advisor 2026-11-20:
-- „Signed-In Users Can Execute SECURITY DEFINER Function“ für ops_health).
-- Gebraucht wird nur anon (das Monitoring hat nur den Publishable Key).
-- Die Token-Prüfung galt auch für authenticated; das hier räumt nur den
-- unnötigen Grant weg. Kein neues Recht, Mindestversion bleibt.
revoke execute on function public.ops_health(text) from authenticated;

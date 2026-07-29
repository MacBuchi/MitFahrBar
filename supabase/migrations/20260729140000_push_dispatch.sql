-- Versand aus dem Ausgangskorb (Issue #132, Teil 2 — löst #115).
--
-- Teil 1 hat den Korb angelegt: Der Client rechnet mit dem echten `planWeek`
-- aus, was zu sagen wäre, und legt es ab. Hier kommt der Abholer dazu.
--
-- **Was sich für die Gruppe ändert.** Eine Änderung am Wochenplan erreicht
-- die anderen künftig binnen rund einer Minute statt frühestens beim nächsten
-- Actions-Lauf — der real oft erst nach einer Stunde kam (#115: gemessen
-- 15:14, 16:27, 17:38 UTC an einem Tag). Wer um 7:05 umplant, dessen Meldung
-- kam bisher womöglich nach der Abfahrt, also nie.
--
-- **Wo die Arbeit liegt.** Der Text steht schon im Korb; hier wird nur noch
-- entschieden, *ob* und *wann*. Das ist Buchhaltung — Zeitfenster, Vergleich
-- mit `push_log`, Mindestabstand — und keine Fairness. `planWeek` bleibt in
-- Dart, genau wie #115 es verlangt hat; nur die Zuordnung „Entscheider =
-- Edge Function" war dort zu grob.
--
-- **Warum die Auswahl in SQL steht und nicht in TypeScript.** Das Fenster
-- geht von der Abendzeit des Vortages bis zur Abfahrtszeit — beides in
-- Europe/Berlin, beides über Sommerzeitwechsel hinweg. Postgres rechnet das
-- richtig, `Date` in Deno tut es nur mit viel Sorgfalt. Ein Fehler dort wäre
-- zweimal im Jahr eine Stunde daneben und in keinem Test zu sehen.

create extension if not exists pg_cron;

-- --------------------------------------------------------------- Auswahl
--
-- Dieselben Regeln wie `dueMessages` in `lib/core/push_digest.dart`, nur ohne
-- den Teil, der den Text macht:
--
--   * Fenster: ab Abendzeit des Vortages, bis Abfahrtszeit am Tag selbst.
--     Der Riegel am Ende ist wichtig — ein nachgeholter Lauf darf niemanden
--     nachts wecken, und nach der Abfahrt nützt keine Meldung mehr.
--   * Abend-Blick: nur wenn für den Tag noch keiner raus ist, nur an
--     Anwesende (ein „du bist nicht dabei" an jemanden, der nie eingetragen
--     war, wäre Lärm) und nur bei eingeschaltetem Abend-Blick.
--   * Änderung: nur nach einem Abend-Blick, nur bei geändertem Digest, nur
--     außerhalb der Mindestabstands-Sperre — und nur, wenn die Zeile fällig
--     ist. Genau dieses `due_at` ist das Entprellen aus Teil 1: Wer im Planer
--     weiterklickt, schiebt es vor sich her.
--
-- `'raus'` ist `removedDigest` aus `push_digest.dart`. Der Wert steht hier
-- ein zweites Mal, und `test/schema_test.dart` hält beide zusammen — driftete
-- er, bekäme ein Ausgetragener entweder gar keine oder endlos Meldungen.
create or replace function public.push_due(at timestamptz default now())
returns table (
  token text,
  group_id uuid,
  person_id uuid,
  plan_date date,
  kind text,
  digest text,
  title text,
  body text
)
language sql security definer set search_path = public as $$
  with ready as (
    select
      box.group_id,
      box.person_id,
      box.plan_date,
      box.digest,
      box.body,
      box.title_evening,
      box.title_change,
      case
        when evening.digest is null then
          case
            when prefs.evening_enabled and box.digest <> 'raus' then 'evening'
          end
        when prefs.changes_enabled
          and box.digest is distinct from coalesce(change.digest, evening.digest)
          and box.due_at is not null
          and box.due_at <= at
          and (change.sent_at is null
               or at - change.sent_at >= interval '30 minutes')
        then 'change'
      end as kind
    from public.push_outbox box
      join public.groups grp
        on grp.id = box.group_id and grp.status = 'active'
      join public.persons person
        on person.id = box.person_id and person.active
      join public.notification_prefs prefs
        on prefs.group_id = box.group_id and prefs.person_id = box.person_id
      left join public.push_log evening
        on evening.group_id = box.group_id
       and evening.person_id = box.person_id
       and evening.plan_date = box.plan_date
       and evening.kind = 'evening'
      left join public.push_log change
        on change.group_id = box.group_id
       and change.person_id = box.person_id
       and change.plan_date = box.plan_date
       and change.kind = 'change'
    where at >= ((box.plan_date - 1)::timestamp + prefs.evening_time)
                  at time zone 'Europe/Berlin'
      and at <  (box.plan_date::timestamp + prefs.departure_time)
                  at time zone 'Europe/Berlin'
  )
  select
    device.token,
    ready.group_id,
    ready.person_id,
    ready.plan_date,
    ready.kind,
    ready.digest,
    case when ready.kind = 'evening'
      then ready.title_evening else ready.title_change end,
    ready.body
  from ready
    join public.push_devices device
      on device.group_id = ready.group_id
     and device.person_id = ready.person_id
  where ready.kind is not null;
$$;

revoke all on function public.push_due(timestamptz) from anon, authenticated;

-- ---------------------------------------------------------------- Abholer
--
-- Der Minutentakt weckt nur; entschieden und gesendet wird in der Function
-- `flush-push`. Der Umweg ist Absicht: FCM braucht ein Dienstkonto, und das
-- gehört zu den übrigen Server-Geheimnissen, nicht in die Datenbank.
--
-- **Zugangsdaten aus dem Vault, nicht aus einer Tabelle.** Eine Spalte mit
-- dem Job-Geheimnis stünde für jeden mit service_role-Zugang im Klartext und
-- landete in jedem Datenbank-Abzug. Fehlen die Einträge, tut die Funktion
-- **nichts** — so bleibt der lokale Teststack und jede Frischinstallation
-- lauffähig, ohne dass jemand Geheimnisse anlegen muss.
--
-- **Der `apikey`-Header ist Pflicht, nicht Beiwerk.** Das API-Gateway von
-- Supabase weist einen Aufruf ohne ihn ab, **bevor** die Function läuft —
-- und `pg_net` schickt asynchron: Die Antwort landet in `net._http_response`
-- und sonst nirgends. Das Symptom wäre „es kommt nichts an, und nirgends
-- steht ein Fehler". `Authorization` nur bei JWT-artigen Schlüsseln, genau
-- wie in `tool/notify.dart` — neue `sb_secret_*`-Keys sind keine JWTs mehr.
--
-- Einmalig einzurichten (Betreiber, nicht im Repo):
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1',
--                              'push_functions_url');
--   select vault.create_secret('<PUSH_JOB_SECRET>', 'push_job_secret');
--   select vault.create_secret('<SERVICE_ROLE_KEY>', 'push_service_key');
create or replace function public.flush_due_push()
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
    from vault.decrypted_secrets where name = 'push_job_secret';
  select decrypted_secret into service_key
    from vault.decrypted_secrets where name = 'push_service_key';
  if base_url is null or job_secret is null or service_key is null then
    return;
  end if;

  -- Nichts zu tun heißt: nicht anklopfen. Spart im Normalfall 1440 Aufrufe
  -- am Tag, und die Abfrage ist ein Index-Treffer.
  if not exists (select 1 from public.push_due()) then
    return;
  end if;

  perform net.http_post(
    url := base_url || '/flush-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', job_secret,
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

revoke all on function public.flush_due_push() from anon, authenticated;

select cron.schedule(
  'flush-due-push',
  '* * * * *',
  $$select public.flush_due_push()$$
);

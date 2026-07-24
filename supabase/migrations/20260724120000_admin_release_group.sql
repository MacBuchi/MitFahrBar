-- Verknüpfung lösen (Issue #73): Übergabe der Verwalter-Konsole.
--
-- Das Einrasten der Erst-Verknüpfung bleibt der Schutz gegen Übernahme von
-- außen — aber der AKTUELLE Verwalter darf sie selbst lösen (Sudo-Muster:
-- eigenes Admin-Passwort erneut). Danach kann sich ein anderes Konto über
-- den normalen claim-Weg mit dem Gruppen-Login verknüpfen — Übergabe und
-- Postfach-Wechsel funktionieren damit ohne Betreiber-Eingriff, wie der
-- „Transfer Ownership"-Standard in Gruppen-Software. Die Gruppendaten
-- bleiben unberührt, das Verwalter-Konto besteht weiter; es fällt nur die
-- Zeile in group_admins. Bewusste Grenze bleibt: Wer Postfach UND Passwort
-- verliert, braucht den Betreiber — jeder Selbstbedienungs-Weg daran vorbei
-- wäre die Übernahme-Lücke, die das Einrasten gerade verhindert.

create or replace function public.admin_release_group(
  admin_password text
) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  target uuid;
  own text;
begin
  select ga.group_id into target from public.group_admins ga
   where ga.user_id = auth.uid();
  if target is null then
    raise exception 'not linked';
  end if;

  select encrypted_password into own from auth.users where id = auth.uid();
  if own is null or own <> crypt(admin_password, own) then
    raise exception 'wrong admin password';
  end if;

  delete from public.group_admins where user_id = auth.uid();
end $$;

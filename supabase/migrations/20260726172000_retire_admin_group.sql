-- Die Admin-Gruppe wird abgeschafft (Issue #108)
--
-- Bis v0.37.0 saß die administrative Macht auf der falschen Art Konto:
-- `groups.is_admin` gehörte einem GETEILTEN Gruppen-Login ohne „Passwort
-- vergessen". Es gab genau eine solche Gruppe, gesetzt als Datenzeile in
-- `20260720140000_multi_tenant_groups.sql`, und keinen Code-Weg, das Flag zu
-- setzen. Am 26.07.2026 hat das zugeschlagen: Eine pending-Gruppe war nicht
-- freigebbar, weil das Passwort der einzigen Admin-Gruppe nicht zur Hand war
-- — es brauchte ein direktes `update public.groups set status='active'`.
--
-- Seit #106 entstehen Gruppen in der Verwalter-Konsole, sofort aktiv und
-- sofort verknüpft. Die Freigabe hat damit keine Aufgabe mehr, und mit ihr
-- fallen `is_admin`, `is_group_admin()` und die Update-Policy auf `groups`.
-- Verwaltet wird ausschließlich über ein Verwalter-Konto mit echter E-Mail —
-- dort funktioniert der Reset-Weg (#102), ein vergessenes geteiltes Passwort
-- kann also niemanden mehr blockieren.
--
-- DIE REIHENFOLGE IST DER INHALT. Zwei Stellen sind scharf:
--
-- * `handle_new_group()` wird NEU GESCHRIEBEN, BEVOR die Spalte fällt. Die
--   alte Fassung führt `is_admin` in ihrer Insert-Spaltenliste; bliebe sie
--   stehen, scheiterte JEDER künftige Signup — auch der eines
--   Verwalter-Kontos. Andere Richtung als im Plan skizziert und mit Absicht:
--   Die neue Fassung läuft auch gegen die noch vorhandene Spalte (sie hat
--   `default false`), also gibt es in keiner Sekunde ein Fenster, in dem
--   Registrieren kaputt ist — selbst wenn dieses File je außerhalb einer
--   Transaktion eingespielt würde.
--
-- * Die Policies fallen VOR der Funktion, die sie aufrufen. Umgekehrt
--   verweigert Postgres das `drop function` wegen der Abhängigkeit.
--
-- `groups` bekommt bewusst KEINE Update-Policy zurück: Gruppen ändern sich
-- nur noch über die SECURITY-DEFINER-Funktionen der Konsole (und künftig über
-- den vorgesehenen Aufräum-Job mit Service-Role-Key). Damit kann kein Client
-- mehr an einem `status` drehen.

-- ------------------------------------------------------ 1. Altlast auflösen
--
-- „Keine Gruppen ohne Zuordnung" ist ab hier die Regel — also müssen die
-- Reste des Freigabe-Zeitalters weg, und zwar differenziert:
--
-- * VERKNÜPFTE pending-Gruppen gehören einem Verwalter-Konto, das sich schon
--   ausgewiesen hat. Sie werden aktiv — die Freigabe, die niemand mehr
--   erteilen kann, war ihr einziges Hindernis.
-- * UNVERKNÜPFTE pending-Gruppen sind Fremd- oder Testsignups gegen die
--   Gruppen-Domain, ohne Besitzer und ohne jeden Inhalt: Die RLS verbietet
--   einer nicht-aktiven Gruppe jedes Lesen und Schreiben
--   (`my_group_active()`), sie KANN also keine Daten haben. Sie werden über
--   ihren Auth-User gelöscht, die Kaskade nimmt die Zeile mit, und ihr
--   Handle wird wieder frei.
--
-- `status = 'rejected'` bleibt unangetastet: ein ausgesprochenes Nein ist
-- eine Entscheidung, kein Rest.
update public.groups
   set status = 'active'
 where status = 'pending'
   and exists (select 1 from public.group_admins ga where ga.group_id = id);

delete from auth.users
 where id in (
   select g.id from public.groups g
    where g.status = 'pending'
      and not exists (select 1 from public.group_admins ga
                       where ga.group_id = g.id)
 );

-- Und die Admin-Gruppe selbst.
--
-- `fahrgemeinschaft` ist der allererste Auth-User dieser Instanz; die
-- Multi-Tenant-Migration hat ihn zur Gruppe mit `is_admin = true` gemacht
-- (`20260720140000`, Zeile 42). Getragen hat sie nie etwas: Die Daten gingen
-- 36 Minuten später in `daciaracing`, ihr einziger Zweck war das Flag. Nimmt
-- dieses File ihr das Flag und lässt die Zeile stehen, bleibt eine AKTIVE
-- Gruppe ohne Verwalter zurück — die Waise, die Invariante 1 ausschließt, und
-- niemand käme je wieder an sie heran: kein Gruppenpasswort mehr bekannt
-- (genau daran scheiterte am 26.07.2026 die Freigabe), also auch kein
-- `claim_admin_group`. Ein halber Rückbau wäre schlechter als keiner.
--
-- Gelöscht statt archiviert, weil es nichts zu bewahren gibt und eine
-- archivierte Leerzeile den Handle dauerhaft blockierte.
--
-- Die drei `not exists` sind kein Zierrat, sondern machen den Schritt
-- SELBSTPRÜFEND: Er trifft die Zeile nur, solange sie unverknüpft und
-- inhaltsleer ist. Auf jeder anderen Instanz — Frischinstallation, lokaler
-- Teststack, künftige Deployments — läuft er wirkungslos durch, und sollte
-- wider Erwarten doch etwas an ihr hängen, passiert nichts.
delete from auth.users
 where id in (
   select g.id from public.groups g
    where g.handle = 'fahrgemeinschaft'
      and not exists (select 1 from public.group_admins ga
                       where ga.group_id = g.id)
      and not exists (select 1 from public.persons p where p.group_id = g.id)
      and not exists (select 1 from public.trips   t where t.group_id = g.id)
 );

-- --------------------------------------- 2. handle_new_group() ohne is_admin
--
-- Bis auf die Spaltenliste unverändert. Der Trigger traut den Metadata eines
-- Signups weiterhin nur den Gruppennamen zu: Ein gebasteltes `auth.signUp`
-- gegen die Gruppen-Domain darf keine aktive oder fremd verknüpfte Gruppe
-- erzeugen können. Fremd-Signups landen als 'pending' und sind damit inert.
create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  -- Konsolen-Registrierungen erzeugen keine Geister-„pending"-Gruppe.
  if new.raw_user_meta_data->>'account_type' = 'admin' then
    return new;
  end if;
  insert into public.groups (id, name, handle, status)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'group_name', ''), new_handle),
          new_handle, 'pending');
  insert into public.settings (group_id, key, value) values
    (new.id, 'commute_km', 30),
    (new.id, 'one_way_factor', 0.5),
    (new.id, 'electricity_price_per_kwh', 0.35),
    (new.id, 'diesel_price_per_liter', 1.70),
    (new.id, 'petrol_price_per_liter', 1.78),
    (new.id, 'points_weight', 1.0);
  return new;
end $$;

-- ------------------------------------------------------- 3. Policies zurück
--
-- Eine Gruppe sieht ab hier ausschließlich sich selbst. Die Freigabe-Liste
-- („Admins sehen alle") gibt es nicht mehr, und die Update-Policy kommt
-- nicht zurück.
drop policy groups_admin_update on public.groups;
drop policy groups_select on public.groups;

create policy groups_select on public.groups for select to authenticated
  using (id = auth.uid());

-- ------------------------------------------- 4. Funktion und Spalte entfernen
--
-- Erst jetzt, nachdem beide Policies weg sind — sonst blockt die Abhängigkeit.
drop function public.is_group_admin();

alter table public.groups drop column is_admin;

-- -------------------------------------- Mindestversion: bewusst UNVERÄNDERT
--
-- Die Hausregel lautet „wer entfernt, was ein Client liest, hebt im selben
-- File die Mindestversion". Sie zielt auf Clients, die BRECHEN — und der
-- veröffentlichte 0.37.0-Client bricht hier nicht:
--
--   * `is_admin` fehlt   → `json['is_admin'] as bool? ?? false` liefert
--                          `false`, der Admin-Knopf verschwindet, kein Wurf.
--   * `pendingGroups()`  → `groups_select` zeigt nur die eigene Zeile,
--                          also eine leere Liste statt eines Fehlers.
--   * `setStatus()`      → ohne Update-Policy trifft das Update 0 Zeilen,
--                          ebenfalls kein Fehler.
--
-- Er degradiert also sauber, und zu erzwingen gibt es nichts.
--
-- Zu heben wäre hier sogar schädlicher als der Schaden, den es verhindern
-- soll: Die Mindestversion wirft JEDEN veralteten Client auf den
-- Sperr-Schirm — und dessen Update-Knopf war bis 0.37.0 tot (kein Navigator
-- im gesperrten Zustand, siehe `app.dart`; behoben in 0.38.0). Wer davor
-- steht, erreicht der Fix nicht mehr: Aus diesem Loch kann man sich nicht
-- heraus-releasen, es hilft nur Deinstallieren und Neuinstallieren von Hand.
-- Genau das ist am 26.07.2026 auf einem Pixel 7 passiert.
--
-- Gehoben wird künftig nur, wenn ein alter Client ohne Update falsche Daten
-- zeigt oder in eine Exception läuft — nicht routinemäßig zu jeder Migration.

-- Rangfolge allein nach Punkten (Issue #38, entschieden 2026-07-21).
--
-- `points_weight` gewichtet Punkte-Rang gegen Fahranteil-Rang; 1.0 heißt
-- „nur Punkte". Der Parameter selbst bleibt — er ist der Weg zurück, ohne
-- die Formel anzufassen.
--
-- Zwei Stellen, weil `settings` pro Gruppe eine Zeile trägt: Bestandsgruppen
-- brauchen ein UPDATE, neue Gruppen den geänderten Default im Trigger.
-- Nur die Dart-Vorgabe zu ändern hätte für keine einzige bestehende Gruppe
-- gewirkt — deren Zeile steht in der Datenbank und sticht sie.

update public.settings set value = 1.0 where key = 'points_weight';

create or replace function public.handle_new_group()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  new_handle text := split_part(new.email, '@', 1);
begin
  insert into public.groups (id, name, handle, status, is_admin)
  values (new.id,
          coalesce(nullif(new.raw_user_meta_data->>'group_name', ''), new_handle),
          new_handle, 'pending', false);
  insert into public.settings (group_id, key, value) values
    (new.id, 'commute_km', 30),
    (new.id, 'one_way_factor', 0.5),
    (new.id, 'electricity_price_per_kwh', 0.35),
    (new.id, 'diesel_price_per_liter', 1.70),
    (new.id, 'petrol_price_per_liter', 1.78),
    (new.id, 'points_weight', 1.0);
  return new;
end $$;

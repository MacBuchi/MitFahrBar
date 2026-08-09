-- Drei Antworten statt zwei auf eine abweichende Abfahrt (#210):
-- „egal" (Vorgabe), „ja unbedingt", „auf keinen Fall".
--
-- **`answer` ist nullable und hat KEINEN Default**, und beides ist der Kern
-- der Verträglichkeit, nicht Nachlässigkeit:
--
--   * Ein Client von vor v0.72.0 kennt die Spalte nicht und schreibt sie
--     folglich nicht mit. Sie bleibt dann NULL, und der neue Client liest die
--     Zeile über `accepted` — also genau mit der Bedeutung, die der alte
--     gemeint hat. Kein Verlust, kein Widerspruch.
--   * Mit `default 'dontcare'` ginge dagegen jede **Ablehnung** eines alten
--     Clients verloren: Die Zeile stünde als „egal" da, und der Ausschluss,
--     der jemanden vor einer 05:30-Abfahrt schützt, wirkte einfach nicht.
--   * Mit `default 'yes'` wäre es umgekehrt genauso falsch — eine Ablehnung
--     würde zum Pin auf genau das Auto, das die Person abgelehnt hat.
--
-- Deshalb NULL: „hat dazu nichts gesagt, frag `accepted`".
--
-- `accepted` bleibt bestehen und wird vom neuen Client mitgeschrieben. Sie auf
-- NULL zu öffnen wäre das sauberere Datenmodell gewesen, hätte aber die
-- Mindestversion gehoben (alte Clients lesen `json['accepted'] as bool` und
-- werfen bei NULL) — und damit jedes nicht aktualisierte Gerät auf den
-- Sperr-Schirm geworfen. Entscheidung der Gruppe am 09.08.2026.
alter table public.plan_seat_choices
  add column answer text
  constraint plan_seat_choices_answer_valid
    check (answer is null or answer in ('yes', 'no', 'dontcare'));

-- Bestandszeilen tragen die Bedeutung, die sie HEUTE haben: `accepted = true`
-- ist seit v0.67.0 ein Pin. Sie stattdessen auf „egal" zu setzen wäre keine
-- Migration, sondern eine stille Verhaltensänderung an laufenden Wochen.
--
-- Dass darunter auch Zeilen sind, die nur durch Wegtippen entstanden sind
-- (Opt-out, v0.70.0), lässt sich nicht mehr unterscheiden — die Ablage hat nie
-- festgehalten, wie das Ja zustande kam. Der Preis ist klein und läuft von
-- selbst aus: Die Zeilen gelten nur für die laufende Planwoche.
update public.plan_seat_choices
set answer = case when accepted then 'yes' else 'no' end
where answer is null;

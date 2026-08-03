/// trip_push.dart – Meldungen über geänderte und gelöschte Fahrten (#163).
///
/// Reines Dart, keine Uhr und kein Netz: `now` kommt von außen, das Ergebnis
/// sind fertige Korb-Zeilen. Dieselbe Linie wie `push_outbox.dart` daneben.
///
/// **Warum ein Diff und keine Haken am Editor.** Der Ausgangskorb ist seit
/// #132 ein *Zuhörer*: Wer an jeder Schreibstelle von Hand nachzieht,
/// vergisst irgendwann eine, und niemand findet es je. Hier gilt dasselbe —
/// gehört wird auf die fertige Fahrtenliste. Eine Fahrt kann aus dem Editor
/// kommen, aus dem Planer, aus dem CSV-Import oder aus einem zweiten Gerät;
/// der Diff sieht alle vier gleich.
///
/// **Drei Fälle, drei Antworten:**
///
///   - Eine Kennung ist in beiden Listen, der Inhalt unterscheidet sich →
///     Bearbeitung, Meldung an alte **und** neue Beteiligte.
///   - Eine Kennung fehlt in der neuen Liste → Löschung, Meldung an die
///     bisherigen Beteiligten.
///   - Eine Kennung ist neu → **keine Meldung.** Das Anlegen einer Fahrt
///     *ist* die Bestätigung des Tages (KONZEPT: „die Existenz einer Zeile in
///     `trips` am Tag ist die Bestätigung"), und wer daran beteiligt war, hat
///     es gerade selbst besprochen. Eine Meldung darüber wäre Lärm.
///
/// **Die ehrliche Grenze:** Diese Meldungen haben keinen stündlichen Boden.
/// `tool/notify.dart` rechnet den Plan-Korb neu und repariert damit, was ein
/// Gerät ohne Netz liegen ließ — einen *Diff* kann er nicht rekonstruieren,
/// dazu müsste er einen früheren Stand der Fahrten kennen. Stirbt der Tab
/// zwischen Speichern und Schreiben des Korbs, entfällt die Meldung. Das ist
/// der Preis dafür, dass die Fahrtenliste keine Änderungshistorie führt —
/// und er ist niedriger als eine zweite Wahrheit über Fahrten.
library;

import '../models/group_defaults.dart';
import '../models/person.dart';
import '../models/trip.dart';
import 'fairness.dart';
import 'push_digest.dart';
import 'push_outbox.dart';

/// Die Korb-Zeilen, die aus dem Übergang [previous] → [next] entstehen.
///
/// [suppressPersonId] ist, wer an diesem Gerät sitzt (#121): Wer die Fahrt
/// selbst geändert hat, braucht keine Meldung darüber. Best effort wie beim
/// Planer — ein Gerät ohne Zuordnung unterdrückt nichts.
List<OutboxEntry> tripChangeEntries({
  required List<Trip> previous,
  required List<Trip> next,
  required Map<String, Person> persons,
  required DateTime now,
  GroupDefaults defaults = const GroupDefaults(),
  String? suppressPersonId,
}) {
  final before = {for (final trip in previous) trip.id: trip};
  final after = {for (final trip in next) trip.id: trip};
  final entries = <OutboxEntry>[];

  for (final id in before.keys) {
    final old = before[id]!;
    final current = after[id];

    // Neu angelegte Fahrten stehen nicht in `before` — sie kommen hier also
    // gar nicht vorbei. Das ist der Fall „keine Meldung", und er ist durch
    // die Schleife über `before.keys` erledigt, nicht durch eine Bedingung.
    if (current != null && _same(old, current)) continue;

    final removed = current == null;
    final trip = current ?? old;
    final date = _dayOnly(trip.date);
    final recipients = <String>{
      ...old.participations.keys,
      ...?current?.participations.keys,
    }..removeWhere((id) => id == suppressPersonId || !persons.containsKey(id));
    if (recipients.isEmpty) continue;

    final title = composeTitle(date, PushKind.trip, now, removed: removed);
    // Der Digest hält zwei Schreibrunden desselben Zustands auseinander: Zwei
    // Geräte sehen dieselbe Änderung und schreiben dieselbe Zeile — bei
    // gleichem Inhalt lässt der Entprell-Trigger die Fälligkeit in Ruhe, es
    // geht also EINE Meldung raus statt zwei.
    final digest = pushHash('${trip.id}|${removed ? 'weg' : _state(trip)}');

    for (final personId in recipients) {
      entries.add(
        OutboxEntry(
          personId: personId,
          date: date,
          kind: 'trip',
          digest: digest,
          body: _body(
            trip,
            personId,
            persons,
            removed: removed,
            defaults: defaults,
          ),
          // Für eine Trip-Zeile wählt `push_due()` immer `title_change`;
          // die anderen Kopfzeilen sind Pflichtfelder der Tabelle und
          // tragen denselben Text, damit keine leere Zeile entsteht.
          titleEvening: title,
          titleChange: title,
        ),
      );
    }
  }

  return entries;
}

/// Der Text der Meldung.
///
/// Bei einer Bearbeitung übernimmt [composeBody] über einen synthetischen
/// bestätigten Tag — dadurch liest, wer herausgefallen ist, automatisch „Du
/// bist für diesen Tag nicht mehr eingetragen", und alle anderen bekommen
/// denselben Wortschatz wie im Banner und im Abend-Blick.
///
/// Zwei Fälle kommen ohne ihn aus: die Löschung (es gibt keinen Tag mehr zu
/// beschreiben) und die Fahrt **ohne Fahrer** — die entsteht nur beim
/// Excel-Import und stellt kein Auto; `composeBody` läse daraus für jeden ein
/// „nicht mehr eingetragen" und behauptete damit etwas Falsches.
String _body(
  Trip trip,
  String personId,
  Map<String, Person> persons, {
  required bool removed,
  required GroupDefaults defaults,
}) {
  if (removed) return 'Die Fahrt an diesem Tag wurde gelöscht.';
  if (trip.driverId == null) {
    return 'Die Fahrt an diesem Tag wurde geändert.';
  }
  return composeBody(_dayOf(trip), personId, persons, defaults: defaults);
}

/// Die Fahrt als bestätigter Plantag — die Form, die [composeBody] versteht.
PlannedDay _dayOf(Trip trip) {
  final full = <String>[];
  final oneWay = <String>[];
  for (final entry in trip.participations.entries) {
    switch (entry.value) {
      case ParticipationStatus.driver:
        break;
      case ParticipationStatus.passenger:
        full.add(entry.key);
      case ParticipationStatus.oneWay:
        oneWay.add(entry.key);
    }
  }
  full.sort();
  oneWay.sort();
  final driverId = trip.driverId!;
  return PlannedDay(
    date: _dayOnly(trip.date),
    availableIds: [driverId, ...full, ...oneWay]..sort(),
    oneWayIds: oneWay.toSet(),
    suggestedDriverIds: [driverId],
    cars: [
      PlannedCar(
        driverId: driverId,
        fullIds: full,
        oneWayIds: oneWay,
        tripId: trip.id,
      ),
    ],
    confirmed: true,
  );
}

/// Was an einer Fahrt eine Meldung wert ist: Tag und Beteiligung.
///
/// Die Notiz steht bewusst **nicht** drin. Sie erscheint in keiner Meldung —
/// eine Benachrichtigung über einen Text, den sie nicht zeigt, wäre eine
/// Aufforderung nachzusehen, wo nichts zu sehen ist.
String _state(Trip trip) {
  final ids = trip.participations.keys.toList()..sort();
  return '${_isoDay(trip.date)}|'
      '${[for (final id in ids) '$id:${trip.participations[id]!.name}'].join(',')}';
}

bool _same(Trip a, Trip b) => _state(a) == _state(b);

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _isoDay(DateTime value) {
  final day = _dayOnly(value);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

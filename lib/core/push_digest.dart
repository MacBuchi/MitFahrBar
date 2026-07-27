/// push_digest.dart – Wann geht welche Benachrichtigung an wen, und was steht
/// drin (Issue #101).
///
/// Reine Funktionen, kein Netz, keine Uhr: `now` kommt immer von außen. Das
/// ist dasselbe Muster wie `csv_export.dart` und `chart_data.dart` — die
/// Regeln bleiben mit `flutter test` prüfbar, und `tool/notify.dart` ist nur
/// noch die I/O-Schale drumherum.
///
/// **Der Fahrer-Vorschlag wird nirgends gespeichert.** Der Versand-Job
/// bekommt fertige [PlannedDay]s aus `planWeek` (also aus der echten
/// Fairness-Logik) und legt hier nur einen *Hash* des Tageszustands ab, um
/// beim nächsten Lauf zu erkennen, ob sich etwas geändert hat. Wer statt des
/// Hashes den Plan speichert, baut die zweite Wahrheit über den Tag.
///
/// **Zwei Abnehmer, ein Wortschatz** (seit #122): Neben `tool/notify.dart`
/// liest auch die Übersicht hier — das Banner „nächste Fahrt" nimmt
/// [composeGroupBody] und [dayLabel]. Der Wortlaut gehört deshalb hierher und
/// nicht ins Widget: Was das Handy meldet und was die App zeigt, darf nicht
/// auseinanderlaufen.
library;

import '../models/notification_prefs.dart';
import '../models/person.dart';
import 'fairness.dart';

/// Warum eine Nachricht rausgeht.
enum PushKind {
  /// Der Blick auf den Folgetag, einmal je Tag und Person.
  evening,

  /// Der Plan hat sich zwischen Abend-Push und Abfahrt geändert.
  change,
}

/// Eine bereits verschickte Nachricht — eine Zeile aus `push_log`.
class SentPush {
  const SentPush({
    required this.personId,
    required this.planDate,
    required this.kind,
    required this.digest,
    required this.sentAt,
  });

  final String personId;
  final DateTime planDate;
  final PushKind kind;
  final String digest;
  final DateTime sentAt;
}

/// Eine fällige Nachricht.
class DuePush {
  const DuePush({
    required this.personId,
    required this.planDate,
    required this.kind,
    required this.title,
    required this.body,
    required this.digest,
  });

  final String personId;
  final DateTime planDate;
  final PushKind kind;
  final String title;
  final String body;

  /// Der Tageszustand zum Zeitpunkt dieser Nachricht — gehört nach dem
  /// Versand in `push_log`.
  final String digest;

  @override
  String toString() => '$kind→$personId ${planDate.toIso8601String()} $digest';
}

/// Der Digest einer Person, die an dem Tag nicht (mehr) eingetragen ist.
///
/// Ein fester Wert statt eines Hashes, und das ist der Trick am Austrag:
/// Sobald jemand raus ist, ändert sich sein Digest nicht mehr, egal wie oft
/// die anderen den Tag noch umbauen. Er bekommt also **genau eine**
/// Austrags-Nachricht — und wieder eine, falls ihn jemand zurückträgt.
const String removedDigest = 'raus';

/// Der Tageszustand aus Sicht von [personId], als kurzer Hash.
///
/// Drin ist, was diese Person auf dem Planer sähe: wer dabei ist (und ob nur
/// eine Richtung), wer fährt, wie die Autos besetzt sind, und ob der Tag
/// schon eingetragen ist.
///
/// **Nicht drin sind die Punkte.** Die ändern sich bei jeder eingetragenen
/// Fahrt und lösten sonst Nachrichten aus, die niemanden interessieren.
String dayDigestFor(PlannedDay day, String personId) {
  if (!day.availableIds.contains(personId)) return removedDigest;

  final state = StringBuffer();
  for (final id in day.availableIds) {
    state
      ..write(id)
      ..write(day.oneWayIds.contains(id) ? ':w' : ':v')
      ..write('/');
  }
  state.write('|');
  for (final car in day.cars) {
    state
      ..write(car.driverId)
      ..write('(')
      ..write(car.fullIds.join(','))
      ..write(';')
      ..write(car.oneWayIds.join(','))
      ..write(')');
  }
  state.write(day.confirmed ? '|x' : '|-');
  return _hash(state.toString());
}

/// Alle Nachrichten, die zu [now] fällig sind.
///
/// [week] kommt aus `planWeek`, [prefs] und [sent] aus der Datenbank. Wer
/// keine Zeile in [prefs] hat, bekommt nichts — das Einschalten im Screen
/// legt sie an, und damit gibt es genau eine Wahrheit darüber, wer etwas
/// bekommt.
///
/// **Eine Änderungs-Meldung setzt den Abend-Push voraus** (unten: der
/// `evening == null`-Zweig endet immer mit `continue`). Ohne ihn wäre sie
/// die erste Nachricht des Tages und ohne Bezug — mit abgeschaltetem
/// Abend-Blick ist `changesEnabled` deshalb wirkungslos.
/// `features/notifications/notifications_screen.dart` spiegelt genau das,
/// indem es den Änderungs-Schalter dann sperrt; wer die Regel hier ändert,
/// ändert sie dort mit.
List<DuePush> dueMessages({
  required List<PlannedDay> week,
  required Map<String, NotificationPrefs> prefs,
  required List<SentPush> sent,
  required Map<String, Person> persons,
  required DateTime now,
  Duration changeCooldown = const Duration(minutes: 30),
}) {
  final index = <String, SentPush>{
    for (final s in sent) _logKey(s.personId, s.planDate, s.kind): s,
  };
  final due = <DuePush>[];

  for (final day in week) {
    // Ein eingetragener Tag ist gelaufen: Es gibt nichts mehr zu planen und
    // nichts mehr zu melden.
    if (day.confirmed) continue;

    final date = _dayOnly(day.date);

    // Kandidaten sind die Anwesenden — plus die, die schon einen Abend-Push
    // für den Tag haben. Sonst erführe niemand, dass er ausgetragen wurde.
    final candidates = <String>{
      ...day.availableIds,
      for (final s in sent)
        if (s.kind == PushKind.evening && _dayOnly(s.planDate) == date)
          s.personId,
    };

    for (final personId in candidates) {
      final pref = prefs[personId];
      if (pref == null) continue;

      // Das Fenster: vom Abend davor bis zur Abfahrt. Gesendet wird
      // „sobald fällig", nicht „um genau" — ein verspäteter Lauf holt also
      // nach. Die Abfahrt ist der harte Riegel dagegen, dass ein Ausfall
      // jemanden nachts weckt.
      final opens = pref.eveningTime.on(date.subtract(const Duration(days: 1)));
      final closes = pref.departureTime.on(date);
      if (now.isBefore(opens) || !now.isBefore(closes)) continue;

      final digest = dayDigestFor(day, personId);
      final evening = index[_logKey(personId, date, PushKind.evening)];
      final change = index[_logKey(personId, date, PushKind.change)];

      if (evening == null) {
        // Der Abend-Push geht nur an Anwesende. Wer gar nicht eingetragen
        // ist, bekommt auch kein „du bist nicht dabei" — das wäre Lärm.
        if (!day.availableIds.contains(personId)) continue;
        if (!pref.eveningEnabled) continue;
        due.add(
          DuePush(
            personId: personId,
            planDate: date,
            kind: PushKind.evening,
            title: composeTitle(date, PushKind.evening, now, removed: false),
            body: composeBody(day, personId, persons),
            digest: digest,
          ),
        );
        continue;
      }

      if (!pref.changesEnabled) continue;
      final lastDigest = change?.digest ?? evening.digest;
      if (digest == lastDigest) continue;
      // Mindestabstand gegen Nachnagen, wenn jemand länger im Planer
      // herumräumt. Der 10-Minuten-Takt des Jobs entprellt zusätzlich,
      // weil er immer nur den fertigen Zustand sieht.
      if (change != null && now.difference(change.sentAt) < changeCooldown) {
        continue;
      }
      due.add(
        DuePush(
          personId: personId,
          planDate: date,
          kind: PushKind.change,
          title: composeTitle(
            date,
            PushKind.change,
            now,
            removed: digest == removedDigest,
          ),
          body: composeBody(day, personId, persons),
          digest: digest,
        ),
      );
    }
  }

  return due;
}

/// Die Kopfzeile der Nachricht.
String composeTitle(
  DateTime date,
  PushKind kind,
  DateTime now, {
  required bool removed,
}) {
  final label = dayLabel(date, now);
  return switch ((kind, removed)) {
    (PushKind.evening, _) => label,
    (PushKind.change, true) => 'Ausgetragen · $label',
    (PushKind.change, false) => 'Änderung · $label',
  };
}

/// Der Text der Nachricht — was diese Person über den Tag wissen will.
String composeBody(
  PlannedDay day,
  String personId,
  Map<String, Person> persons,
) {
  if (!day.availableIds.contains(personId)) {
    return 'Du bist für diesen Tag nicht mehr eingetragen.';
  }

  final parts = <String>[];
  final myCar = _carOf(day, personId);

  if (day.cars.isEmpty) {
    final allOneWay =
        day.availableIds.isNotEmpty &&
        day.oneWayIds.length == day.availableIds.length;
    parts.add(
      allOneWay
          ? 'Kein Fahrer möglich — alle nur eine Richtung'
          : 'Kein Fahrer',
    );
    parts.add('${day.availableIds.length} dabei');
  } else if (myCar == null) {
    // Sollte nicht vorkommen (planWeek teilt alle Anwesenden zu), aber ein
    // stiller Absturz im Versand-Job wäre der schlechtere Ausgang.
    parts.add(_driverPhrase(day.driverIds, persons));
    parts.add('${day.availableIds.length} dabei');
  } else if (myCar.driverId == personId) {
    parts.add('Du fährst');
    final riders = [...myCar.fullIds, ...myCar.oneWayIds];
    parts.add(
      riders.isEmpty
          ? 'niemand mitzunehmen'
          : 'dabei: ${_names(riders, persons)}',
    );
  } else {
    parts.add('${_name(myCar.driverId, persons)} fährt');
    final others = [
      ...myCar.fullIds,
      ...myCar.oneWayIds,
    ].where((id) => id != personId).toList();
    if (others.isNotEmpty) parts.add('dabei: ${_names(others, persons)}');
    if (day.oneWayIds.contains(personId)) parts.add('du nur eine Richtung');
  }

  if (day.cars.length > 1) parts.add('${day.cars.length} Autos');
  return parts.join(' · ');
}

/// Derselbe Tag, aber aus Sicht der ganzen Gruppe — für die Übersicht (#122),
/// wo niemand „du" ist.
///
/// [composeBody] braucht eine `personId`, und die kennt nur ein Gerät mit
/// Push-Zuordnung: im Browser und auf nicht zugeordneten Geräten gibt es sie
/// nicht. Diese Fassung nennt den Fahrer beim Namen und zählt alle übrigen
/// Anwesenden als Mitfahrer — sie teilt sich [_driverPhrase] und [_names] mit
/// der persönlichen, damit beide dieselbe Sprache sprechen.
String composeGroupBody(PlannedDay day, Map<String, Person> persons) {
  final parts = <String>[];

  if (day.cars.isEmpty) {
    final allOneWay =
        day.availableIds.isNotEmpty &&
        day.oneWayIds.length == day.availableIds.length;
    parts.add(
      allOneWay
          ? 'Kein Fahrer möglich — alle nur eine Richtung'
          : 'Kein Fahrer',
    );
    parts.add('${day.availableIds.length} dabei');
  } else {
    parts.add(_driverPhrase(day.driverIds, persons));
    // Alle Anwesenden außer den Fahrern — bei mehreren Autos ist „dabei" die
    // Gruppe des Tages, nicht die eines Autos.
    final riders = day.availableIds
        .where((id) => !day.driverIds.contains(id))
        .toList();
    parts.add(
      riders.isEmpty
          ? 'niemand mitzunehmen'
          : 'dabei: ${_names(riders, persons)}',
    );
  }

  if (day.cars.length > 1) parts.add('${day.cars.length} Autos');
  return parts.join(' · ');
}

/// `Morgen (Di, 28.07.)` — bezogen auf [now], damit ein nachgeholter Lauf am
/// Morgen nicht „morgen" schreibt, wenn der Tag längst da ist.
String dayLabel(DateTime date, DateTime now) {
  final target = _dayOnly(date);
  final today = _dayOnly(now);
  final stamp =
      '${_weekdays[target.weekday - 1]}, '
      '${target.day.toString().padLeft(2, '0')}.'
      '${target.month.toString().padLeft(2, '0')}.';
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Heute ($stamp)';
  if (diff == 1) return 'Morgen ($stamp)';
  return stamp;
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _logKey(String personId, DateTime date, PushKind kind) {
  final day = _dayOnly(date);
  return '$personId|${day.year}-${day.month}-${day.day}|${kind.name}';
}

PlannedCar? _carOf(PlannedDay day, String personId) {
  for (final car in day.cars) {
    if (car.driverId == personId ||
        car.fullIds.contains(personId) ||
        car.oneWayIds.contains(personId)) {
      return car;
    }
  }
  return null;
}

String _name(String id, Map<String, Person> persons) =>
    persons[id]?.name ?? 'jemand';

/// Bis zu vier Namen, alphabetisch; der Rest als `+n`. Eine Benachrichtigung
/// wird ohnehin abgeschnitten — lieber lesbar kurz als vollständig unlesbar.
String _names(Iterable<String> ids, Map<String, Person> persons) {
  final names = ids.map((id) => _name(id, persons)).toList()..sort();
  if (names.length <= 4) return names.join(', ');
  return '${names.take(4).join(', ')} +${names.length - 4}';
}

String _driverPhrase(List<String> driverIds, Map<String, Person> persons) {
  if (driverIds.isEmpty) return 'Kein Fahrer';
  final names = driverIds.map((id) => _name(id, persons)).toList()..sort();
  if (names.length == 1) return '${names.first} fährt';
  return '${names.join(' und ')} fahren';
}

/// djb2 mit 32-Bit-Maske, als Hex.
///
/// Bewusst kein 64-Bit-FNV und keine Krypto-Abhängigkeit: `int` ist im
/// Web-Build eine JS-Zahl mit 53 Bit Genauigkeit. Bei 64 Bit lieferten VM
/// und Web still **verschiedene** Digests, und das fiele erst auf, wenn
/// jemand den Digest später auch im Client berechnet. `hash * 33` bleibt
/// unter 2^37 und ist damit auf beiden Zielen exakt.
///
/// 32 Bit reichen: Verglichen werden immer nur zwei konkrete Zustände
/// desselben Tages, nicht eine große Menge gegeneinander.
String _hash(String input) {
  var hash = 5381;
  for (final unit in input.codeUnits) {
    hash = ((hash * 33) ^ unit) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

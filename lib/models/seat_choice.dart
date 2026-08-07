/// seat_choice.dart – Das Einverständnis eines Mitfahrers mit einer Abfahrt
/// (#189, Stufe B2).
///
/// **Keine freie Auto-Wahl, sondern eine Zustimmung.** Der Wunsch im Issue
/// hieß „Mitfahrer sollten ihr Auto wählen können"; gebaut ist der engere und
/// tragfähigere Fall, denn der Anlass ist ein anderer: Seit #183 kann ein
/// Fahrer die Abfahrt SEINES Autos verschieben. Wer zu 07:30 zugesagt hat,
/// darf nicht stillschweigend auf 05:30 gezogen werden.
///
/// Zwei Werte, mit sehr verschiedener Wirkung:
///
/// - [accepted] `true` — **Pin.** `planWeek` setzt die Person in genau dieses
///   Auto, solange dort ein Platz frei ist.
/// - [accepted] `false` — **Ausschluss.** Die Person wird nicht in dieses
///   Auto gesetzt. Reichen die übrigen nicht, entsteht dadurch ein weiteres —
///   und genau dafür gibt es den Wert.
///
/// **Reines Dart ohne Flutter-Import**, wie alles unter `models/`:
/// `tool/notify.dart` importiert die Fairness-Kette und läuft auf der
/// Dart-VM ohne Flutter.
///
/// [personId] ist wie überall im Planer **kein Identitätsnachweis** — jeder
/// darf für jeden entscheiden („eine Gruppe = ein Login"). Die
/// Geräte-Zuordnung aus #121 belegt das Feld nur vor.
library;

import 'group_defaults.dart';

class SeatChoice {
  const SeatChoice({
    required this.date,
    required this.personId,
    required this.driverId,
    required this.accepted,
    required this.terms,
    required this.decidedAt,
  });

  /// Kalendertag (Zeitanteil 00:00 lokal).
  final DateTime date;

  /// Wer entschieden hat.
  final String personId;

  /// Über wessen Auto. Ein Auto existiert nur als „diese Person fährt an
  /// diesem Tag" — dieselbe Begründung wie bei `plan_car_defaults`.
  final String driverId;

  /// `true` = Pin, `false` = Ausschluss.
  final bool accepted;

  /// Die Bedingungen, zu denen entschieden wurde — [termsOf].
  ///
  /// **Ohne dieses Feld wäre eine Zusage ein Blankoscheck.** Stimmt es nicht
  /// mehr mit den aktuellen Bedingungen überein, ist die Entscheidung
  /// veraltet und wirkt nicht ([isCurrentFor]); der Client fragt dann neu.
  final String terms;

  /// Wann entschieden wurde — **entscheidet bei Überfüllung**: Wollen fünf
  /// Leute in einen Vierer, bleibt, wer zuerst gepinnt hat. Das ist der
  /// einzige Zweck des Feldes, es ist kein Protokolleintrag.
  final DateTime decidedAt;

  /// Ob diese Entscheidung zu den aktuell geltenden [current] passt.
  bool isCurrentFor(String current) => terms == current;

  factory SeatChoice.fromJson(Map<String, dynamic> json) => SeatChoice(
    date: DateTime.parse(json['plan_date'] as String),
    personId: json['person_id'] as String,
    driverId: json['driver_id'] as String,
    accepted: json['accepted'] as bool,
    terms: json['terms'] as String? ?? '',
    decidedAt: DateTime.parse(json['decided_at'] as String),
  );

  /// Nur die Felder, die ein Client setzen darf. `group_id` fehlt bewusst:
  /// Den Wert liefert der Spalten-Default `auth.uid()`.
  ///
  /// `decided_at` steht **doch** darin — anders als bei [PlanNote.toJson],
  /// und der Unterschied ist Absicht: Der Wert geht in die Plan-Rechnung ein
  /// („wer zuerst gepinnt hat"). Beim erneuten Speichern derselben
  /// Entscheidung muss er deshalb erhalten bleiben und darf nicht auf `now()`
  /// springen — sonst verlöre ein Pin bei jedem Umschreiben seinen Vorrang.
  Map<String, dynamic> toJson() => {
    'plan_date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'person_id': personId,
    'driver_id': driverId,
    'accepted': accepted,
    'terms': terms,
    'decided_at': decidedAt.toUtc().toIso8601String(),
  };
}

/// Die Bedingungen eines Autos als kanonischer Text — `hh:mm|hh:mm|Ort`.
///
/// **Eine Stelle, damit Speichern und Vergleichen dieselbe Zeichenkette
/// erzeugen.** Zwei Schreibweisen für dieselbe Abfahrt ließen jede Zusage
/// sofort veralten, und das Ergebnis wäre eine Rückfrage bei jedem Aufbau des
/// Plans.
///
/// Leerer Text heißt „die festen Vorgaben der Gruppe gelten" — und das ist
/// bewusst derselbe Wert wie für eine Abweichung, die alle Felder leer lässt:
/// Beide bedeuten für den Mitfahrer dasselbe, nämlich nichts Besonderes.
String termsOf(GroupDefaults? deviation) {
  if (deviation == null || deviation.isEmpty) return '';
  return [
    deviation.outboundTime?.format() ?? '',
    deviation.returnTime?.format() ?? '',
    deviation.meetingPoint ?? '',
  ].join('|');
}

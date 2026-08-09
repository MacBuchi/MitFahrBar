/// seat_choice.dart – Das Einverständnis eines Mitfahrers mit einer Abfahrt
/// (#189, Stufe B2).
///
/// **Keine freie Auto-Wahl, sondern eine Zustimmung.** Der Wunsch im Issue
/// hieß „Mitfahrer sollten ihr Auto wählen können"; gebaut ist der engere und
/// tragfähigere Fall, denn der Anlass ist ein anderer: Seit #183 kann ein
/// Fahrer die Abfahrt SEINES Autos verschieben. Wer zu 07:30 zugesagt hat,
/// darf nicht stillschweigend auf 05:30 gezogen werden.
///
/// **Seit v0.72.0 drei Werte statt zwei** (#210), siehe [SeatAnswer]. Der
/// dritte („egal") ist kein Beiwerk: Er ist die Vorgabe und trotzdem eine
/// *abgelegte* Entscheidung. Als Abwesenheit einer Zeile umgesetzt fände die
/// nachträgliche Rückfrage (#200) nichts Veraltetes, und wer zu 06:00 „egal"
/// gesagt hat, würde bei 04:00 stillschweigend mitgezogen — genau das Loch,
/// das #200 geschlossen hat.
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

/// Wozu jemand ja, nein oder nichts gesagt hat (#210).
///
/// Die drei sind **nicht** symmetrisch, und die Etiketten verschweigen das
/// fast: [no] ist eine *Bedingung* — „zu diesen Bedingungen nicht" heißt, dass
/// jemand anderes fahren muss, notfalls in einem zusätzlichen Auto. [yes] ist
/// nur eine *Bevorzugung*: Ist das Wunsch-Auto voll, fällt die Person in die
/// normale Verteilung statt ein zweites Sonderzeit-Auto zu erzwingen (Gruppe,
/// 09.08.2026). [indifferent] überlässt den Platz der Verteilung.
enum SeatAnswer {
  /// „Egal" — die Vorgabe. Wirkt weder als Pin noch als Ausschluss, wird aber
  /// **mit Bedingungen abgelegt**, damit eine spätere Verschiebung als
  /// Änderung erkannt wird (#200).
  indifferent('dontcare'),

  /// „Ja unbedingt" — Bevorzugung für dieses Auto, kein Anspruch darauf.
  yes('yes'),

  /// „Auf keinen Fall" — Ausschluss. Kann ein weiteres Auto erzwingen.
  no('no');

  const SeatAnswer(this.wire);

  /// Der Wert in `plan_seat_choices.answer`.
  final String wire;

  /// Tolerant wie [Group.statusFrom]: Ein unbekannter Wert gilt als „egal"
  /// und nicht als Ausnahme. Ein `byName` würde **werfen**, und der Fehler
  /// landete mitten in der Plan-Rechnung — jede künftige Erweiterung des
  /// Wertevorrats wäre damit ein Release-Zwang.
  static SeatAnswer from(Object? value) => switch (value) {
    'yes' => SeatAnswer.yes,
    'no' => SeatAnswer.no,
    _ => SeatAnswer.indifferent,
  };
}

class SeatChoice {
  const SeatChoice({
    required this.date,
    required this.personId,
    required this.driverId,
    required this.answer,
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

  /// Was entschieden wurde (#210). Die Wahrheit steht in der Spalte `answer`.
  final SeatAnswer answer;

  /// Die Mitschrift für Clients von vor v0.72.0 — **kein zweiter Wert**.
  ///
  /// Sie kennen nur `accepted` und würden eine `null` nicht überleben
  /// (`json['accepted'] as bool` wirft). Deshalb bleibt die Spalte stehen und
  /// wird mitgeschrieben, statt sie auf NULL zu öffnen; das hätte die
  /// Mindestversion gehoben und jedes nicht aktualisierte Gerät auf den
  /// Sperr-Schirm geworfen (Entscheidung der Gruppe, 09.08.2026).
  ///
  /// **Genau ein Schreiber, genau eine Ableitung** — hier. Wer sie irgendwo
  /// anders setzt, macht aus der Mitschrift die zweite Wahrheit, vor der
  /// `CLAUDE.md` warnt.
  ///
  /// Der bewusst hingenommene Preis: Ein alter Client liest „egal" als
  /// Zusage, pinnt also fester als gewollt. Er sieht dabei nie eine falsche
  /// Zeit — nur eine Verteilung, die weniger nachgibt.
  bool get accepted => answer != SeatAnswer.no;

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
    // `answer` ist die Wahrheit. Fehlt die Spalte im Ergebnis oder steht dort
    // nichts, ist die Zeile von einem alten Client — dann trägt `accepted`
    // die Aussage, und mehr als ja/nein wusste er ohnehin nicht.
    answer: json.containsKey('answer') && json['answer'] != null
        ? SeatAnswer.from(json['answer'])
        : (json['accepted'] as bool? ?? false)
        ? SeatAnswer.yes
        : SeatAnswer.no,
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
    'answer': answer.wire,
    // Die Mitschrift reist im selben Upsert mit. Ließe man sie aus, stünde
    // für einen alten Client der Stand von vorhin — dieselbe Lehre wie bei
    // `title_out` (#164).
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

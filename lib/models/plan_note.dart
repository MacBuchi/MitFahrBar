/// plan_note.dart – Eine Anmerkung zu einem geplanten Fahrtag (Issue #127).
///
/// „Komme erst um 9." Mehr ist es nicht und mehr soll es nicht werden: kein
/// Thread, keine Antwort, kein Gelesen-Status — KONZEPT.md §1 zieht die
/// Grenze („Kommunikation bleibt in WhatsApp") und sie gilt weiter.
///
/// **Reines Dart ohne Flutter-Import**, wie alles unter `models/`: Der
/// Versand-Job `tool/notify.dart` importiert diese Datei, und der läuft auf
/// der Dart-VM ohne Flutter.
///
/// [personId] ist der Verfasser und **kein Identitätsnachweis** — jeder kann
/// für jeden schreiben, genau wie im Planer jeder für jeden einträgt („eine
/// Gruppe = ein Login"). Die Geräte-Zuordnung aus #121 belegt das Feld nur
/// vor.
library;

class PlanNote {
  const PlanNote({
    required this.id,
    required this.date,
    required this.personId,
    required this.body,
    required this.createdAt,
  });

  final String id;

  /// Kalendertag, zu dem die Anmerkung gehört (Zeitanteil 00:00 lokal).
  final DateTime date;

  final String personId;
  final String body;
  final DateTime createdAt;

  factory PlanNote.fromJson(Map<String, dynamic> json) => PlanNote(
    id: json['id'] as String,
    date: DateTime.parse(json['plan_date'] as String),
    personId: json['person_id'] as String,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  /// Nur die Felder, die ein Client setzen darf. `group_id` fehlt bewusst:
  /// Den Wert liefert der Spalten-Default `auth.uid()` — stünde er in der
  /// Nutzlast, könnte ein Client ihn setzen. `id` und `created_at` vergibt
  /// die Datenbank.
  Map<String, dynamic> toJson() => {
    'plan_date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'person_id': personId,
    'body': body,
  };
}

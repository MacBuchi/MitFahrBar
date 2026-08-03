/// Benachrichtigungs-Einstellungen einer Person (Issue #101).
///
/// Bewusst **pro Person**, nicht pro Gerät: Wer Handy und Laptop registriert
/// hat, soll nicht zwei Uhrzeiten pflegen. Alle Zeiten sind Europe/Berlin —
/// eine Fahrgemeinschaft fährt an einem Ort zur Arbeit, eine Zeitzone je
/// Person wäre Aufwand ohne Nutzen.
library;

/// Eine Uhrzeit ohne Datum — das Gegenstück zur Postgres-Spalte `time`.
///
/// Nicht `TimeOfDay` aus Material: Diese Datei muss reines Dart bleiben,
/// damit `tool/notify.dart` sie ohne Flutter-Engine benutzen kann.
class DayTime implements Comparable<DayTime> {
  const DayTime(this.hour, this.minute);

  /// Aus einer Postgres-`time`-Spalte: `21:00`, `21:00:00` oder mit Zone.
  /// Sekunden und Zone werden verworfen — die Auflösung ist eine Minute.
  factory DayTime.parse(String value) {
    final parts = value.trim().split(':');
    if (parts.length < 2) {
      throw FormatException('Keine Uhrzeit: $value');
    }
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1].substring(0, 2));
    if (hour == null || minute == null) {
      throw FormatException('Keine Uhrzeit: $value');
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw FormatException('Uhrzeit außerhalb des Tages: $value');
    }
    return DayTime(hour, minute);
  }

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  /// `21:00` — die Form, die auch Postgres annimmt.
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Diese Uhrzeit an einem konkreten Tag.
  DateTime on(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  @override
  int compareTo(DayTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  @override
  bool operator ==(Object other) =>
      other is DayTime && other.hour == hour && other.minute == minute;

  @override
  int get hashCode => minutesOfDay;

  @override
  String toString() => format();
}

/// Wann eine Person benachrichtigt werden will.
///
/// **Keine Zeile in der Datenbank = keine Benachrichtigungen.** Deshalb gibt
/// es hier keine „Vorgabe für Fehlende" — [NotificationPrefs.initial] ist
/// ausschließlich die Vorbelegung des Formulars beim Einschalten. Sie muss
/// mit den DB-Defaults in `20260726100000_push_notifications.sql`
/// übereinstimmen; `test/push_digest_test.dart` nagelt das fest.
class NotificationPrefs {
  const NotificationPrefs({
    required this.personId,
    required this.eveningEnabled,
    required this.eveningTime,
    required this.departureTime,
    required this.changesEnabled,
    this.remindersEnabled = false,
    this.reminderLeadMinutes = defaultReminderLead,
  });

  /// Vorbelegung beim Einschalten: Abend-Push um 21 Uhr, Fenster bis 7:30.
  ///
  /// Die Abfahrts-Erinnerung (#164) ist hier **aus**, und das ist keine
  /// Vorsicht, sondern die Entscheidung: Sie meldet sich an einem Tag, an dem
  /// nichts passiert ist, und wer das nicht will, soll es nicht einmal
  /// abschalten müssen. Der Wert muss mit dem DB-Default übereinstimmen —
  /// `test/push_digest_test.dart` nagelt beide zusammen.
  factory NotificationPrefs.initial(String personId) => NotificationPrefs(
    personId: personId,
    eveningEnabled: true,
    eveningTime: const DayTime(21, 0),
    departureTime: const DayTime(7, 30),
    changesEnabled: true,
  );

  factory NotificationPrefs.fromJson(Map<String, Object?> json) =>
      NotificationPrefs(
        personId: json['person_id'] as String,
        eveningEnabled: json['evening_enabled'] as bool? ?? true,
        eveningTime: DayTime.parse(json['evening_time'] as String),
        departureTime: DayTime.parse(json['departure_time'] as String),
        changesEnabled: json['changes_enabled'] as bool? ?? true,
        remindersEnabled: json['reminders_enabled'] as bool? ?? false,
        reminderLeadMinutes:
            (json['reminder_lead_minutes'] as num?)?.toInt() ??
            defaultReminderLead,
      );

  final String personId;
  final bool eveningEnabled;

  /// Wann der Blick auf den Folgetag kommt.
  final DayTime eveningTime;

  /// Ende des Änderungs-Fensters am Tag selbst. Danach nützt keine Nachricht
  /// mehr — und ein nachgeholter Lauf weckt niemanden mitten in der Nacht.
  final DayTime departureTime;

  final bool changesEnabled;

  /// Kurz vor der Abfahrt erinnern (#164) — **Opt-in**.
  final bool remindersEnabled;

  /// Wie viele Minuten vor der Gruppenzeit. Ein Wert für beide Richtungen:
  /// Wer morgens fünf Minuten braucht, braucht sie abends auch, und zwei
  /// Regler für dieselbe Frage sind ein Regler zu viel.
  final int reminderLeadMinutes;

  /// Schaltet die Person überhaupt etwas ein?
  bool get anyEnabled => eveningEnabled || changesEnabled || remindersEnabled;

  Map<String, Object?> toJson() => {
    'person_id': personId,
    'evening_enabled': eveningEnabled,
    'evening_time': eveningTime.format(),
    'departure_time': departureTime.format(),
    'changes_enabled': changesEnabled,
    'reminders_enabled': remindersEnabled,
    'reminder_lead_minutes': reminderLeadMinutes,
  };

  NotificationPrefs copyWith({
    bool? eveningEnabled,
    DayTime? eveningTime,
    DayTime? departureTime,
    bool? changesEnabled,
    bool? remindersEnabled,
    int? reminderLeadMinutes,
  }) => NotificationPrefs(
    personId: personId,
    eveningEnabled: eveningEnabled ?? this.eveningEnabled,
    eveningTime: eveningTime ?? this.eveningTime,
    departureTime: departureTime ?? this.departureTime,
    changesEnabled: changesEnabled ?? this.changesEnabled,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    reminderLeadMinutes: reminderLeadMinutes ?? this.reminderLeadMinutes,
  );
}

/// Vorlauf der Abfahrts-Erinnerung in Minuten (#164).
///
/// Fünfzehn Minuten: genug, um die Jacke zu holen, zu kurz, um es bis zur
/// Abfahrt wieder zu vergessen. Muss mit dem DB-Default übereinstimmen.
const int defaultReminderLead = 15;

/// Die wählbaren Vorläufe im Benachrichtigungs-Screen.
const List<int> reminderLeadChoices = [5, 10, 15, 20, 30, 45, 60];

/// Die festen Vorgaben einer Gruppe: Abfahrt hin, Abfahrt zurück,
/// Treffpunkt (Issue #139).
///
/// **Nichts davon berührt die Punkte.** Es sind Angaben über die Fahrt, nicht
/// über ihre Bewertung — dieselbe Klasse wie eine Anmerkung am Plantag (#127),
/// nur eben dauerhaft statt für einen Tag. Sie erscheinen im Banner und in der
/// Benachrichtigung und sonst nirgends; `fairness.dart` und `computeStats`
/// sehen sie nie.
///
/// Reines Dart ohne Flutter-Import: `tool/notify.dart` liest die Vorgaben für
/// seine Texte, und der Job läuft ohne Flutter-Engine.
library;

import 'notification_prefs.dart';

class GroupDefaults {
  const GroupDefaults({this.outboundTime, this.returnTime, this.meetingPoint});

  /// Aus einer Zeile `group_defaults` — oder aus `null`, wenn es keine gibt.
  ///
  /// Unlesbare Werte werden zu `null` statt zu einer Ausnahme: Dieselbe Linie
  /// wie `Group.statusFrom` und `PriceSeries.fromKey` — ein künftiger oder
  /// kaputter Wert in der Datenbank darf keinen Screen sprengen, schon gar
  /// nicht das Banner der Übersicht.
  factory GroupDefaults.fromJson(Map<String, Object?>? json) {
    if (json == null) return const GroupDefaults();
    final point = (json['meeting_point'] as String?)?.trim();
    return GroupDefaults(
      outboundTime: _time(json['outbound_time']),
      returnTime: _time(json['return_time']),
      meetingPoint: point == null || point.isEmpty ? null : point,
    );
  }

  static DayTime? _time(Object? value) {
    if (value is! String) return null;
    try {
      return DayTime.parse(value);
    } on FormatException {
      return null;
    }
  }

  /// Wann es losgeht. `null` = nicht gepflegt.
  final DayTime? outboundTime;

  /// Wann es zurückgeht.
  final DayTime? returnTime;

  /// Wo man sich trifft, in den Worten der Gruppe.
  final String? meetingPoint;

  /// Nichts gepflegt — dann sagen Banner und Benachrichtigung kein Wort davon.
  bool get isEmpty =>
      outboundTime == null && returnTime == null && meetingPoint == null;

  /// Die Felder für einen Upsert. Nicht gesetzte Werte gehen als `null` mit
  /// und **löschen** damit einen alten Eintrag — genau deshalb gibt es hier
  /// bewusst kein `copyWith`: Der Screen baut die Vorgaben beim Speichern
  /// frisch aus seinen Feldern, sonst ließe sich eine Zeit nie wieder leeren.
  Map<String, Object?> toJson() => {
    'outbound_time': outboundTime?.format(),
    'return_time': returnTime?.format(),
    'meeting_point': meetingPoint,
  };

  @override
  bool operator ==(Object other) =>
      other is GroupDefaults &&
      other.outboundTime == outboundTime &&
      other.returnTime == returnTime &&
      other.meetingPoint == meetingPoint;

  @override
  int get hashCode => Object.hash(outboundTime, returnTime, meetingPoint);

  @override
  String toString() =>
      'GroupDefaults(${outboundTime?.format()}, ${returnTime?.format()}, '
      '$meetingPoint)';
}

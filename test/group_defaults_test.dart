/// group_defaults_test.dart – Die festen Vorgaben der Gruppe (Issue #139).
///
/// Der Inhalt dieses Tests ist die Toleranz beim Lesen und die Strenge beim
/// Schreiben: Ein kaputter Wert in der Datenbank darf keinen Screen sprengen,
/// ein geleertes Feld muss den alten Wert wirklich löschen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/models/group_defaults.dart';
import 'package:mitfahrbar/models/notification_prefs.dart';

void main() {
  test('keine Zeile heißt: nichts gepflegt', () {
    expect(GroupDefaults.fromJson(null).isEmpty, isTrue);
    expect(GroupDefaults.fromJson(const {}).isEmpty, isTrue);
  });

  test('Postgres liefert `time` mit Sekunden — die fallen weg', () {
    final loaded = GroupDefaults.fromJson(const {
      'outbound_time': '07:15:00',
      'return_time': '16:30:00',
      'meeting_point': 'Parkplatz Rathaus',
    });
    expect(loaded.outboundTime, const DayTime(7, 15));
    expect(loaded.returnTime, const DayTime(16, 30));
    expect(loaded.meetingPoint, 'Parkplatz Rathaus');
    expect(loaded.isEmpty, isFalse);
  });

  test('ein unlesbarer Wert wird zu null, nicht zu einer Ausnahme', () {
    // Dieselbe Linie wie `Group.statusFrom` und `PriceSeries.fromKey`: Ein
    // künftiger oder kaputter Wert in der Datenbank darf keinen Screen
    // sprengen — und dieser hier hinge am Banner der Übersicht.
    final loaded = GroupDefaults.fromJson(const {
      'outbound_time': 'irgendwann',
      'return_time': 42,
    });
    expect(loaded.outboundTime, isNull);
    expect(loaded.returnTime, isNull);
  });

  test('ein Treffpunkt aus Leerzeichen gilt als nicht gepflegt', () {
    final loaded = GroupDefaults.fromJson(const {'meeting_point': '   '});
    expect(loaded.meetingPoint, isNull);
    expect(loaded.isEmpty, isTrue);
  });

  test('nicht gesetzte Werte gehen als null mit raus und löschen damit', () {
    // Genau deshalb gibt es kein copyWith: Der Screen baut die Vorgaben beim
    // Speichern frisch. Fehlte hier ein Schlüssel, ließe der Upsert den alten
    // Wert stehen, und eine einmal gesetzte Uhrzeit wäre nie wieder
    // loszuwerden.
    const cleared = GroupDefaults(returnTime: DayTime(16, 30));
    expect(cleared.toJson(), {
      'outbound_time': null,
      'return_time': '16:30',
      'meeting_point': null,
    });
  });
}

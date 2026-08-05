/// notification_health_test.dart – Was blockiert wirklich? (#180)
///
/// Der Fall, der diese Datei erzwungen hat: Am 05.08.2026 stand in
/// `push_log` beides als verschickt, FCM hatte `ok` gemeldet — und auf dem
/// Gerät kam nichts an, weil die Berechtigung aus war (#175). Jede Achse
/// hier kann das allein auslösen; deshalb wird jede einzeln festgenagelt.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/notification_health.dart';

/// Der unauffällige Zustand: alles erlaubt, Kanal hörbar, kein „Nicht stören".
NotificationHealth healthy({
  bool? enabled = true,
  int? importance = 4,
  bool? bypass = false,
  int? filter = 1,
  bool? restricted = false,
}) => NotificationHealth(
  notificationsEnabled: enabled,
  channelImportance: importance,
  channelBypassesDnd: bypass,
  interruptionFilter: filter,
  backgroundRestricted: restricted,
);

void main() {
  group('nichts im Weg', () {
    test('ein sauber eingerichtetes Gerät meldet keine Blockade', () {
      expect(healthy().blocks, isEmpty);
      expect(healthy().isClear, isTrue);
    });

    test('unbekannt ist keine Blockade', () {
      // Web, oder die Abfrage ist gescheitert. Ein Schirm, der ohne Wissen
      // warnt, ist Lärm — und der Nutzer kann nichts dagegen tun.
      expect(NotificationHealth.unknown.blocks, isEmpty);
      expect(const NotificationHealth().isClear, isTrue);
    });
  });

  group('die vier Achsen, jede für sich', () {
    test('entzogene Berechtigung', () {
      expect(healthy(enabled: false).blocks, [NotificationBlock.permission]);
    });

    test('Akku-Zustand „Eingeschränkt"', () {
      // Nicht die normale Akkuoptimierung: In diesem Zustand stellt FCM gar
      // nichts mehr zu, high wie normal priority.
      expect(healthy(restricted: true).blocks, [
        NotificationBlock.batteryRestricted,
      ]);
    });

    test('ausgeschalteter Kanal — der App-Schalter kann dabei an sein', () {
      expect(healthy(importance: 0).blocks, [NotificationBlock.channelOff]);
    });

    test('„Nicht stören" lässt diesen Kanal nicht durch', () {
      expect(healthy(filter: 2, bypass: false).blocks, [
        NotificationBlock.dndBlocks,
      ]);
    });
  });

  group('„Nicht stören" ist nicht gleich „Nicht stören"', () {
    test('mit Ausnahme kommt der Kanal im Prioritäten-Modus durch', () {
      expect(healthy(filter: 2, bypass: true).blocks, isEmpty);
    });

    test('totale Stille lässt auch einen Ausnahmekanal nicht durch', () {
      // `setBypassDnd` gilt ausdrücklich nur für den Prioritäten-Modus. Das
      // kann die App nicht lösen — und sie darf es nicht behaupten.
      expect(healthy(filter: 3, bypass: true).blocks, [
        NotificationBlock.dndSilences,
      ]);
    });

    test('„nur Wecker" ebenso wenig', () {
      expect(healthy(filter: 4, bypass: true).blocks, [
        NotificationBlock.dndSilences,
      ]);
    });

    test('ohne „Nicht stören" ist die Ausnahme egal', () {
      expect(healthy(filter: 1, bypass: false).blocks, isEmpty);
    });
  });

  group('stumm ist etwas anderes als aus', () {
    test('ein stumm gestellter Kanal wird gemeldet', () {
      // Erscheint, erreicht aber niemanden — für eine Erinnerung kurz vor
      // der Abfahrt dasselbe wie keine.
      expect(healthy(importance: 2).blocks, [NotificationBlock.channelSilent]);
    });

    test(
      'ein ausgeschalteter Kanal wird NICHT zusätzlich als stumm gemeldet',
      () {
        // Sonst stünden zwei Zeilen über denselben einen Schalter.
        expect(healthy(importance: 0).blocks, [NotificationBlock.channelOff]);
      },
    );

    test('kein Kanal ist kein stummer Kanal', () {
      // Vor Android 8 gibt es keine Kanäle. `null` heißt „weiß ich nicht",
      // und darüber wird nicht gewarnt.
      expect(healthy(importance: null).blocks, isEmpty);
    });
  });

  test('mehrere Blockaden werden alle gemeldet, nach Schwere', () {
    // Wer die Berechtigung erteilt und dann merkt, dass „Nicht stören" es
    // trotzdem schluckt, hat zweimal umsonst nachgesehen.
    final health = healthy(
      enabled: false,
      restricted: true,
      importance: 0,
      filter: 3,
    );
    expect(health.blocks, [
      NotificationBlock.permission,
      NotificationBlock.batteryRestricted,
      NotificationBlock.channelOff,
      NotificationBlock.dndSilences,
    ]);
  });

  group('fromMap verträgt alles, was die Brücke liefern kann', () {
    test('liest die Rohwerte', () {
      final health = NotificationHealth.fromMap(const {
        'notificationsEnabled': false,
        'channelImportance': 3,
        'channelBypassesDnd': true,
        'interruptionFilter': 2,
        'policyAccessGranted': true,
        'backgroundRestricted': false,
      });
      expect(health.notificationsEnabled, isFalse);
      expect(health.channelImportance, 3);
      expect(health.channelBypassesDnd, isTrue);
      expect(health.interruptionFilter, 2);
      expect(health.policyAccessGranted, isTrue);
      // Der Kanal ist Ausnahme, also blockt „Nicht stören" ihn nicht — übrig
      // bleibt genau die fehlende Berechtigung.
      expect(health.blocks, [NotificationBlock.permission]);
    });

    test('fehlende Schlüssel werden unbekannt, nicht falsch', () {
      final health = NotificationHealth.fromMap(const {});
      expect(health.notificationsEnabled, isNull);
      expect(health.blocks, isEmpty);
    });

    test('unerwartete Typen werfen nicht', () {
      // Diese Abfrage ist Diagnose. Sie darf den Schirm nie kaputt machen —
      // auch nicht, wenn ein künftiger Build etwas anderes schickt.
      final health = NotificationHealth.fromMap(const {
        'notificationsEnabled': 'ja',
        'channelImportance': 'hoch',
      });
      expect(health.notificationsEnabled, isNull);
      expect(health.channelImportance, isNull);
      expect(health.blocks, isEmpty);
    });
  });
}

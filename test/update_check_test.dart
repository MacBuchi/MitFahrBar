/// update_check_test.dart – Versionsvergleich für den Update-Hinweis.
library;

import 'package:fahrgemeinschaft/core/update_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isNewerVersion', () {
    test('erkennt neuere Versionen', () {
      expect(isNewerVersion('0.5.0', '0.4.2'), isTrue);
      expect(isNewerVersion('1.0.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.4.3', '0.4.2'), isTrue);
    });

    test('vergleicht numerisch, nicht als Text', () {
      expect(isNewerVersion('0.10.0', '0.9.0'), isTrue);
      expect(isNewerVersion('0.9.0', '0.10.0'), isFalse);
    });

    test('gleiche oder ältere Version ergibt kein Update', () {
      expect(isNewerVersion('0.4.2', '0.4.2'), isFalse);
      expect(isNewerVersion('0.4.1', '0.4.2'), isFalse);
    });

    test('Vorab- und Build-Suffixe verschlucken kein Update', () {
      // Ohne Abschneiden würde "1-rc1" zu 0 und das Update verschwinden.
      expect(isNewerVersion('1.0.0-rc1', '0.9.0'), isTrue);
      expect(isNewerVersion('0.5.0+7', '0.4.9'), isTrue);
    });

    test('bleibt bei Unsinn ruhig', () {
      expect(isNewerVersion('kaputt', '0.1.0'), isFalse);
      expect(isNewerVersion('', '0.1.0'), isFalse);
    });
  });
}

/// log_ring_test.dart – Der Mitschnitt für Fehlermeldungen.
library;

import 'package:fahrgemeinschaft/core/log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogRing', () {
    test('hebt nur die jüngsten Zeilen auf', () {
      final ring = LogRing(capacity: 3);
      for (final line in ['eins', 'zwei', 'drei', 'vier']) {
        ring.add(line);
      }

      expect(
        ring.lines,
        ['zwei', 'drei', 'vier'],
        reason:
            'Ohne Deckel würde ein Dauerfehler den Speicher füllen und den '
            'Dialog fluten.',
      );
    });

    test('tail schneidet vorne ab, nicht hinten', () {
      final ring = LogRing()
        ..add('alt und lang genug um wegzufallen')
        ..add('neu');

      expect(
        ring.tail(maxChars: 10),
        'neu',
        reason:
            'Die letzte Meldung vor einem Absturz ist die interessanteste — '
            'gekürzt wird deshalb am Anfang.',
      );
    });

    test('eine einzelne überlange Zeile geht trotzdem mit', () {
      final ring = LogRing()..add('x' * 500);

      expect(
        ring.tail(maxChars: 10),
        hasLength(500),
        reason: 'Sonst käme bei genau einem langen Stacktrace nichts an.',
      );
    });

    test('leer bleibt leer', () {
      final ring = LogRing();
      expect(ring.isEmpty, isTrue);
      expect(ring.tail(), isEmpty);
    });

    test('clear leert den Puffer', () {
      final ring = LogRing()..add('irgendwas');
      ring.clear();
      expect(ring.isEmpty, isTrue);
    });

    // Der globale Logger hängt den Ring als LogOutput ein — die globalen
    // Fehler-Handler in main.dart laufen bereits über log.e, es muss also
    // keine Aufrufstelle angefasst werden.
    test('der globale Logger schreibt in den globalen Ring', () {
      logRing.clear();
      log.e('Testfehler');

      expect(logRing.isNotEmpty, isTrue);
      expect(logRing.tail(), contains('Testfehler'));
      logRing.clear();
    });
  });
}

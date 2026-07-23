/// balance_label_test.dart – Punktestand und Fahrraten-Deltas in Worten.
library;

import 'package:fahrgemeinschaft/core/balance_label.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  final format = NumberFormat('0.#', 'de');

  group('balanceLabel', () {
    test('Richtung steht im Text, nicht im Vorzeichen', () {
      expect(balanceLabel(2.5, format), 'hat 2,5 gut');
      expect(balanceLabel(-1.5, format), 'schuldet 1,5');
      expect(balanceLabel(0.02, format), 'ausgeglichen');
    });
  });

  group('signedPoints', () {
    test('typografisches Minus, kompakte Null', () {
      expect(signedPoints(1.5, format), '+1,5');
      expect(signedPoints(-2, format), '−2');
      expect(signedPoints(0.01, format), '0');
    });
  });

  // Issue #60: Fahrraten-Änderung der geplanten Woche in Promille.
  group('signedPerMille', () {
    test('rundet auf ganze Promille und trägt das Vorzeichen', () {
      expect(signedPerMille(0.0834), '+83 ‰');
      expect(signedPerMille(-0.125), '−125 ‰');
      expect(signedPerMille(1.0), '+1000 ‰');
    });

    test('unmerkliche Änderungen sind eine ehrliche Null', () {
      expect(signedPerMille(0.0004), '±0 ‰');
      expect(signedPerMille(-0.0004), '±0 ‰');
    });
  });
}

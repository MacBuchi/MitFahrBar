// Hält fest, dass die Testsuite in einer Zeitzone mit Sommerzeit läuft
// (#290). In UTC gibt es keine Zeitumstellung — jeder Test über den
// Wechsel wäre dort grün, egal ob `Duration(days: …)` den Tag verfehlt.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI führt flutter test in Europe/Berlin aus', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(
      RegExp(
        r"- name: Tests \(Europe/Berlin\)\s+env:\s+TZ: Europe/Berlin\s+run: flutter test",
      ).hasMatch(ci),
      isTrue,
      reason:
          'Ohne TZ läuft der Runner in UTC, und die Zeitumstellungs-Tests in '
          'test/plan_test.dart und test/push_digest_test.dart prüfen nichts.',
    );
  });

  test('die Suite sieht die Zeitumstellung wirklich', () {
    // Am 25.10.2026 springt Berlin von MESZ auf MEZ: 24 Stunden nach
    // Mitternacht ist noch Sonntag. Fällt das weg, läuft die Suite ohne
    // Sommerzeit — lokal genauso wie in der CI.
    final sundayPlus24h = DateTime(2026, 10, 25).add(const Duration(days: 1));
    expect(
      sundayPlus24h.hour,
      23,
      reason:
          'flutter test braucht TZ=Europe/Berlin (oder eine andere '
          'Zone mit derselben Sommerzeit)',
    );
  });

  test('planningWeek rechnet nicht mit Duration', () {
    final src = File('lib/core/fairness.dart').readAsStringSync();
    final start = src.indexOf('List<DateTime> planningWeek(');
    final end = src.indexOf('\n}\n', start);
    final body = src
        .substring(start, end)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(body, isNot(contains('Duration(')));
  });
}

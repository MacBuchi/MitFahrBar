/// group_status_test.dart – Ein unbekannter Gruppen-Status darf den Client
/// nicht umbringen.
///
/// Warum das ein eigener Test ist: `GroupStatus.values.byName(...)` **wirft**
/// bei einem Namen, den diese Fassung nicht kennt. Der Fehler landete in
/// `myGroupProvider`, und die Nutzerin sähe „Fehler: Invalid argument" statt
/// einer Erklärung — ausgerechnet dann, wenn der Server einen neuen Zustand
/// einführt (etwa das Stilllegen ungenutzter Gruppen). Jede solche Neuerung
/// bräuchte dann erst ein Client-Release, und der Sperr-Schirm greift bewusst
/// nie, solange es keines gibt.
///
/// Die sichere Richtung ist immer „kein Zugang": Was der Client nicht kennt,
/// gilt als nicht aktiv. Wer den Parser wieder auf `byName` umstellt, macht
/// jede künftige Statusänderung zu einem Release-Zwang.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/models/group.dart';

Map<String, dynamic> _json(String status) => {
  'id': 'g1',
  'name': 'Dacia Racing',
  'handle': 'daciaracing',
  'status': status,
  'is_admin': false,
};

void main() {
  test('die bekannten Status kommen unverändert an', () {
    expect(Group.fromJson(_json('pending')).status, GroupStatus.pending);
    expect(Group.fromJson(_json('active')).status, GroupStatus.active);
    expect(Group.fromJson(_json('rejected')).status, GroupStatus.rejected);
    expect(Group.fromJson(_json('archived')).status, GroupStatus.archived);
  });

  test('nur "active" gilt als aktiv', () {
    expect(Group.fromJson(_json('active')).isActive, isTrue);
    for (final status in ['pending', 'rejected', 'archived']) {
      expect(Group.fromJson(_json(status)).isActive, isFalse);
    }
  });

  test('ein unbekannter Status wirft nicht und gilt als nicht aktiv', () {
    late final Group group;
    expect(
      () => group = Group.fromJson(_json('irgendwas_neues')),
      returnsNormally,
      reason:
          'Sonst zeigt jeder veröffentlichte Client einen Fehlerbildschirm, '
          'sobald der Server einen neuen Zustand setzt.',
    );
    expect(
      group.isActive,
      isFalse,
      reason:
          'Ein Status, den der Client nicht versteht, darf niemals Zugang '
          'zu Gruppendaten geben.',
    );
    expect(
      group.status,
      GroupStatus.archived,
      reason:
          'Unbekannt wird als „stillgelegt" gelesen — der Screen erklärt das '
          'dann als „nicht in Gebrauch" statt als Fehler.',
    );
  });
}

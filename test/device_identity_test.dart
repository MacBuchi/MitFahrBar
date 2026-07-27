/// device_identity_test.dart – Die drei Zustände der Geräte-Zuordnung (#121).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/data/device_identity.dart';

void main() {
  group('DeviceIdentity', () {
    // Der mittlere Zustand ist der eigentliche Inhalt: Ohne ihn käme die
    // Startabfrage bei jedem Start wieder, und man klickt sie blind weg.
    test('kennt drei Zustände, nicht zwei', () {
      expect(DeviceIdentity.unknown.asked, isFalse);
      expect(DeviceIdentity.unknown.chosen, isFalse);

      expect(DeviceIdentity.skipped.asked, isTrue);
      expect(DeviceIdentity.skipped.chosen, isFalse);

      const picked = DeviceIdentity(personId: 'p1', asked: true);
      expect(picked.asked, isTrue);
      expect(picked.chosen, isTrue);
    });

    test('„übersprungen" ist nicht „nie gefragt"', () {
      expect(
        DeviceIdentity.skipped,
        isNot(DeviceIdentity.unknown),
        reason:
            'Fielen beide zusammen, gäbe es keinen Weg, die Frage genau '
            'einmal zu stellen.',
      );
    });
  });

  group('InMemoryDeviceIdentityStore', () {
    test('gibt zurück, was gespeichert wurde', () async {
      final store = InMemoryDeviceIdentityStore();
      expect(await store.load(), DeviceIdentity.unknown);

      await store.save(const DeviceIdentity(personId: 'p1', asked: true));
      expect(
        await store.load(),
        const DeviceIdentity(personId: 'p1', asked: true),
      );
    });

    test(
      'eine Auswahl lässt sich zurücknehmen, ohne „nie gefragt" zu werden',
      () async {
        final store = InMemoryDeviceIdentityStore(
          const DeviceIdentity(personId: 'p1', asked: true),
        );
        await store.save(DeviceIdentity.skipped);

        final loaded = await store.load();
        expect(loaded.chosen, isFalse);
        expect(
          loaded.asked,
          isTrue,
          reason:
              'Wer bewusst auf „niemand" stellt, will nicht beim nächsten Start '
              'wieder gefragt werden.',
        );
      },
    );
  });
}

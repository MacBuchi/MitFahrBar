/// update_check_test.dart – Versionsvergleich und Sperre für alte Clients.
library;

import 'package:mitfahrbar/core/update_check.dart';
import 'package:mitfahrbar/data/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _update = UpdateInfo(
  latestVersion: '0.18.0',
  releaseUrl: 'https://example.invalid/release',
);

/// Baut den Sperr-Provider mit vorgegebenen Bausteinen.
Future<UpdateInfo?> requiredUpdate({
  required String current,
  String? minimum,
  UpdateInfo? available = _update,
}) async {
  final container = ProviderContainer(
    overrides: [
      currentVersionProvider.overrideWith((ref) async => current),
      updateInfoProvider.overrideWith((ref) async => available),
      minSupportedVersionProvider.overrideWith((ref) async => minimum),
    ],
  );
  addTearDown(container.dispose);
  return container.read(updateRequiredProvider.future);
}

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

  // Der Schirm liegt im Startpfad: Ein Fehler hier sperrt alle aus, und die
  // Korrektur käme nur über ein neues Release. Diese vier Fälle sind
  // deshalb der eigentliche Inhalt der Sperre.
  group('updateRequiredProvider', () {
    test('unterhalb der Mindestversion wird gesperrt', () async {
      expect(
        await requiredUpdate(current: '0.16.0', minimum: '0.17.0'),
        isNotNull,
      );
    });

    test('ohne verfügbares Update wird nie gesperrt', () async {
      // Der Tippfehler-Fall: Steht dort 99.0.0, könnte niemand ihn je
      // erfüllen. Die Zusage ist, dass der neueste Client durchkommt —
      // sonst wäre der einzige Ausweg eine weitere Migration.
      expect(
        await requiredUpdate(
          current: '0.17.0',
          minimum: '99.0.0',
          available: null,
        ),
        isNull,
      );
    });

    test('ohne bekannte Mindestversion wird nie gesperrt', () async {
      // null heißt offline, Tabelle fehlt oder Zeile fehlt. Eine Sperre aus
      // einem Netzwerkfehler wäre schlimmer als der alte Client.
      expect(await requiredUpdate(current: '0.1.0'), isNull);
    });

    test('genau die Mindestversion reicht aus', () async {
      expect(
        await requiredUpdate(current: '0.17.0', minimum: '0.17.0'),
        isNull,
      );
    });

    test('neuer als die Mindestversion ebenfalls', () async {
      expect(
        await requiredUpdate(current: '0.18.0', minimum: '0.17.0'),
        isNull,
      );
    });
  });
}

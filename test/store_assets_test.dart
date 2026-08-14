import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Was der Play-Store-Eintrag hochlädt, prüft sonst erst die Console — und
/// zwar mit einer Meldung, die nur sagt, dass etwas nicht passt. Ein falsches
/// Maß oder eine fehlende Alpha-Ebene ist hier in Millisekunden zu sehen,
/// dort in einem Formular, das man ohnehin nur alle paar Monate anfasst.
void main() {
  group('Store-Grafiken', () {
    test('App-Symbol ist 512×512 und wirklich 32-Bit', () {
      final png = _png('doc/store/icon-512.png');
      expect(png.width, 512);
      expect(png.height, 512);
      expect(
        png.colorType,
        6,
        reason:
            'Play verlangt ein 32-Bit-PNG, also RGBA (Farbtyp 6). Genau '
            'deshalb ist die Quelle das maskable PWA-Icon und nicht '
            'Icon-512.png — das ist die weiße Marke auf Transparenz und im '
            'Store-Umfeld unsichtbar.',
      );
    });

    test('Feature-Grafik ist 1024×500', () {
      final png = _png('doc/store/feature-graphic.png');
      expect(png.width, 1024);
      expect(png.height, 500);
    });

    test('Telefon-Screenshots sind 1080×1920, mindestens zwei', () {
      final shots =
          Directory('doc/store/screenshots')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.png'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(
        shots.length,
        greaterThanOrEqualTo(2),
        reason: 'Play nimmt einen Eintrag mit weniger nicht an.',
      );
      expect(shots.length, lessThanOrEqualTo(8), reason: 'Play zeigt acht.');
      for (final shot in shots) {
        final png = _png(shot.path);
        // Die README-Screenshots sind 860×1800 = 1:2,09 und wären an Plays
        // 2:1-Grenze gescheitert. tool/store_assets.py füllt sie seitlich
        // auf, statt zu beschneiden — ein Zuschnitt träfe App-Bar oder
        // Navigationsleiste.
        expect(
          [png.width, png.height],
          [1080, 1920],
          reason: '${shot.path} hat ${png.width}×${png.height}.',
        );
      }
    });
  });

  group('Datensicherheits-CSV', () {
    final csv = File('doc/store/data_safety.csv').readAsStringSync();

    // Ohne den Aufruf in der CI wird **nichts rot**, wenn die Antworten in
    // `tool/play_data_safety.py` und die eingecheckte CSV auseinanderlaufen —
    // dieselbe Lehre wie beim Service-Worker-Injektor.
    test('die CI hält CSV und Antwort-Tabelle zusammen', () {
      expect(
        File('.github/workflows/ci.yml').readAsStringSync(),
        contains('python3 tool/play_data_safety.py --check'),
      );
    });

    // Googles Muster-CSV ist NICHT leer: Sie beschreibt eine erfundene App
    // mit 15 gesetzten Werten. Unverändert hochgeladen deklariert man deren
    // Angaben — darunter „ungefährer Standort, geteilt, für Werbung".
    test('kein Rest von Googles Beispiel-App', () {
      for (final leftover in const [
        'PSL_APPROX_LOCATION,true',
        'PSL_PRECISE_LOCATION,true',
        'PSL_ADVERTISING,true',
        'PSL_ANALYTICS,true',
      ]) {
        expect(
          csv,
          isNot(contains(leftover)),
          reason:
              'MitFahrBar erhebt keinen Standort und wertet nichts aus — '
              'steht das hier, wurde die Vorlage nicht geleert.',
        );
      }
    });

    test('die Löschseite steht drin, und zwar die live erreichbare', () {
      expect(
        csv,
        contains('https://macbuchi.github.io/MitFahrBar/konto-loeschen.html'),
        reason:
            'Play ruft die URL auf. Sie liegt erst seit der Beförderung von '
            '0.83.0 auf Pages — gebaut ist nicht ausgeliefert.',
      );
    });
  });
}

/// Maße und Farbtyp direkt aus dem IHDR — kein Bildpaket für zwölf Bytes.
({int width, int height, int colorType}) _png(String path) {
  final bytes = File(path).readAsBytesSync();
  final header = ByteData.sublistView(Uint8List.fromList(bytes));
  expect(bytes.sublist(0, 8), const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
  ], reason: '$path ist kein PNG.');
  return (
    width: header.getUint32(16),
    height: header.getUint32(20),
    colorType: header.getUint8(25),
  );
}

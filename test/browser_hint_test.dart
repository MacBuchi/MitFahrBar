/// browser_hint_test.dart – Die Zuordnung Browser → Anleitung (#230).
///
/// Geprüft wird gegen **echte** User-Agent-Zeichenketten, nicht gegen
/// erfundene: Der ganze Inhalt der Erkennung ist die Reihenfolge der
/// Abfragen, und die fällt nur an den Verwandtschaften auf. Edge und Opera
/// tragen `Chrome` mit; Chrome, Edge und Firefox auf iOS tragen `Safari` mit.
/// Wer zuerst auf Chrome prüft, schickt Opera-Nutzer in ein Menü, das es dort
/// nicht gibt.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mitfahrbar/core/browser_hint.dart';

void main() {
  group('browserFromUserAgent', () {
    test('Chrome auf Android und Desktop', () {
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36',
        ),
        BrowserKind.chrome,
      );
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
        ),
        BrowserKind.chrome,
      );
    });

    test('Edge ist nicht Chrome — obwohl „Chrome" darin steht', () {
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0',
        ),
        BrowserKind.edge,
      );
      // Die ältere Android-Fassung meldet sich als EdgA.
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like '
          'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 EdgA/126.0.0.0',
        ),
        BrowserKind.edge,
      );
    });

    test('Opera ist nicht Chrome — dasselbe Muster', () {
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 OPR/112.0.0.0',
        ),
        BrowserKind.opera,
      );
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like '
          'Gecko) Chrome/126.0.0.0 Mobile Safari/537.36 OPR/76.0.0.0',
        ),
        BrowserKind.opera,
      );
    });

    test('Firefox auf Desktop, Android und iOS', () {
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 '
          'Firefox/127.0',
        ),
        BrowserKind.firefox,
      );
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (Android 14; Mobile; rv:127.0) Gecko/127.0 Firefox/127.0',
        ),
        BrowserKind.firefox,
      );
      // Auf iOS steckt Firefox in einer Safari-Hülle und trägt „Safari" mit.
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/127.0 Mobile/15E148 '
          'Safari/605.1.15',
        ),
        BrowserKind.firefox,
      );
    });

    test('Safari erst, wenn kein anderer sich meldet', () {
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 '
          'Safari/604.1',
        ),
        BrowserKind.safari,
      );
      // Chrome auf iOS ist CriOS und trägt ebenfalls „Safari".
      expect(
        browserFromUserAgent(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/126.0.0.0 '
          'Mobile/15E148 Safari/604.1',
        ),
        BrowserKind.chrome,
      );
    });

    test('Unbekanntes und Leeres landen bei „Dein Browser"', () {
      expect(browserFromUserAgent(''), BrowserKind.other);
      expect(browserFromUserAgent('irgendwas'), BrowserKind.other);
      expect(browserLabel(BrowserKind.other), 'Dein Browser');
    });
  });

  group('notificationStepsFor', () {
    test('jeder Browser bekommt einen Weg, keiner eine Entschuldigung', () {
      for (final kind in BrowserKind.values) {
        final steps = notificationStepsFor(kind);
        expect(steps, isNotEmpty, reason: '$kind ohne Anleitung');
        // Der letzte Schritt führt zurück in die App — ohne ihn bliebe der
        // Mensch in den Browser-Einstellungen stehen und wüsste nicht, dass
        // er hier noch einmal einschalten muss.
        expect(steps.last, contains('neu'), reason: '$kind ohne Rückweg');
      }
    });
  });
}

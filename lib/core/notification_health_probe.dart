/// notification_health_probe.dart – Die Brücke zu Androids Wahrheit (#180).
///
/// Fragt den echten Zustand ab und öffnet die Systemschirme, auf denen er
/// sich ändern lässt. Die Bewertung steckt in `notification_health.dart` und
/// bleibt davon getrennt — hier ist nichts zu prüfen als die Verdrahtung.
///
/// **Bewusst NICHT über `firebase_messaging.getNotificationSettings()`.**
/// Das ist auf Android unzuverlässig: Es meldet `authorized`, obwohl
/// Benachrichtigungen in den Systemeinstellungen aus sind
/// (flutterfire#4492), und auf API 34 `denied`, bevor überhaupt gefragt
/// wurde (flutterfire#12839, #9501). Eine Überwachung darauf gebaut wäre
/// genau die stille Falschaussage, gegen die sie antritt — der Schirm sagte
/// „alles in Ordnung", während nichts ankommt.
///
/// Jeder Fehlerpfad endet in [NotificationHealth.unknown] bzw. in gar nichts.
/// Diese Abfrage ist Diagnose; sie darf den Schirm nie kaputt machen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_hint.dart';
import 'notification_health.dart';
import 'web_notifications.dart';

/// Die Kanal-Kennung aus `android/app/src/main/res/values/strings.xml`
/// (`notification_channel_plan_id`). Muss wörtlich übereinstimmen —
/// `test/android_manifest_test.dart` vergleicht beide Dateien. Driften sie,
/// fragt die App nach einem Kanal, den es nicht gibt, bekommt „unbekannt"
/// zurück und meldet fröhlich, es sei alles in Ordnung.
const String androidPlanChannel = 'plan';

/// Wer hier die Erlaubnis vergibt. Drei Welten, drei Antworten — und im Web
/// eine einzige Achse statt vier.
enum NotificationOwner { android, browser, none }

/// Liest den Zustand und öffnet die passenden Systemschirme.
class NotificationHealthProbe {
  const NotificationHealthProbe({
    MethodChannel? channel,
    String? Function()? webPermission,
    String Function()? userAgent,
    NotificationOwner? owner,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _webPermission = webPermission ?? webNotificationPermission,
       _userAgent = userAgent ?? webUserAgent,
       _owner = owner;

  /// Muss wörtlich mit `HEALTH_CHANNEL` in `MainActivity.kt` übereinstimmen —
  /// `test/android_manifest_test.dart` vergleicht beide Dateien.
  static const channelName = 'de.macbuchi.mitfahrbar/notification_health';

  final MethodChannel _channel;

  /// Die Plattform-Quellen als Parameter, damit der Flow-Test einen
  /// blockierten Browser nachstellen kann, **ohne einen zu starten**. Ohne
  /// diesen Schnitt liefe der Web-Zweig in `flutter test` (VM) nie — und die
  /// Karten, um die es hier geht, wären ungeprüft.
  final String? Function() _webPermission;
  final String Function() _userAgent;
  final NotificationOwner? _owner;

  NotificationOwner get owner => _owner ?? _detected;

  static NotificationOwner get _detected {
    if (kIsWeb) return NotificationOwner.browser;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return NotificationOwner.android;
    }
    return NotificationOwner.none;
  }

  /// Ob überhaupt etwas zu lesen ist. Seit v0.78.0 auch im Web — vorher blieb
  /// der Zustand dort auf „unbekannt", und damit war die ganze Führung aus
  /// #180 im Browser dunkel: keine Karte, keine Erklärung, nur eine
  /// SnackBar-Zeile beim Einschalten.
  bool get supported => owner != NotificationOwner.none;

  /// Ob die App den Systemschirm selbst öffnen kann. **Im Browser nie** — es
  /// gibt keine Web-API für die Seiteneinstellungen einer Seite. Deshalb steht
  /// dort eine Anleitung statt eines Knopfes (`browser_hint.dart`).
  bool get canOpenSettings => owner == NotificationOwner.android;

  /// Welcher Browser gerade läuft — für die Anleitung, die den Knopf ersetzt.
  BrowserKind get browser => browserFromUserAgent(_userAgent());

  /// Der Zustand für genau diesen Kanal.
  ///
  /// [channelId] ist ein **Parameter und kein fester Wert**: Sobald die
  /// Abfahrts-Erinnerung ihren eigenen Kanal bekommt (#180 B), ist das eine
  /// Ergänzung und kein Umbau dieser Abfrage.
  Future<NotificationHealth> read(String channelId) async {
    // Im Browser gibt es genau eine Achse: Darf die Seite überhaupt?
    // Kanäle, „Nicht stören" und den Akku-Zustand kennt er nicht — und
    // erfundene Werte stünden hier als Behauptung im Schirm.
    //
    // `default` (noch nie gefragt) ist ausdrücklich **keine** Blockade: Das
    // Einschalten löst dann den Dialog aus, und eine Warnung davor wäre eine
    // Fehlmeldung an jeden, der den Screen zum ersten Mal öffnet.
    if (owner == NotificationOwner.browser) {
      return switch (_webPermission()) {
        'granted' => const NotificationHealth(notificationsEnabled: true),
        'denied' => const NotificationHealth(notificationsEnabled: false),
        _ => NotificationHealth.unknown,
      };
    }
    if (!supported) return NotificationHealth.unknown;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('read', {
        'channel': channelId,
      });
      if (raw == null) return NotificationHealth.unknown;
      return NotificationHealth.fromMap(raw);
    } catch (_) {
      // Fehlt der Kanal (alter Build), ist eben nichts bekannt — und
      // unbekannt meldet keine Blockade.
      return NotificationHealth.unknown;
    }
  }

  Future<void> openAppNotifications() => _open('openAppNotifications');

  Future<void> openChannel(String channelId) =>
      _open('openChannel', {'channel': channelId});

  Future<void> openDndAccess() => _open('openDndAccess');

  Future<void> openAppDetails() => _open('openAppDetails');

  Future<void> _open(String method, [Map<String, Object?>? args]) async {
    if (!canOpenSettings) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // Kein Gerät hat garantiert jeden Systemschirm. Der Text daneben sagt
      // ohnehin, worum es geht.
    }
  }
}

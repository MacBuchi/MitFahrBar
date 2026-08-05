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

import 'notification_health.dart';

/// Die Kanal-Kennung aus `android/app/src/main/res/values/strings.xml`
/// (`notification_channel_plan_id`). Muss wörtlich übereinstimmen —
/// `test/android_manifest_test.dart` vergleicht beide Dateien. Driften sie,
/// fragt die App nach einem Kanal, den es nicht gibt, bekommt „unbekannt"
/// zurück und meldet fröhlich, es sei alles in Ordnung.
const String androidPlanChannel = 'plan';

/// Liest den Zustand und öffnet die passenden Systemschirme.
class NotificationHealthProbe {
  const NotificationHealthProbe({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// Muss wörtlich mit `HEALTH_CHANNEL` in `MainActivity.kt` übereinstimmen —
  /// `test/android_manifest_test.dart` vergleicht beide Dateien.
  static const channelName = 'de.macbuchi.mitfahrbar/notification_health';

  final MethodChannel _channel;

  /// Nur Android. Im Web entscheidet der Browser über die Erlaubnis, und
  /// weder Kanäle noch „Nicht stören" gibt es dort.
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Der Zustand für genau diesen Kanal.
  ///
  /// [channelId] ist ein **Parameter und kein fester Wert**: Sobald die
  /// Abfahrts-Erinnerung ihren eigenen Kanal bekommt (#180 B), ist das eine
  /// Ergänzung und kein Umbau dieser Abfrage.
  Future<NotificationHealth> read(String channelId) async {
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
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } catch (_) {
      // Kein Gerät hat garantiert jeden Systemschirm. Der Text daneben sagt
      // ohnehin, worum es geht.
    }
  }
}

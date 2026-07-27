/// device_identity.dart – Wer sitzt an DIESEM Gerät (#121).
///
/// **Das ist ausdrücklich kein Login.** „Eine Gruppe = ein Login" bleibt
/// unangetastet: `group_id = auth.uid()`, keine Policy ändert sich, und über
/// die Rückfrage im Planer darf weiterhin jeder für jeden eintragen. Was hier
/// entsteht, ist eine **Einstellung dieses Geräts gegen Vertipper** — wer sie
/// je für eine Zugriffskontrolle hält, irrt: Ein zweites Gerät mit anderer
/// Auswahl bearbeitet alles.
///
/// Sie liegt bewusst **lokal** und nicht in `push_devices`. Dort hinge sie am
/// FCM-Token und existierte im Browser ohne Push und auf iOS gar nicht —
/// genau dort soll sie aber wirken (Banner, später die Planer-Leitplanke).
///
/// **Folge, die dazugehört:** Die Android-Backup-Regeln schließen
/// `FlutterSharedPreferences.xml` als ganze Datei aus, weil dort das
/// Sitzungs-Token liegt. Die Auswahl überlebt deshalb keinen Gerätewechsel —
/// das neue Gerät fragt erneut. Das ist gewollt und der Preis dafür, dass der
/// gemeinsame Gruppenzugang nicht über das Google-Konto eines Mitglieds
/// wandert.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Der Zustand der Zuordnung — **drei** Möglichkeiten, nicht zwei.
///
/// Ohne „schon gefragt, aber übersprungen" käme die Startabfrage bei jedem
/// Start wieder, und man klickt sie blind weg. Gemahnt wird an genau einer
/// Stelle: dem Banner auf der Übersicht.
class DeviceIdentity {
  const DeviceIdentity({this.personId, this.asked = false});

  /// Noch nie gefragt.
  static const unknown = DeviceIdentity();

  /// Gefragt und bewusst übersprungen.
  static const skipped = DeviceIdentity(asked: true);

  /// `null` heißt: niemand ausgewählt.
  final String? personId;

  /// Ob die Startabfrage schon einmal beantwortet wurde — auch mit „Später".
  final bool asked;

  bool get chosen => personId != null;

  @override
  bool operator ==(Object other) =>
      other is DeviceIdentity &&
      other.personId == personId &&
      other.asked == asked;

  @override
  int get hashCode => Object.hash(personId, asked);

  @override
  String toString() => 'DeviceIdentity($personId, asked: $asked)';
}

abstract class DeviceIdentityStore {
  Future<DeviceIdentity> load();
  Future<void> save(DeviceIdentity identity);
}

/// Die echte Ablage. Zwei Schlüssel statt einem: „übersprungen" und „noch nie
/// gefragt" müssen unterscheidbar bleiben, und ein leerer String als
/// Ersatzwert wäre genau die Art Kniff, die später niemand mehr erklärt.
class SharedPrefsDeviceIdentityStore implements DeviceIdentityStore {
  static const _personKey = 'identity.person_id';
  static const _askedKey = 'identity.asked';

  @override
  Future<DeviceIdentity> load() async {
    final prefs = await SharedPreferences.getInstance();
    return DeviceIdentity(
      personId: prefs.getString(_personKey),
      asked: prefs.getBool(_askedKey) ?? false,
    );
  }

  @override
  Future<void> save(DeviceIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    if (identity.personId == null) {
      await prefs.remove(_personKey);
    } else {
      await prefs.setString(_personKey, identity.personId!);
    }
    await prefs.setBool(_askedKey, identity.asked);
  }
}

/// Für den Demo-Modus und Tests: Es gibt dort nichts zu behalten.
class InMemoryDeviceIdentityStore implements DeviceIdentityStore {
  InMemoryDeviceIdentityStore([this._value = DeviceIdentity.unknown]);

  DeviceIdentity _value;

  @override
  Future<DeviceIdentity> load() async => _value;

  @override
  Future<void> save(DeviceIdentity identity) async => _value = identity;
}

/// offline_cache_prefs_test.dart – Die ECHTE Ablage des letzten Stands.
///
/// [PrefsOfflineCache] ist bis v0.79.0 in keinem Test gelaufen: Jeder Test
/// der Suite nimmt [InMemoryOfflineCache], und die echte Fassung hing allein
/// an `providers.dart`. Damit war ausgerechnet die Klasse ungeprüft, die auf
/// dem Gerät entscheidet, ob nach einem Neustart überhaupt etwas da ist —
/// dieselbe Lücke wie bei den Release-only-Fallen im Manifest: kompiliert
/// sauber, fällt erst beim Nutzer auf.
///
/// Der schärfste Fall steht in „räumt nur die eigenen Schlüssel weg": Ein
/// `keepOnly`, das über den Präfix hinausgreift, löscht das
/// **Sitzungs-Token** der Gruppe gleich mit — dann steht nach dem
/// Gruppenwechsel nicht der falsche Stand da, sondern der Login.
library;

import 'dart:convert';

import 'package:mitfahrbar/data/offline_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // SharedPreferences läuft über einen Plattform-Kanal; ohne Binding und
  // Mock gäbe es hier gar keine Ablage.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Rundlauf: was abgelegt wurde, kommt mit Zeitpunkt zurück', () async {
    final cache = PrefsOfflineCache();
    final before = DateTime.now();
    await cache.write('g1', 'persons', [
      {'id': 'p1', 'name': 'Anna'},
    ]);

    final stored = await cache.read('g1', 'persons');

    expect(stored, isNotNull);
    expect(stored!.value, [
      {'id': 'p1', 'name': 'Anna'},
    ]);
    // Der Zeitpunkt ist der eigentliche Inhalt der Leiste — ohne ihn hielte
    // man einen alten Plan für den aktuellen.
    expect(
      stored.storedAt.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test('ein unbekannter Schlüssel ist kein Fehler', () async {
    expect(await PrefsOfflineCache().read('g1', 'nie-geschrieben'), isNull);
  });

  test('eine andere Gruppe liest die Zeilen der ersten nicht', () async {
    final cache = PrefsOfflineCache();
    await cache.write('g1', 'persons', ['Anna']);

    expect(await cache.read('g2', 'persons'), isNull);
  });

  test('räumt nur die eigenen Schlüssel weg', () async {
    // Was sonst noch in derselben Datei liegt: die Geräte-Zuordnung (#121)
    // und — der teure Fall — das Sitzungs-Token der Gruppe.
    SharedPreferences.setMockInitialValues({
      'mfb.device.person': 'p1',
      'supabase.session': '{"access_token":"…"}',
    });
    final cache = PrefsOfflineCache();
    await cache.write('g1', 'persons', ['Anna']);
    await cache.write('g2', 'persons', ['Bert']);

    await cache.keepOnly('g1');

    expect(await cache.read('g1', 'persons'), isNotNull);
    expect(
      await cache.read('g2', 'persons'),
      isNull,
      reason: 'die Mandantentrennung der RLS, auf dem Gerät nachgezogen',
    );

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('supabase.session'),
      isNotNull,
      reason:
          'greift das Aufräumen über den eigenen Präfix hinaus, wirft es die '
          'Gruppe beim Gruppenwechsel aus der Anmeldung',
    );
    expect(prefs.getString('mfb.device.person'), 'p1');
  });

  test('ein kaputter Eintrag ist wie keiner, nicht wie ein Absturz', () async {
    final cache = PrefsOfflineCache();
    await cache.write('g1', 'persons', ['Anna']);
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getKeys().firstWhere(
      (k) => k.startsWith('mfb.cache.g1.'),
    );

    // Drei Arten, kaputt zu sein: gar kein JSON, JSON ohne Zeitstempel,
    // und ein Zeitstempel, den niemand parsen kann. Alle drei enden im
    // selben Ausgang — der Lesezugriff geht danach über das Netz.
    for (final broken in [
      'kein json',
      jsonEncode({'v': 'Anna'}),
      jsonEncode({'at': 'vorgestern', 'v': 'Anna'}),
    ]) {
      await prefs.setString(key, broken);
      expect(await cache.read('g1', 'persons'), isNull, reason: broken);
    }
  });

  test('ein zweiter Schreibzugriff ersetzt den ersten', () async {
    final cache = PrefsOfflineCache();
    await cache.write('g1', 'trips', ['alt']);
    await cache.write('g1', 'trips', ['neu']);

    expect((await cache.read('g1', 'trips'))!.value, ['neu']);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('mfb.cache.')).length,
      1,
      reason: 'je (Gruppe, Schlüssel) ein Eintrag — sonst wächst die Datei',
    );
  });

  test('null ist ein Wert, kein fehlender Eintrag', () async {
    // `myGroup()` darf legitim `null` liefern. Käme das als „nichts
    // gespeichert" zurück, liefe der Gate-Lesezugriff ohne Netz in den
    // Fehlerschirm statt in den bekannten Stand.
    final cache = PrefsOfflineCache();
    await cache.write('g1', 'group', null);

    final stored = await cache.read('g1', 'group');
    expect(stored, isNotNull);
    expect(stored!.value, isNull);
  });
}

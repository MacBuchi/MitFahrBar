/// android_manifest_test.dart – Schützt die Android-Voraussetzungen, die
/// ausschließlich im Release auf einem echten Gerät auffallen.
///
/// Alles hier Geprüfte hat dasselbe Muster: Es lässt sich weder im Debug-Lauf
/// noch im Web bemerken. Fehlt eines, merkt es zuerst die Gruppe.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final content = manifest.existsSync() ? manifest.readAsStringSync() : '';

  test('das main-Manifest existiert', () {
    expect(manifest.existsSync(), isTrue);
  });

  // Die Flutter-Vorlage deklariert INTERNET nur in debug/profile. Fehlt sie im
  // main-Manifest, hat ausgerechnet der Release-Build keinen Netzzugriff:
  // Supabase ist unerreichbar, der Login schlägt immer fehl – und zwar nur in
  // der veröffentlichten App, nie im Debug-Lauf oder im Web. Genau so ist
  // v0.6.0 ausgeliefert worden (Issue #7).
  test('das main-Manifest deklariert die INTERNET-Berechtigung', () {
    expect(
      content,
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
      reason:
          'Ohne INTERNET im main-Manifest kann der Release-Build den Server '
          'nicht erreichen und jeder Login scheitert.',
    );
  });

  group('In-App-Update', () {
    test('darf die geladene APK an den Installer übergeben', () {
      expect(
        content,
        contains('android.permission.REQUEST_INSTALL_PACKAGES'),
        reason: 'Ohne diese Berechtigung endet das Update nach dem Download.',
      );
    });

    // Seit Android 11 sieht eine App fremde Apps nur, wenn sie danach fragt.
    // Ohne die Abfrage liefert url_launcher still `false`: Der Knopf tut
    // sichtbar nichts – so gemeldet für v0.7.0.
    test('sieht einen Browser für die Rückfallebene', () {
      expect(content, contains('android.intent.action.VIEW'));
      expect(content, contains('android:scheme="https"'));
    });

    // ota_update erwartet exakt diese Authority. Stimmt sie nicht, stürzt die
    // App NACH erfolgreichem Download ab – nie im Test, nur beim echten
    // Update auf einem Gerät.
    test('stellt den FileProvider mit der erwarteten Authority bereit', () {
      expect(content, contains('androidx.core.content.FileProvider'));
      expect(
        content,
        contains(r'android:authorities="${applicationId}.ota_update_provider"'),
      );
      expect(content, contains('@xml/filepaths'));
    });

    test('gibt den Ablageort der APK frei', () {
      final paths = File('android/app/src/main/res/xml/filepaths.xml');
      expect(
        paths.existsSync(),
        isTrue,
        reason: 'Ohne filepaths.xml findet der FileProvider die APK nicht.',
      );
      expect(paths.readAsStringSync(), contains('ota_update/'));
    });

    test('aktiviert das von ota_update geforderte Desugaring', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(gradle, contains('coreLibraryDesugaring('));
    });
  });
}

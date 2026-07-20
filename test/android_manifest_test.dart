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

  // android:allowBackup ist standardmäßig an. Ohne Ausschluss sichert Android
  // shared_prefs ins Google-Konto und spielt sie auf einem neuen Gerät zurück
  // — samt der von supabase_flutter abgelegten Sitzung. Da eine Gruppe genau
  // einen Login hat, ist dieses Token das gemeinsame Zugangsmerkmal der
  // ganzen Gruppe. Nichts davon ist im Debug-Lauf oder im Web zu bemerken.
  group('Backup', () {
    const excluded =
        '<exclude domain="sharedpref" path="FlutterSharedPreferences.xml"/>';

    test('das Manifest verweist auf beide Regelsätze', () {
      expect(
        content,
        contains('android:fullBackupContent="@xml/backup_rules"'),
        reason:
            'Ohne fullBackupContent greift auf Android 11 und älter keine '
            'Regel — dort wandert die Sitzung weiter ins Cloud-Backup.',
      );
      expect(
        content,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason:
            'Ab Android 12 wird fullBackupContent ignoriert; ohne '
            'dataExtractionRules ist die neuere Hälfte der Geräte ungeschützt.',
      );
    });

    // Backup-Regeln adressieren ganze Dateien, nie einzelne Schlüssel:
    // supabase_flutter schreibt die Sitzung nach
    // shared_prefs/FlutterSharedPreferences.xml, also muss genau diese Datei
    // dastehen. Verlustfrei, weil shared_preferences nur transitiv über
    // supabase_flutter hereinkommt und sonst niemand hineinschreibt — sollte
    // sich das ändern, gehört diese Regel überdacht.
    test('Android 11 und älter schließt die Sitzungsdatei aus', () {
      final rules = File('android/app/src/main/res/xml/backup_rules.xml');
      expect(rules.existsSync(), isTrue, reason: 'backup_rules.xml fehlt.');
      expect(rules.readAsStringSync(), contains(excluded));
    });

    test(
      'ab Android 12 ist die Sitzung aus Cloud UND Gerätewechsel heraus',
      () {
        final rules = File(
          'android/app/src/main/res/xml/data_extraction_rules.xml',
        );
        expect(
          rules.existsSync(),
          isTrue,
          reason: 'data_extraction_rules.xml fehlt.',
        );
        final text = rules.readAsStringSync();

        final cloud = text.indexOf('<cloud-backup>');
        final transfer = text.indexOf('<device-transfer>');
        expect(cloud, isNonNegative, reason: '<cloud-backup> fehlt.');
        expect(transfer, isNonNegative, reason: '<device-transfer> fehlt.');

        // Beide Blöcke einzeln prüfen: Ein Ausschluss nur unter cloud-backup
        // ließe das Token beim direkten Gerätewechsel trotzdem mitreisen.
        final cloudBlock = text.substring(
          cloud,
          text.indexOf('</cloud-backup>'),
        );
        final transferBlock = text.substring(
          transfer,
          text.indexOf('</device-transfer>'),
        );
        expect(
          cloudBlock,
          contains(excluded),
          reason: 'Sitzung fehlt im Ausschluss für das Cloud-Backup.',
        );
        expect(
          transferBlock,
          contains(excluded),
          reason: 'Sitzung fehlt im Ausschluss für den Gerätewechsel.',
        );
      },
    );
  });
}

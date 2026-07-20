/// android_manifest_test.dart – Schützt die Netz-Berechtigung des Release-Builds.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Die Flutter-Vorlage deklariert INTERNET nur in debug/profile. Fehlt sie im
  // main-Manifest, hat ausgerechnet der Release-Build keinen Netzzugriff:
  // Supabase ist unerreichbar, der Login schlägt immer fehl – und zwar nur in
  // der veröffentlichten App, nie im Debug-Lauf oder im Web. Genau so ist
  // v0.6.0 ausgeliefert worden (Issue #7).
  test('das main-Manifest deklariert die INTERNET-Berechtigung', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    expect(
      manifest.existsSync(),
      isTrue,
      reason: 'android/app/src/main/AndroidManifest.xml fehlt',
    );

    expect(
      manifest.readAsStringSync(),
      contains('<uses-permission android:name="android.permission.INTERNET"/>'),
      reason:
          'Ohne INTERNET im main-Manifest kann der Release-Build den Server '
          'nicht erreichen und jeder Login scheitert.',
    );
  });
}

/// android_manifest_test.dart – Schützt die Android-Voraussetzungen, die
/// ausschließlich im Release auf einem echten Gerät auffallen.
///
/// Alles hier Geprüfte hat dasselbe Muster: Es lässt sich weder im Debug-Lauf
/// noch im Web bemerken. Fehlt eines, merkt es zuerst die Gruppe.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die `applicationId` ist die eine Quelle — der Kotlin-Pfad folgt ihr.
///
/// Vorher stand er dreimal ausgeschrieben im File. Beim Umzug auf
/// `de.mcbuchi.mitfahrbar` (v0.83.0) scheiterte der ganze Test deshalb mit
/// „Cannot open file" statt mit einer Aussage darüber, was nicht stimmt.
/// Abgeleitet prüft er zusätzlich etwas Echtes mit: dass Paketverzeichnis und
/// `applicationId` zusammenpassen. Tun sie das nicht, findet Gradle die
/// Activity nicht — und meldet das erst im Android-Build, nicht hier.
String _applicationId() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final match = RegExp(r'applicationId\s*=\s*"([^"]+)"').firstMatch(gradle);
  return match!.group(1)!;
}

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  final content = manifest.existsSync() ? manifest.readAsStringSync() : '';
  final activityPath =
      'android/app/src/main/kotlin/'
      '${_applicationId().replaceAll('.', '/')}/MainActivity.kt';

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

    // MainActivity.installApk erwartet exakt diese Authority. Stimmt sie
    // nicht, stürzt die App NACH erfolgreichem Download ab – nie im Test,
    // nur beim echten Update auf einem Gerät.
    test('stellt den FileProvider mit der erwarteten Authority bereit', () {
      expect(content, contains('androidx.core.content.FileProvider'));
      expect(
        content,
        contains(r'android:authorities="${applicationId}.fileprovider"'),
      );
      expect(content, contains('@xml/filepaths'));
    });

    test('gibt NUR den Update-Ordner frei', () {
      final paths = File('android/app/src/main/res/xml/filepaths.xml');
      expect(
        paths.existsSync(),
        isTrue,
        reason: 'Ohne filepaths.xml findet der FileProvider die APK nicht.',
      );
      final text = paths.readAsStringSync();
      expect(text, contains('path="updates/"'));
      // Der Pfad ist bewusst eng: Im selben Verzeichnis liegt die
      // SharedPreferences-Datei mit dem Sitzungs-Token der Gruppe, und der
      // frühere external-path stammte aus dem ota_update-Zuschnitt.
      // Kommentarfrei geprüft (die sqlOnly-Lehre): Die Datei begründet die
      // Entfernung und nennt den verbotenen Namen dabei selbst.
      expect(
        text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ''),
        isNot(contains('external-path')),
        reason:
            'Ein external-path gäbe weit mehr frei als die Update-APK — '
            'das war der Zuschnitt von ota_update, nicht unserer.',
      );
    });

    test('Kanalname in Kotlin und Dart ist derselbe', () {
      final kotlinChannel = RegExp(
        r'const val INSTALL_CHANNEL = "([^"]+)"',
      ).firstMatch(File(activityPath).readAsStringSync())?.group(1);
      final dartChannel = RegExp(r"channelName = '([^']+)'")
          .firstMatch(File('lib/data/apk_installer.dart').readAsStringSync())
          ?.group(1);
      expect(kotlinChannel, isNotNull);
      expect(
        dartChannel,
        kotlinChannel,
        reason:
            'Driften die Namen, wirft invokeMethod MissingPluginException, '
            'der catch macht daraus „kein In-App-Weg" — jedes Update liefe '
            'kommentarlos über den Browser, und niemand merkte es.',
      );
    });

    // ota_update ist raus, und das muss so bleiben: Sein Plugin-Manifest zog
    // INSTALL_PACKAGES (Signatur-Berechtigung!), READ/WRITE_EXTERNAL_STORAGE
    // und RECEIVE_BOOT_COMPLETED in JEDEN Build — mit INSTALL_PACKAGES ist
    // kein AAB einreichbar. Der eigene Weg (data/update_installer.dart)
    // kommt mit REQUEST_INSTALL_PACKAGES allein aus.
    test('ota_update kommt nicht zurück', () {
      // Ohne Kommentare prüfen (die sqlOnly-Lehre): pubspec.yaml begründet
      // die Entfernung und nennt den Namen dabei zwangsläufig selbst.
      final pubspec = File('pubspec.yaml')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('#'))
          .join('\n');
      expect(
        pubspec,
        isNot(contains('ota_update')),
        reason:
            'ota_update zieht INSTALL_PACKAGES & Co. in jeden Build — die '
            'Abhängigkeit brächte alles auf einmal zurück.',
      );
    });

    test('Desugaring bleibt an', () {
      // Einst von ota_update gefordert; ob keines der übrigen Plugins es
      // braucht, ließe sich nur am Gerät beweisen — eingeschaltet kostet es
      // nichts, ein stiller Wegfall fiele erst im Release auf.
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('isCoreLibraryDesugaringEnabled = true'));
      expect(gradle, contains('coreLibraryDesugaring('));
    });
  });

  // Zwei Vertriebswege, EINE App (Muster von PilzBuddy 1.87.1): `github`
  // behält REQUEST_INSTALL_PACKAGES fürs Selbst-Update, `play` nimmt die
  // Berechtigung heraus — Play verbietet Selbst-Updates, und eine
  // Berechtigung ohne Funktion ist in der Review die schlechtestmögliche
  // Antwort.
  group('Play-Flavor', () {
    const playManifestPath = 'android/app/src/play/AndroidManifest.xml';

    test('nimmt REQUEST_INSTALL_PACKAGES heraus — und sonst nichts', () {
      final play = File(playManifestPath);
      expect(play.existsSync(), isTrue, reason: '$playManifestPath fehlt');
      final text = play.readAsStringSync();
      expect(text, contains('android.permission.REQUEST_INSTALL_PACKAGES'));
      expect(
        text,
        contains('tools:node="remove"'),
        reason:
            'Ohne das remove ADDIERT das Flavor-Manifest die Berechtigung '
            'nur erneut, statt sie zu entfernen.',
      );
      // Genau EIN Element neben <manifest>: Jede weitere Zeile gälte nur
      // für den Play-Build und driftete still von den Geräten der
      // GitHub-Nutzer ab. Kommentare vorher wegnehmen, damit die Zählung
      // nicht an Erklärtext hängt.
      final code = text.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
      final elements = RegExp(r'<[a-z]').allMatches(code).length;
      expect(
        elements,
        2, // <manifest> selbst + <uses-permission>
        reason: 'Der Play-Flavor soll genau eine Sache tun',
      );
    });

    test('das Play-Manifest übersteht Androids strengen Parser', () {
      // Zwei aufeinanderfolgende Bindestriche sind in einem XML-Kommentar
      // verboten. Darts xml-Paket nähme sie an — Androids ManifestMerger
      // bricht ab, nach viereinhalb Minuten Gradle (in PilzBuddy live
      // passiert: die Schreibweise eines dart-define-Schalters im
      // Kommentar). Deshalb am Rohtext geprüft.
      for (final match in RegExp(
        r'<!--(.*?)-->',
        dotAll: true,
      ).allMatches(File(playManifestPath).readAsStringSync())) {
        expect(
          match.group(1),
          isNot(contains('--')),
          reason:
              '$playManifestPath: „--" im Kommentar — daran scheitert der '
              'ManifestMerger, nicht dieser Parser',
        );
      }
    });

    test('beide Flavors bauen dieselbe App', () {
      // Ohne Kommentare prüfen: Der Kommentar über den Flavors begründet,
      // warum es KEIN applicationIdSuffix gibt, und nennt das Wort dabei
      // selbst (dieselbe Lehre wie sqlOnly — in PilzBuddy genau so rot
      // geworden).
      final gradle = File('android/app/build.gradle.kts')
          .readAsStringSync()
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//.*'), '');
      for (final flavor in const ['github', 'play']) {
        expect(
          gradle,
          contains('create("$flavor")'),
          reason: 'Flavor $flavor fehlt — die Workflows rufen ihn auf',
        );
      }
      expect(
        gradle,
        isNot(contains('applicationIdSuffix')),
        reason:
            'Ein Suffix machte aus einem Vertriebsweg eine zweite App — '
            'Android sähe zwei, und der Wechsel verlöre die Installation '
            '(die Lehre aus dem Bundle-ID-Umzug #87).',
      );
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

  // Push-Benachrichtigungen (Issue #101). Dieselbe Fehlerklasse: Jede dieser
  // Voraussetzungen fehlt lautlos — die App startet, der Screen lässt sich
  // bedienen, und erst am Abend kommt bei niemandem etwas an.
  group('Push-Benachrichtigungen', () {
    test('darf ab Android 13 überhaupt fragen', () {
      expect(
        content,
        contains('android.permission.POST_NOTIFICATIONS'),
        reason:
            'Ohne die Deklaration erscheint der Berechtigungsdialog nie. Die '
            'App hält sich für abgelehnt, der Nutzer sieht keinen Fehler — '
            'und keine Benachrichtigung.',
      );
    });

    test('nennt einen eigenen Benachrichtigungs-Kanal', () {
      expect(
        content,
        contains(
          'com.google.firebase.messaging.default_notification_channel_id',
        ),
        reason:
            'Ohne Angabe legt FCM einen Kanal namens „Miscellaneous" an — '
            'die Gruppe fände in den Systemeinstellungen nicht, was sie '
            'abschalten will.',
      );
      expect(
        content,
        contains('com.google.firebase.messaging.default_notification_icon'),
        reason:
            'Ohne eigenes Icon nimmt Android das farbige Launcher-Icon und '
            'zeigt daraus eine weiße Fläche.',
      );
      expect(
        content,
        contains('android:resource="@drawable/ic_notification"'),
        reason:
            'Zeigt die Angabe wieder auf den Adaptive-Icon-Vordergrund, ist '
            'der Fehler aus #271 zurück: Dort sind die cyanen Flächen im '
            'Alphakanal genauso deckend wie der Wagen, übrig bleibt der '
            'äußere Umriss — gemeldet als „ein weißer Kreis". Nur im '
            'Benachrichtigungs-Schatten eines echten Geräts zu sehen.',
      );
      expect(
        File(
          'android/app/src/main/res/drawable/ic_notification.xml',
        ).existsSync(),
        isTrue,
        reason:
            'Der Verweis im Manifest löst nur auf, wenn die Ressource da ist '
            '— sonst bricht der Android-Build ab, und zwar erst er, nicht '
            '`flutter test`. Erzeugt von tool/brand/build_icons.sh aus '
            'tool/brand/notification.svg; nie von Hand bearbeiten.',
      );
      expect(
        File(
          'android/app/src/main/res/drawable/ic_notification.xml',
        ).readAsStringSync(),
        contains('android:fillType="evenOdd"'),
        reason:
            'Die Frontscheibe ist ein LOCH, keine dunkle Fläche. Die '
            'SystemUI wirft jede Farbe weg und behält nur den Alphakanal — '
            'ohne evenOdd wäre das Glyph wieder der weiße Klotz aus #271. '
            'Braucht API 24, und genau dort liegt unser minSdk.',
      );
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File(
            'android/app/src/main/res/drawable-$density/ic_notification.png',
          ).existsSync(),
          isFalse,
          reason:
              'Ein PNG neben dem Vektor gewinnt: Android nimmt die Fassung '
              'der passenden Dichte und der Vektor bliebe wirkungslos — '
              'stillschweigend, und nur auf einem Gerät zu sehen. Der '
              'Vektor deckt jede Dichte ab, auch die, die es noch nicht '
              'gibt.',
        );
      }
      expect(
        content,
        contains('com.google.firebase.messaging.default_notification_color'),
        reason:
            'Ohne die Angabe färbt Android das kleine Icon und die App-Zeile '
            'grau — die Meldung sähe aus wie die einer beliebigen fremden '
            'App. Nur im Benachrichtigungs-Schatten eines echten Geräts zu '
            'sehen, nie im Web und nie im Debug-Lauf.',
      );
    });

    // Der Verweis oben löst nur auf, wenn es die Ressource gibt: Fehlt sie,
    // bricht der Android-Build ab — und zwar erst er, nicht `flutter test`.
    // Die dunkle Fassung ist keine Zierde, sondern der Grund, warum der Ton
    // im dunklen Schatten überhaupt zu sehen ist; die Kontraste misst
    // `test/banner_contrast_test.dart`.
    test('die Akzentfarbe existiert in beiden Fassungen', () {
      for (final path in const [
        'android/app/src/main/res/values/colors.xml',
        'android/app/src/main/res/values-night/colors.xml',
      ]) {
        final colors = File(path);
        expect(colors.existsSync(), isTrue, reason: '$path fehlt.');
        expect(
          colors.readAsStringSync(),
          contains('name="notification_accent"'),
          reason:
              'In $path fehlt die Farbe, auf die das Manifest mit '
              '@color/notification_accent zeigt.',
        );
      }
    });

    test('legt den Kanal auch wirklich an', () {
      final activity = File(activityPath);
      expect(activity.existsSync(), isTrue);
      expect(
        activity.readAsStringSync(),
        contains('createNotificationChannel'),
        reason:
            'Das Manifest verweist auf einen Kanal. Existiert er nicht, '
            'weicht FCM still auf seinen eigenen aus — der Verweis wäre dann '
            'wirkungslos, ohne dass irgendwo ein Fehler auftaucht.',
      );
      expect(
        File('android/app/src/main/res/values/strings.xml').readAsStringSync(),
        contains('notification_channel_plan_id'),
      );
    });

    test('bindet die Firebase-Konfiguration in den Build ein', () {
      expect(
        File('android/app/google-services.json').existsSync(),
        isTrue,
        reason:
            'Ohne die Datei findet firebase_core zur Laufzeit kein Projekt '
            'und die App stürzt beim Start ab.',
      );
      expect(
        File('android/app/google-services.json').readAsStringSync(),
        contains('de.mcbuchi.mitfahrbar'),
        reason:
            'Die Konfiguration muss zum applicationId passen; sonst lehnt '
            'FCM die Registrierung ab.',
      );
      expect(
        File('android/settings.gradle.kts').readAsStringSync(),
        contains('com.google.gms.google-services'),
      );
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains('com.google.gms.google-services'),
        reason:
            'Deklariert, aber nicht angewendet: Dann wird die json nie '
            'ausgewertet — der Build bleibt grün, die App findet nichts.',
      );
    });

    // Der Web-Worker lädt das Firebase-JS von gstatic. Wählt er eine andere
    // Fassung als firebase_core_web erwartet, warnt die App im besten Fall
    // und lädt im schlechtesten eine Version, die es dort nicht mehr gibt —
    // dann bekommt die PWA still kein Token. Die erwartete Version steht im
    // Paket selbst, also prüfen wir gegen die Quelle statt gegen eine
    // abgeschriebene Zahl.
    test('der Web-Service-Worker nutzt die erwartete Firebase-JS-Version', () {
      final worker = File('web/firebase-messaging-sw.js');
      expect(worker.existsSync(), isTrue, reason: 'Ohne ihn kein Web-Push.');

      final packages =
          jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
              as Map<String, Object?>;
      final root =
          (packages['packages'] as List)
                  .cast<Map<String, Object?>>()
                  .firstWhere(
                    (p) => p['name'] == 'firebase_core_web',
                  )['rootUri']
              as String;
      // Der Schrägstrich muss sein: Ohne ihn ersetzt `resolve` das letzte
      // Segment, statt darunter zu suchen. Relative rootUri (Pfad-
      // Abhängigkeiten) gegen .dart_tool auflösen.
      final rootUri = Uri.parse('$root/');
      final base = rootUri.hasScheme
          ? rootUri
          : Uri.directory(
              Directory('.dart_tool').absolute.path,
            ).resolveUri(rootUri);
      final expected = RegExp(r"supportedFirebaseJsSdkVersion = '([^']+)'")
          .firstMatch(
            File.fromUri(
              base.resolve('lib/src/firebase_sdk_version.dart'),
            ).readAsStringSync(),
          )!
          .group(1);

      expect(
        worker.readAsStringSync(),
        contains('firebasejs/$expected/'),
        reason:
            'firebase_core_web erwartet $expected. Nach einem Dependabot-'
            'Bump muss der Service Worker mitziehen.',
      );
    });
  });

  // Issue #144: Der Weg von Androids Beendigungs-Historie in die
  // Fehler-Senke hängt an Kotlin-Code, den kein Flutter-Test ausführt —
  // dieselbe Klasse Release-only-Falle wie der FCM-Kanal.
  group('Beendigungsgründe (#144)', () {
    final mainActivity = File(activityPath).readAsStringSync();

    test('MainActivity fragt Androids Historie ab', () {
      expect(
        mainActivity,
        contains('getHistoricalProcessExitReasons'),
        reason:
            'Ohne den Aufruf liefert der Kanal still eine leere Liste — '
            'ANRs und Abstürze blieben wieder unsichtbar, und niemand '
            'merkte es, weil genau dann nichts gemeldet wird.',
      );
      expect(
        mainActivity,
        contains('makeBackgroundTaskQueue'),
        reason:
            'Der ANR-Dump ist bis zu 4 MB groß und gzip-gepackt. Auf dem '
            'Platform-Thread gelesen wäre die Diagnose selbst ein '
            'ANR-Kandidat — genau beim Start, wo ohnehin am meisten läuft.',
      );
    });

    test('Kanalname in Kotlin und Dart ist derselbe', () {
      final kotlinChannel = RegExp(
        r'const val CHANNEL = "([^"]+)"',
      ).firstMatch(mainActivity)?.group(1);
      final dartChannel = RegExp(r"channelName = '([^']+)'")
          .firstMatch(
            File('lib/data/exit_info_repository.dart').readAsStringSync(),
          )
          ?.group(1);
      expect(kotlinChannel, isNotNull);
      expect(
        dartChannel,
        kotlinChannel,
        reason:
            'Driften die Namen, wirft invokeMethod MissingPluginException, '
            'der catch macht daraus eine leere Liste — und die Meldungen '
            'fallen lautlos aus. Kompiliert fehlerfrei, fällt nur auf dem '
            'Gerät auf.',
      );
    });
  });

  group('Benachrichtigungs-Prüfung (#180)', () {
    final mainActivity = File(activityPath).readAsStringSync();
    final probe = File(
      'lib/core/notification_health_probe.dart',
    ).readAsStringSync();

    test('Kanalname der Prüf-Brücke ist in Kotlin und Dart derselbe', () {
      final kotlin = RegExp(
        r'const val HEALTH_CHANNEL = "([^"]+)"',
      ).firstMatch(mainActivity)?.group(1);
      final dart = RegExp(
        r"channelName = '([^']+)'",
      ).firstMatch(probe)?.group(1);
      expect(kotlin, isNotNull);
      expect(
        dart,
        kotlin,
        reason:
            'Driften die Namen, wirft invokeMethod MissingPluginException, '
            'der catch macht daraus „unbekannt" — und unbekannt meldet keine '
            'Blockade. Der Schirm sagte also „alles in Ordnung", während '
            'nichts ankommt: genau die stille Falschaussage, gegen die diese '
            'Prüfung gebaut wurde.',
      );
    });

    test('die geprüfte Kanal-Kennung ist die aus strings.xml', () {
      final declared =
          RegExp(
                r'<string name="notification_channel_plan_id">([^<]+)</string>',
              )
              .firstMatch(
                File(
                  'android/app/src/main/res/values/strings.xml',
                ).readAsStringSync(),
              )
              ?.group(1);
      final probed = RegExp(
        r"androidPlanChannel = '([^']+)'",
      ).firstMatch(probe)?.group(1);
      expect(declared, isNotNull);
      expect(
        probed,
        declared,
        reason:
            'Sonst fragt die App nach einem Kanal, den es nicht gibt. '
            '`getNotificationChannel` liefert dann null, die Prüfung liest '
            'das als „weiß ich nicht" und schweigt — obwohl der echte Kanal '
            'ausgeschaltet sein kann.',
      );
    });

    test('die Prüfung baut NICHT auf firebase_messaging', () {
      // Ohne Kommentare prüfen — dieselbe Lehre wie bei `sqlOnly` in
      // `schema_test.dart`: Ein File, das seine eigene Entscheidung
      // begründet, nennt den verbotenen Namen zwangsläufig. Ein Test, der
      // den Fließtext mitliest, scheitert an der Begründung statt am Code.
      final code = probe
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        code,
        isNot(contains('getNotificationSettings')),
        reason:
            'getNotificationSettings() meldet auf Android authorized, obwohl '
            'die Systemeinstellung aus ist (flutterfire#4492), und denied '
            'vor der ersten Frage auf API 34 (flutterfire#12839). Darauf '
            'gebaut wäre die Überwachung genau so unzuverlässig wie der '
            'Zustand, den sie aufdecken soll.',
      );
      expect(
        mainActivity,
        contains('areNotificationsEnabled'),
        reason:
            'Der einzige Aufruf, der Berechtigung UND Systemschalter '
            'abbildet. checkSelfPermission meldet vor Android 13 immer '
            '„verweigert", auch bei erlaubten Benachrichtigungen.',
      );
    });
  });
}

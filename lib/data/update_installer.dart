import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/update_check.dart';
import 'apk_installer.dart';

/// Warum ein Update nicht in der App installiert werden konnte.
///
/// Kein `Exception`-Typ, sondern ein Ergebnis: Jeder dieser Fälle ist
/// vorgesehen und endet im Browser-Download, nicht in einer Fehlermeldung.
enum UpdateFailure {
  /// Freigabe „Unbekannte Apps installieren" fehlt (ab Android 8).
  notAllowed,

  /// Download abgebrochen — kein Netz, Abbruch, HTTP-Fehler.
  downloadFailed,

  /// Der System-Installer ließ sich nicht öffnen.
  installFailed,
}

/// Lädt die Update-APK und übergibt sie dem System-Installer.
///
/// Der Nachbau ersetzt `ota_update`, und der Grund ist keine Kür: Dessen
/// Plugin-Manifest zog `INSTALL_PACKAGES` (Signatur-Berechtigung),
/// `READ/WRITE_EXTERNAL_STORAGE` und `RECEIVE_BOOT_COMPLETED` in JEDEN
/// Build — in PilzBuddy nachgemessen 14 statt 8 Berechtigungen, und mit
/// `INSTALL_PACKAGES` ist kein AAB einreichbar. Der eigene Weg braucht
/// genau eine: `REQUEST_INSTALL_PACKAGES` — die App *bietet* eine Datei an,
/// den Installationsdialog zeigt Android (Muster von PilzBuddy, dort #161).
class UpdateInstaller {
  UpdateInstaller({required ApkInstaller installer, http.Client? client})
    : _installer = installer,
      _client = client ?? http.Client();

  final ApkInstaller _installer;
  final http.Client _client;

  /// Steht dieser Weg auf diesem Gerät überhaupt zur Verfügung?
  bool get supported => _installer.supported;

  /// Für den Fall [UpdateFailure.notAllowed]: führt direkt zur
  /// System-Freigabe „Unbekannte Apps installieren" dieser App.
  Future<void> openInstallSettings() => _installer.openSettings();

  static const _inactivityTimeout = Duration(seconds: 60);

  /// Lädt die APK und öffnet den System-Installer.
  ///
  /// Liefert `null` bei Erfolg, sonst den Grund — der Aufrufer bietet dann
  /// den Browser an. [onProgress] bekommt 0…1, solange die Größe bekannt
  /// ist; sonst gar nichts (die Anzeige läuft dann unbestimmt).
  Future<UpdateFailure?> downloadAndInstall(
    UpdateInfo info, {
    void Function(double)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final apkUrl = info.apkUrl;
    if (apkUrl == null) return UpdateFailure.downloadFailed;
    if (!await _installer.canInstall()) return UpdateFailure.notAllowed;

    final File apk;
    try {
      apk = await _download(
        apkUrl,
        info.latestVersion,
        onProgress,
        isCancelled ?? () => false,
      );
    } catch (_) {
      return UpdateFailure.downloadFailed;
    }

    return await _installer.install(apk.path)
        ? null
        : UpdateFailure.installFailed;
  }

  Future<File> _download(
    String url,
    String version,
    void Function(double)? onProgress,
    bool Function() isCancelled,
  ) async {
    final dirPath = await _installer.updatesPath();
    if (dirPath == null) throw StateError('kein Update-Verzeichnis');
    final dir = Directory(dirPath);
    // Alte Downloads wegräumen, bevor der nächste beginnt: Eine APK wiegt
    // ~60 MB, und nach der Installation braucht sie niemand mehr. Ein
    // abgebrochener Rest bliebe sonst für immer liegen.
    await _clear(dir);

    final target = File('${dir.path}/mitfahrbar-$version.apk');
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request).timeout(_inactivityTimeout);
    if (response.statusCode != 200) {
      throw HttpException('Update-Download: HTTP ${response.statusCode}');
    }

    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in response.stream.timeout(_inactivityTimeout)) {
        if (isCancelled()) throw const _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    // Eine abgeschnittene Datei würde der Installer mit „App nicht
    // installiert" quittieren — ohne zu sagen, warum.
    if (total > 0 && received < total) {
      await target.delete();
      throw const HttpException('Update-Download unvollständig');
    }
    return target;
  }

  Future<void> _clear(Directory dir) async {
    try {
      await for (final entry in dir.list()) {
        if (entry is File) await entry.delete();
      }
    } catch (_) {
      // Aufräumen ist Kür: Scheitert es, überschreibt der Download die
      // gleichnamige Datei ohnehin.
    }
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

final updateInstallerProvider = Provider<UpdateInstaller>(
  (ref) => UpdateInstaller(installer: ref.watch(apkInstallerProvider)),
);

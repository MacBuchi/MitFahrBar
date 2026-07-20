/// update_check.dart – Prüft, ob eine neuere App-Version veröffentlicht ist.
///
/// Quelle ist das jeweils neueste GitHub-Release (tokenlos). Web lädt die
/// Seite neu, Android verweist auf die APK des Releases.
/// Grundsatz: Jeder Fehlerpfad endet in `null` – der Update-Check darf die
/// App nie stören.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const String githubRepo = 'MacBuchi/Fahrgemeinschaft';

class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    this.apkUrl,
    this.releaseNotes,
  });

  final String latestVersion;

  /// Release-Seite – Ziel für „Was ist neu" und den Web-Hinweis.
  final String releaseUrl;

  /// Direkter APK-Download (nur Android-Releases).
  final String? apkUrl;
  final String? releaseNotes;
}

/// `true`, wenn [latest] neuer als [current] ist (segmentweise numerisch,
/// damit 1.10.0 > 1.9.2 gilt). Vorabspann wie `1.5.0-rc1` wird abgeschnitten,
/// sonst wird das Segment zu 0 und ein Update stillschweigend verschluckt.
bool isNewerVersion(String latest, String current) {
  List<int> parse(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((part) => int.tryParse(part.trim()) ?? 0)
      .toList();
  final l = parse(latest);
  final c = parse(current);
  for (var i = 0; i < 3; i++) {
    final li = i < l.length ? l[i] : 0;
    final ci = i < c.length ? c[i] : 0;
    if (li != ci) return li > ci;
  }
  return false;
}

/// Laufende Version – überschreibbar, damit Tests nicht auf das
/// Plattform-Plugin angewiesen sind.
final currentVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '0.0.0';
  }
});

/// Verfügbares Update oder `null`.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    final current = await ref.watch(currentVersionProvider.future);
    final response = await http
        .get(
          Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = release['tag_name'] as String? ?? '';
    final latest = tag.startsWith('v') ? tag.substring(1) : tag;
    if (latest.isEmpty || !isNewerVersion(latest, current)) return null;

    final assets = (release['assets'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    final apk = assets
        .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
        .map((a) => a['browser_download_url'] as String);

    return UpdateInfo(
      latestVersion: latest,
      releaseUrl:
          release['html_url'] as String? ??
          'https://github.com/$githubRepo/releases/latest',
      apkUrl: apk.isEmpty ? null : apk.first,
      releaseNotes: release['body'] as String?,
    );
  } catch (_) {
    return null; // Update-Check darf die App nie stören.
  }
});

/// Auf Android gibt es eine APK zum Laden, im Web genügt ein Neuladen.
bool get updateIsDownload =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

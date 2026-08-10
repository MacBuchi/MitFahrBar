/// update_check.dart – Prüft, ob eine neuere App-Version veröffentlicht ist.
///
/// Quelle ist das jeweils neueste GitHub-Release (tokenlos). Web lädt die
/// Seite neu, Android verweist auf die APK des Releases.
/// Grundsatz: Jeder Fehlerpfad endet in `null` – der Update-Check darf die
/// App nie stören.
///
/// Seit #225 gibt es dabei **zwei Kanäle**, und der Schalter dafür steht
/// weiter unten in dieser Datei — bewusst hier und nicht in `data/` neben
/// der Geräte-Zuordnung: Gelesen wird er von [updateInfoProvider], und
/// `core/` darf `data/` nicht kennen.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_config.dart';

const String githubRepo = 'MacBuchi/MitFahrBar';

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

/// Der erste **veröffentlichte** Eintrag einer Release-Liste — Prereleases
/// eingeschlossen, Entwürfe nicht.
///
/// GitHub liefert die Liste absteigend nach Erstellungszeit, genommen wird
/// also der jüngste Stand. Ein Entwurf ist keiner: Seine Dateien sind nicht
/// öffentlich abrufbar, das In-App-Update liefe ins Leere und der Hinweis
/// nennte eine Version, die es für niemanden gibt.
Map<String, dynamic>? firstPublishedRelease(List<dynamic> releases) {
  for (final entry in releases) {
    if (entry is! Map<String, dynamic>) continue;
    if (entry['draft'] == true) continue;
    return entry;
  }
  return null;
}

/// Ein Release-Objekt als [UpdateInfo] — oder `null`, wenn es nicht neuer
/// ist als [current].
///
/// Eine Stelle für beide Kanäle: Zwei Fassungen wären zwei Antworten auf
/// „ist das ein Update", und der Unterschied fiele erst dem Tester auf.
UpdateInfo? updateFromRelease(Map<String, dynamic> release, String current) {
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
}

/// Verfügbares Update oder `null`.
///
/// Der Kanal entscheidet nur über die **Adresse**: `…/releases/latest`
/// liefert grundsätzlich kein Prerelease, `…/releases` die ganze Liste.
/// Alles danach — Versionsvergleich, APK, „Was ist neu", der Sperr-Schirm —
/// ist für beide Kanäle dasselbe.
final updateInfoProvider = FutureProvider<UpdateInfo?>((ref) async {
  try {
    final current = await ref.watch(currentVersionProvider.future);
    final prerelease = await ref.watch(prereleaseChannelProvider.future);
    final response = await http
        .get(
          Uri.parse(
            prerelease
                ? 'https://api.github.com/repos/$githubRepo/releases?per_page=10'
                : 'https://api.github.com/repos/$githubRepo/releases/latest',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;

    final decoded = jsonDecode(response.body);
    final release = prerelease
        ? firstPublishedRelease(decoded as List<dynamic>)
        : decoded as Map<String, dynamic>;
    if (release == null) return null;
    return updateFromRelease(release, current);
  } catch (_) {
    return null; // Update-Check darf die App nie stören.
  }
});

/// Release-Notes der LAUFENDEN Version — für „Über MitFahrBar".
///
/// Dieselbe einzige Quelle wie der Update-Dialog (GitHub-Release, dessen
/// Body der CHANGELOG-Auszug der Version ist) — nur das Release zum
/// eigenen Tag statt des neuesten. Und derselbe Grundsatz: Jeder
/// Fehlerpfad endet in `null`, der Abschnitt fehlt dann einfach (offline,
/// Demo-Modus, Release noch nicht angelegt).
final currentReleaseNotesProvider = FutureProvider<String?>((ref) async {
  try {
    final current = await ref.watch(currentVersionProvider.future);
    final response = await http
        .get(
          Uri.parse(
            'https://api.github.com/repos/$githubRepo/releases/tags/v$current',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return null;
    final release = jsonDecode(response.body) as Map<String, dynamic>;
    return release['body'] as String?;
  } catch (_) {
    return null; // Wie der Update-Check: darf die App nie stören.
  }
});

/// Auf Android gibt es eine APK zum Laden, im Web genügt ein Neuladen.
bool get updateIsDownload =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

// ---------------------------------------------------------------------------
// Der Vorab-Kanal (#225)
// ---------------------------------------------------------------------------

/// Wo der Schalter liegt. Wie bei der Geräte-Zuordnung (#121): im
/// Demo-Modus flüchtig — dort gibt es nichts zu behalten und entstehen die
/// README-Screenshots.
abstract class UpdateChannelStore {
  Future<bool> load();
  Future<void> save(bool prerelease);
}

class SharedPrefsUpdateChannelStore implements UpdateChannelStore {
  const SharedPrefsUpdateChannelStore();

  static const _key = 'update.prerelease';

  @override
  Future<bool> load() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;

  @override
  Future<void> save(bool prerelease) async =>
      (await SharedPreferences.getInstance()).setBool(_key, prerelease);
}

class InMemoryUpdateChannelStore implements UpdateChannelStore {
  InMemoryUpdateChannelStore([this._value = false]);

  bool _value;

  @override
  Future<bool> load() async => _value;

  @override
  Future<void> save(bool prerelease) async => _value = prerelease;
}

final updateChannelStoreProvider = Provider<UpdateChannelStore>(
  (ref) => SupabaseConfig.isConfigured
      ? const SharedPrefsUpdateChannelStore()
      : InMemoryUpdateChannelStore(),
);

/// Ob dieses Gerät Vorabversionen bekommt — **Vorgabe aus**.
///
/// Eine Einstellung dieses Geräts, keine der Gruppe: In den
/// Parameter-Screen gehört sie nicht (dort stehen Gruppenwerte in der DB,
/// Kriterium „der Wert darf die Punkte nie berühren"), und eine
/// gruppenweite Fahne machte aus dem Ausprobieren eines Einzelnen ein
/// Update für alle.
///
/// **Nur auf Android**, und der Riegel steht hier statt nur in der
/// Oberfläche: Die PWA hat eine einzige Adresse und wird ausschließlich bei
/// der Beförderung deployt (`promote.yml`). Ein eingeschalteter Kanal
/// meldete dort eine Version, die im Browser niemand bekommen kann — der
/// Hinweis zeigte auf nichts.
final prereleaseChannelProvider =
    AsyncNotifierProvider<PrereleaseChannelNotifier, bool>(
      PrereleaseChannelNotifier.new,
    );

class PrereleaseChannelNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    if (!updateIsDownload) return false;
    return ref.watch(updateChannelStoreProvider).load();
  }

  Future<void> set(bool prerelease) async {
    state = AsyncData(prerelease);
    await ref.read(updateChannelStoreProvider).save(prerelease);
  }
}

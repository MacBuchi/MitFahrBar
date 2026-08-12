/// Über welchen Kanal dieser Build ausgeliefert wird.
///
/// Der Play Store verbietet Apps, sich selbst zu aktualisieren oder Nutzer
/// zu APK-Downloads zu schicken („Device and Network Abuse"). Im Play-Build
/// entfällt deshalb der komplette Update-Pfad — Check, Banner, Dialog und
/// der Vorab-Kanal-Schalter; dort aktualisiert der Store. Die GitHub-APK
/// behält alles, weil sie sonst niemand aktualisiert.
///
/// Der Riegel steht in den Providern (`updateInfoProvider`,
/// `prereleaseChannelProvider`), nicht nur in der Oberfläche — sonst ließe
/// er sich im Play-Build umlegen, ohne dass je etwas passiert (dieselbe
/// Lehre wie beim Vorab-Kanal, #225).
///
/// Gesetzt beim Bauen: `flutter build appbundle --dart-define=PLAY_BUILD=true`
/// (siehe `.github/workflows/release.yml`). Ohne das Flag gilt der
/// GitHub-Kanal — der Standard für lokale Builds, die veröffentlichte APK
/// und das Web (die PWA bekommt ihre Fassung ohnehin nur über den
/// Pages-Deploy der Beförderung).
abstract final class AppDistribution {
  static const isPlayBuild = bool.fromEnvironment('PLAY_BUILD');

  /// Zeigt die App selbst auf Updates hin? Nur außerhalb des Play Stores.
  static const showsUpdateHints = !isPlayBuild;
}

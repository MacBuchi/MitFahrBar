/// invite_text.dart – Einladungstext für neue Mitglieder.
///
/// Reine Textbildung, damit sie ohne Plattform testbar ist — dieselbe
/// Trennung wie bei `csv_export.dart`.
///
/// **Der Text kann das Gruppenpasswort enthalten** (bewusste Entscheidung,
/// damit eine Einladung ein Schritt bleibt). Daraus folgen zwei Regeln, die
/// überall gelten, wo dieser Text auftaucht:
///
/// * Er wird **nie geloggt.** `core/log.dart` hält die letzten Zeilen in
///   `logRing`, und die kann eine Nutzerin einer Rückmeldung anhängen — die
///   der Feedback-Bot in ein **öffentliches** GitHub-Issue verwandelt.
/// * Er wird **nie gespeichert.** Das Passwort lebt nur so lange, wie der
///   Dialog offen ist.
library;

/// Web-App der Gruppe. Groß-F ist Absicht: GitHub Pages ist
/// groß-/kleinschreibungsempfindlich.
const inviteWebUrl = 'https://macbuchi.github.io/Fahrgemeinschaft/';

/// Android-Installation läuft über das jeweils neueste Release.
const inviteApkUrl =
    'https://github.com/MacBuchi/Fahrgemeinschaft/releases/latest';

/// Baut die Einladung.
///
/// Ohne [password] endet der Text mit dem Hinweis, dass das Passwort separat
/// kommt — die sichere Variante bleibt damit einen Tastendruck entfernt.
String buildInviteText({
  required String groupName,
  required String handle,
  String? password,
}) {
  final hasPassword = password != null && password.trim().isNotEmpty;
  return [
    'Komm in unsere RideBuddy-Gruppe „$groupName"!',
    '',
    'Am Handy (Android): $inviteApkUrl',
    'Im Browser: $inviteWebUrl',
    '',
    'Zugang: $handle',
    if (hasPassword)
      'Passwort: ${password.trim()}'
    else
      'Das Passwort bekommst du von mir.',
  ].join('\n');
}

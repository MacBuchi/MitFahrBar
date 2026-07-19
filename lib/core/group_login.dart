/// group_login.dart – Abbildung Gruppen-Handle <-> interne Login-E-Mail.
///
/// Supabase-Passwort-Login braucht technisch eine E-Mail. Nutzer geben nur
/// den Gruppen-Handle ein; intern wird eine feste, nie sichtbare Domain
/// angehängt. Die Adresse muss weder echt noch zustellbar sein.
library;

const String groupLoginDomain = 'grp.fahrgemeinschaft.app';

/// Normalisiert die Nutzereingabe zu einem gültigen Handle.
String normalizeHandle(String input) => input
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._-]'), '');

String handleToEmail(String handle) =>
    '${normalizeHandle(handle)}@$groupLoginDomain';

/// Login-Kennung auflösen: Wer eine volle E-Mail eingibt (Bestands-Accounts),
/// nutzt sie direkt; sonst wird der Handle zur internen E-Mail gemappt.
String resolveLoginEmail(String input) {
  final trimmed = input.trim();
  return trimmed.contains('@') ? trimmed.toLowerCase() : handleToEmail(trimmed);
}

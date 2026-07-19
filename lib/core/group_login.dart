/// group_login.dart – Abbildung Gruppen-Handle <-> interne Login-E-Mail.
///
/// Supabase-Passwort-Login braucht technisch eine E-Mail. Nutzer geben nur
/// den Gruppen-Handle ein; intern wird eine feste, nie sichtbare Domain
/// angehängt. Die Adresse muss weder echt noch zustellbar sein.
library;

const String groupLoginDomain = 'grp.local';

/// Normalisiert die Nutzereingabe zu einem gültigen Handle.
String normalizeHandle(String input) => input
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9._-]'), '');

String handleToEmail(String handle) =>
    '${normalizeHandle(handle)}@$groupLoginDomain';

/// supabase_config.dart – Zugangsdaten des Supabase-Projekts.
///
/// Der Publishable-Key ist bewusst öffentlich — die Sicherheit liegt
/// vollständig in den Row-Level-Security-Policies (supabase/schema.sql).
/// Solange die Platzhalter nicht ersetzt sind, startet die App im
/// Demo-Modus mit In-Memory-Daten (kein Login nötig).
///
/// Beide Werte lassen sich zur Build-Zeit übersteuern, ohne diese Datei
/// anzufassen — so baut man Test-Builds gegen ein anderes Backend
/// (z. B. den lokalen Supabase-Stack) oder den Demo-Modus:
///
///   flutter build web \
///     --dart-define=SUPABASE_URL=http://192.168.1.50:54321 \
///     --dart-define=SUPABASE_KEY=anon-key-des-teststacks
///
///   --dart-define=SUPABASE_URL=https://REPLACE-ME.supabase.co  → Demo-Modus
library;

class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://azrlhlcxhpwmxcinjovp.supabase.co',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_Fs71LcKOZdxBBFtrwQU6Tg_e9oDEzCs',
  );

  static const isConfigured = url != 'https://REPLACE-ME.supabase.co';
}

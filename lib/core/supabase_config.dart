/// supabase_config.dart – Zugangsdaten des Supabase-Projekts.
///
/// Der Publishable-Key ist bewusst öffentlich — die Sicherheit liegt
/// vollständig in den Row-Level-Security-Policies (supabase/schema.sql).
/// Solange die Platzhalter nicht ersetzt sind, startet die App im
/// Demo-Modus mit In-Memory-Daten (kein Login nötig).
library;

class SupabaseConfig {
  static const url = 'https://REPLACE-ME.supabase.co';
  static const publishableKey = 'sb_publishable_Fs71LcKOZdxBBFtrwQU6Tg_e9oDEzCs';

  static const isConfigured = url != 'https://REPLACE-ME.supabase.co';
}

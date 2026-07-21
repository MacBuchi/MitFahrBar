/// app_config_repository.dart – Gruppenübergreifende Konfiguration lesen.
///
/// Zurzeit nur die Mindestversion (Issue #19). Die Tabelle ist für Clients
/// **nur lesbar**; geschrieben wird sie ausschließlich von Migrationen.
///
/// Grundsatz wie beim Update-Check: **Jeder Fehlerpfad endet in `null`.**
/// Offline, Tabelle fehlt, Zeile fehlt — nichts davon darf die App sperren.
/// Eine Sperre, die aus einem Netzwerkfehler entsteht, wäre schlimmer als
/// der veraltete Client, den sie verhindern soll.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';

abstract class AppConfigRepository {
  /// Kleinste noch unterstützte App-Version, oder `null` wenn unbekannt.
  Future<String?> minSupportedVersion();
}

class SupabaseAppConfigRepository implements AppConfigRepository {
  SupabaseAppConfigRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> minSupportedVersion() async {
    try {
      final row = await _client
          .from('app_config')
          .select('value')
          .eq('key', 'min_supported_version')
          .maybeSingle();
      final value = row?['value'] as String?;
      return (value == null || value.isEmpty) ? null : value;
    } catch (error) {
      // Kein Personenbezug in der Meldung — Log-Zeilen können per
      // Rückmeldung in einem öffentlichen Issue landen.
      log.w('min supported version unavailable: $error');
      return null;
    }
  }
}

/// Demo-Modus: keine Datenbank, also keine Mindestversion.
class NoopAppConfigRepository implements AppConfigRepository {
  @override
  Future<String?> minSupportedVersion() async => null;
}

/// push_outbox_repository.dart – Schreibt den Ausgangskorb (Issue #132).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/push_outbox.dart';

abstract class PushOutboxRepository {
  /// Legt den Ausgangskorb der Gruppe neu an.
  ///
  /// [keepFrom] ist der erste Tag, der stehen bleiben soll — alles davor
  /// wird weggeräumt. Ohne das wüchse die Tabelle mit jedem Tag, und die
  /// Zusage „beschränkt auf Personen × Planwoche" wäre falsch.
  Future<void> publish(List<OutboxEntry> entries, {required DateTime keepFrom});
}

class SupabasePushOutboxRepository implements PushOutboxRepository {
  SupabasePushOutboxRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> publish(
    List<OutboxEntry> entries, {
    required DateTime keepFrom,
  }) async {
    // Über eine SECURITY-DEFINER-Funktion statt direkt auf die Tabelle, und
    // das ist keine Vorliebe: „schreiben ja, lesen nein" ist an der Tabelle
    // nicht zu haben. Postgres verlangt für `on conflict do update` das
    // SELECT-Recht; gibt man es und lässt die SELECT-Policy weg, scheitert
    // der Upsert daran, dass die bestehende Zeile unsichtbar ist. Der Text
    // nennt aber den vorgeschlagenen Fahrer — er darf nicht zurücklesbar
    // sein, sonst entstünde neben `fairness.dart` eine zweite Wahrheit.
    await _client.rpc<void>(
      'publish_push_outbox',
      params: {
        'entries': [for (final entry in entries) entry.toJson()],
        'keep_from':
            '${keepFrom.year.toString().padLeft(4, '0')}-'
            '${keepFrom.month.toString().padLeft(2, '0')}-'
            '${keepFrom.day.toString().padLeft(2, '0')}',
      },
    );
  }
}

/// Im Demo-Modus gibt es kein Backend — und nichts zu benachrichtigen.
class NoopPushOutboxRepository implements PushOutboxRepository {
  @override
  Future<void> publish(
    List<OutboxEntry> entries, {
    required DateTime keepFrom,
  }) async {}
}

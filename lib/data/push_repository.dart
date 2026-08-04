/// push_repository.dart – Registrierung und Einstellungen für die
/// Push-Benachrichtigungen (Issue #101).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_prefs.dart';
import 'read_retry.dart';

/// Was dieses Gerät gerade ist: wem es zugeordnet ist und was diese Person
/// eingestellt hat. `personId == null` heißt „registriert, aber niemandem
/// zugeordnet" — dann kommt hier nichts an.
class PushState {
  const PushState({this.personId, this.prefs});

  final String? personId;
  final NotificationPrefs? prefs;

  bool get active => personId != null && prefs != null;
}

abstract class PushRepository {
  /// Wem ist dieses Gerät zugeordnet, und was hat die Person eingestellt?
  Future<PushState> stateFor(String token);

  /// Ordnet dieses Gerät einer Person zu (oder niemandem).
  ///
  /// Läuft über eine SECURITY-DEFINER-Funktion, weil ein Gerät die Gruppe
  /// wechseln kann: Seine alte Zeile liegt dann unter fremder `group_id`,
  /// die RLS zeigt sie nicht, und ein blanker Upsert liefe in eine
  /// Unique-Verletzung auf einer unsichtbaren Zeile.
  Future<void> register({
    required String token,
    required String? personId,
    required String platform,
  });

  /// Beim Abmelden — das Token gehört zur Gruppe, nicht zum Gerät.
  Future<void> unregister(String token);

  Future<void> savePrefs(NotificationPrefs prefs);

  /// Schaltet für diese Person alles ab (Zeile weg = keine Nachrichten).
  Future<void> deletePrefs(String personId);

  /// Schickt eine Nachricht an genau dieses Gerät, damit man das Ankommen
  /// prüfen kann, ohne bis 21 Uhr zu warten.
  ///
  /// Liefert `true`, wenn FCM sie **angenommen** hat. Das Ergebnis nicht
  /// anzusehen wäre bequem und falsch: Die Function antwortet auch dann mit
  /// 200, wenn der Versand scheiterte — sie meldet den Ausgang je Gerät im
  /// Rumpf. Bis 0.39.0 quittierte der Screen deshalb jeden Fehlschlag mit
  /// „unterwegs", dieselbe Klasse Fehler wie der tote Update-Knopf: ein
  /// Erfolg, den niemand geprüft hat.
  Future<bool> sendTest(String token);
}

class SupabasePushRepository implements PushRepository {
  SupabasePushRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<PushState> stateFor(String token) => readTolerant(() async {
    final device = await _client
        .from('push_devices')
        .select('person_id')
        .eq('token', token)
        .maybeSingle();
    final personId = device?['person_id'] as String?;
    if (personId == null) return const PushState();

    final prefs = await _client
        .from('notification_prefs')
        .select()
        .eq('person_id', personId)
        .maybeSingle();
    return PushState(
      personId: personId,
      prefs: prefs == null ? null : NotificationPrefs.fromJson(prefs),
    );
  });

  @override
  Future<void> register({
    required String token,
    required String? personId,
    required String platform,
  }) => _client.rpc<void>(
    'register_push_device',
    params: {
      'device_token': token,
      'person': personId,
      'device_platform': platform,
    },
  );

  @override
  Future<void> unregister(String token) => _client.rpc<void>(
    'unregister_push_device',
    params: {'device_token': token},
  );

  @override
  Future<void> savePrefs(NotificationPrefs prefs) async {
    await _client.from('notification_prefs').upsert({
      'group_id': _client.auth.currentUser?.id,
      ...prefs.toJson(),
    }, onConflict: 'group_id,person_id');
  }

  @override
  Future<void> deletePrefs(String personId) async {
    await _client.from('notification_prefs').delete().eq('person_id', personId);
  }

  @override
  Future<bool> sendTest(String token) async {
    final response = await _client.functions.invoke(
      'send-push',
      body: {'test': token},
    );
    // `results` ist eine Liste `{token, status}` — 'ok', 'unregistered' oder
    // 'error'. Ein leeres oder unerwartetes Ergebnis gilt als Fehlschlag:
    // lieber einmal zu viel gemeldet als ein stiller.
    final results = (response.data as Map?)?['results'];
    if (results is! List) return false;
    return results.any((r) => (r as Map?)?['status'] == 'ok');
  }
}

/// Demo-Modus: Es gibt keinen Zugang, an den etwas zugestellt werden könnte.
class NoopPushRepository implements PushRepository {
  @override
  Future<PushState> stateFor(String token) async => const PushState();

  @override
  Future<void> register({
    required String token,
    required String? personId,
    required String platform,
  }) async {}

  @override
  Future<void> unregister(String token) async {}

  @override
  Future<void> savePrefs(NotificationPrefs prefs) async {}

  @override
  Future<void> deletePrefs(String personId) async {}

  @override
  Future<bool> sendTest(String token) async => false;
}

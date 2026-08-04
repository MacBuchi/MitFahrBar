/// admin_repository.dart – Die Verwalter-Konsole (Issue #55, #106).
///
/// Alle Aktionen laufen über SECURITY-DEFINER-Funktionen in der Datenbank —
/// das Admin-Konto hat keinerlei direkten Tabellenzugriff (anderer uid,
/// RLS blockt, `group_admins` hat bewusst keine Policies). Server-Fehler
/// tragen feste Marker; hier werden sie zu getypten Ausnahmen, damit nie
/// ein roher Fehlertext ins UI oder Log wandert.
///
/// Ein Konto verwaltet bis zu [groupCap] Gruppen, deshalb nennt jede Aktion
/// ihre Gruppe. Das Anlegen ist die eine Ausnahme vom RPC-Muster: Es braucht
/// einen echten Auth-User samt Passwort und läuft über die Edge Function
/// `request-group` (siehe deren Kopfkommentar).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/group_login.dart';
import 'read_retry.dart';

/// Wie viele Gruppen ein Verwalter-Konto tragen darf. Entscheidend ist der
/// Trigger `group_admins_cap` in der Datenbank — dieser Wert steuert nur, ob
/// die Konsole das Anlege-Formular noch zeigt.
const groupCap = 5;

/// Handle + Gruppenpasswort stimmen nicht (oder die Gruppe ist nicht aktiv).
class WrongGroupCredentials implements Exception {}

/// Die Gruppe hat schon ein Verwalter-Konto — die Verknüpfung ist eingerastet.
class GroupAlreadyClaimed implements Exception {}

/// Das eigene Admin-Passwort war falsch (Sudo-Abfrage vor dem Löschen).
class WrongAdminPassword implements Exception {}

/// Der getippte Handle stimmt nicht mit der gewählten Gruppe überein.
class HandleMismatch implements Exception {}

/// Der Anmeldename ist schon vergeben.
class HandleTakenException implements Exception {
  const HandleTakenException();
}

/// Dieses Konto verwaltet bereits [groupCap] Gruppen.
class GroupLimitReached implements Exception {
  const GroupLimitReached();
}

/// Eine verwaltete Gruppe, wie die Konsole sie anzeigt.
class AdminGroup {
  const AdminGroup({
    required this.id,
    required this.handle,
    required this.name,
  });

  final String id;
  final String handle;
  final String name;
}

abstract class AdminRepository {
  /// Legt eine neue Gruppe an — sofort aktiv und mit diesem Konto verknüpft.
  Future<void> createGroup({
    required String handle,
    required String password,
    required String groupName,
  });

  /// Verknüpft das angemeldete Verwalter-Konto mit einer **bestehenden**
  /// Gruppe. Beweis ist das Gruppen-Login; nur möglich, solange die Gruppe
  /// keinen Admin hat.
  Future<void> claimGroup(String handle, String groupPassword);

  /// Alle verwalteten Gruppen, älteste zuerst — leer, wenn keine.
  Future<List<AdminGroup>> myAdminGroups();

  /// Setzt das Passwort des Gruppen-Kontos neu (die Rettungsleine).
  Future<void> resetGroupPassword({
    required String groupId,
    required String newPassword,
  });

  /// Löst die Verknüpfung — die Übergabe (Issue #73). Verlangt das eigene
  /// Admin-Passwort erneut; danach kann ein anderes Konto neu einrasten.
  /// Gruppendaten und dieses Konto bleiben unberührt.
  Future<void> releaseGroup({
    required String groupId,
    required String adminPassword,
  });

  /// Löscht **die Gruppe** endgültig. Verlangt das eigene Admin-Passwort
  /// erneut und den getippten Handle. Das Verwalter-Konto bleibt bestehen —
  /// es trägt womöglich weitere Gruppen.
  Future<void> deleteGroup({
    required String groupId,
    required String adminPassword,
    required String handleConfirmation,
  });
}

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  /// Übersetzt die festen Server-Marker; alles andere wird unverändert
  /// weitergeworfen (und vom UI als allgemeiner Fehler gemeldet).
  Never _mapError(Object error) {
    final message = error is PostgrestException ? error.message : '$error';
    if (message.contains('wrong group credentials')) {
      throw WrongGroupCredentials();
    }
    if (message.contains('group already claimed')) throw GroupAlreadyClaimed();
    if (message.contains('group limit reached')) {
      throw const GroupLimitReached();
    }
    if (message.contains('wrong admin password')) throw WrongAdminPassword();
    if (message.contains('handle mismatch')) throw HandleMismatch();
    throw error; // ignore: only_throw_errors
  }

  @override
  Future<void> createGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {
    // Über die Edge Function statt per RPC: Ein Gruppen-Login ist ein echter
    // Auth-User mit Passwort, und den erzeugt nur GoTrue. Die Function prüft
    // dabei, dass wirklich ein bestätigtes Verwalter-Konto ruft.
    try {
      await _client.functions.invoke(
        'request-group',
        body: {
          'handle': normalizeHandle(handle),
          'password': password,
          'groupName': groupName,
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 409) throw const HandleTakenException();
      if (e.status == 429) throw const GroupLimitReached();
      rethrow;
    }
  }

  @override
  Future<void> claimGroup(String handle, String groupPassword) async {
    try {
      await _client.rpc<void>(
        'claim_admin_group',
        params: {'claim_handle': handle, 'group_password': groupPassword},
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<List<AdminGroup>> myAdminGroups() => readTolerant(() async {
    final rows = await _client.rpc<List<dynamic>>('my_admin_groups');
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        AdminGroup(
          id: row['group_id'] as String,
          handle: row['handle'] as String,
          name: row['name'] as String,
        ),
    ];
  });

  @override
  Future<void> resetGroupPassword({
    required String groupId,
    required String newPassword,
  }) async {
    try {
      await _client.rpc<void>(
        'admin_reset_group_password',
        params: {'target_group': groupId, 'new_password': newPassword},
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<void> releaseGroup({
    required String groupId,
    required String adminPassword,
  }) async {
    try {
      await _client.rpc<void>(
        'admin_release_group',
        params: {'target_group': groupId, 'admin_password': adminPassword},
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String adminPassword,
    required String handleConfirmation,
  }) async {
    try {
      await _client.rpc<void>(
        'admin_delete_group',
        params: {
          'target_group': groupId,
          'admin_password': adminPassword,
          'handle_confirmation': handleConfirmation,
        },
      );
    } catch (error) {
      _mapError(error);
    }
  }
}

/// Demo-Modus: keine Konsole (es gibt keinen echten Zugang zu verwalten).
class NoopAdminRepository implements AdminRepository {
  @override
  Future<void> createGroup({
    required String handle,
    required String password,
    required String groupName,
  }) async {}

  @override
  Future<void> claimGroup(String handle, String groupPassword) async {}

  @override
  Future<List<AdminGroup>> myAdminGroups() async => const [];

  @override
  Future<void> resetGroupPassword({
    required String groupId,
    required String newPassword,
  }) async {}

  @override
  Future<void> releaseGroup({
    required String groupId,
    required String adminPassword,
  }) async {}

  @override
  Future<void> deleteGroup({
    required String groupId,
    required String adminPassword,
    required String handleConfirmation,
  }) async {}
}

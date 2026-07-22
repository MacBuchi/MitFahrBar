/// admin_repository.dart – Die Verwalter-Konsole (Issue #55).
///
/// Alle Aktionen laufen über SECURITY-DEFINER-Funktionen in der Datenbank —
/// das Admin-Konto hat keinerlei direkten Tabellenzugriff (anderer uid,
/// RLS blockt, `group_admins` hat bewusst keine Policies). Server-Fehler
/// tragen feste Marker; hier werden sie zu getypten Ausnahmen, damit nie
/// ein roher Fehlertext ins UI oder Log wandert.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Handle + Gruppenpasswort stimmen nicht (oder die Gruppe ist nicht aktiv).
class WrongGroupCredentials implements Exception {}

/// Die Gruppe hat schon ein Verwalter-Konto — die Verknüpfung ist eingerastet.
class GroupAlreadyClaimed implements Exception {}

/// Das eigene Admin-Passwort war falsch (Sudo-Abfrage vor dem Löschen).
class WrongAdminPassword implements Exception {}

/// Der getippte Handle stimmt nicht mit der verknüpften Gruppe überein.
class HandleMismatch implements Exception {}

/// Die verknüpfte Gruppe, wie die Konsole sie anzeigt.
class AdminGroup {
  const AdminGroup({required this.handle, required this.name});

  final String handle;
  final String name;
}

abstract class AdminRepository {
  /// Verknüpft das angemeldete Verwalter-Konto mit einer Gruppe. Beweis ist
  /// das Gruppen-Login; nur möglich, solange die Gruppe keinen Admin hat.
  Future<void> claimGroup(String handle, String groupPassword);

  /// Die verknüpfte Gruppe — `null`, wenn noch keine verknüpft ist.
  Future<AdminGroup?> myAdminGroup();

  /// Setzt das Passwort des Gruppen-Kontos neu (die Rettungsleine).
  Future<void> resetGroupPassword(String newPassword);

  /// Löscht Gruppe und Verwalter-Konto endgültig. Verlangt das eigene
  /// Admin-Passwort erneut und den getippten Handle.
  Future<void> deleteGroup({
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
    if (message.contains('group already claimed') ||
        message.contains('admin already linked')) {
      throw GroupAlreadyClaimed();
    }
    if (message.contains('wrong admin password')) throw WrongAdminPassword();
    if (message.contains('handle mismatch')) throw HandleMismatch();
    throw error; // ignore: only_throw_errors
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
  Future<AdminGroup?> myAdminGroup() async {
    final rows = await _client.rpc<List<dynamic>>('my_admin_group');
    if (rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    return AdminGroup(
      handle: row['handle'] as String,
      name: row['name'] as String,
    );
  }

  @override
  Future<void> resetGroupPassword(String newPassword) async {
    try {
      await _client.rpc<void>(
        'admin_reset_group_password',
        params: {'new_password': newPassword},
      );
    } catch (error) {
      _mapError(error);
    }
  }

  @override
  Future<void> deleteGroup({
    required String adminPassword,
    required String handleConfirmation,
  }) async {
    try {
      await _client.rpc<void>(
        'admin_delete_group',
        params: {
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
  Future<void> claimGroup(String handle, String groupPassword) async {}

  @override
  Future<AdminGroup?> myAdminGroup() async => null;

  @override
  Future<void> resetGroupPassword(String newPassword) async {}

  @override
  Future<void> deleteGroup({
    required String adminPassword,
    required String handleConfirmation,
  }) async {}
}

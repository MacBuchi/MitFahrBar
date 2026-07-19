/// group_repository.dart – Gruppen-Verwaltung (eigene Gruppe, Freigaben).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';

abstract class GroupRepository {
  /// Die Gruppe des aktuell eingeloggten Accounts (null wenn keine).
  Future<Group?> myGroup();

  /// Alle Gruppen mit Status 'pending' (nur für Admins sichtbar/relevant).
  Future<List<Group>> pendingGroups();

  Future<void> setStatus(String groupId, GroupStatus status);
}

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Group?> myGroup() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row =
        await _client.from('groups').select().eq('id', uid).maybeSingle();
    return row == null ? null : Group.fromJson(row);
  }

  @override
  Future<List<Group>> pendingGroups() async {
    final rows = await _client
        .from('groups')
        .select()
        .eq('status', 'pending')
        .order('created_at');
    return rows.map(Group.fromJson).toList();
  }

  @override
  Future<void> setStatus(String groupId, GroupStatus status) async {
    await _client
        .from('groups')
        .update({'status': status.name}).eq('id', groupId);
  }
}

/// Demo-Modus: eine feste aktive Admin-Gruppe, keine Anfragen.
class DemoGroupRepository implements GroupRepository {
  @override
  Future<Group?> myGroup() async => const Group(
        id: 'demo',
        name: 'Demo-Fahrgemeinschaft',
        handle: 'demo',
        status: GroupStatus.active,
        isAdmin: true,
      );

  @override
  Future<List<Group>> pendingGroups() async => const [];

  @override
  Future<void> setStatus(String groupId, GroupStatus status) async {}
}

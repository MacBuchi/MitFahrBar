/// group_repository.dart – Die eigene Gruppe lesen.
///
/// Bewusst nur lesend: Seit #108 hat `groups` keine Update-Policy mehr, und es
/// gibt keine Freigabe-Liste. Statuswechsel passieren ausschließlich in den
/// SECURITY-DEFINER-Funktionen der Konsole (`data/admin_repository.dart`).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group.dart';

abstract class GroupRepository {
  /// Die Gruppe des aktuell eingeloggten Accounts (null wenn keine).
  Future<Group?> myGroup();
}

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Group?> myGroup() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _client
        .from('groups')
        .select()
        .eq('id', uid)
        .maybeSingle();
    return row == null ? null : Group.fromJson(row);
  }
}

/// Demo-Modus: eine feste aktive Gruppe.
class DemoGroupRepository implements GroupRepository {
  @override
  Future<Group?> myGroup() async => const Group(
    id: 'demo',
    name: 'Demo-Fahrgemeinschaft',
    handle: 'demo',
    status: GroupStatus.active,
  );
}

/// schema_test.dart – Schützt Mandanten-Annahmen, die nur in der echten
/// Datenbank auffallen.
///
/// Dieselbe Fehlerklasse wie `android_manifest_test.dart`: Ein Schlüssel ohne
/// `group_id` kompiliert sauber, läuft im Test gegen das In-Memory-Backend
/// durch und fällt erst auf, wenn eine **zweite** Gruppe dasselbe tut.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = File('supabase/schema.sql').readAsStringSync();
  final repository = File(
    'lib/data/supabase_repository.dart',
  ).readAsStringSync();

  /// Der `primary key (...)`-Ausdruck aus dem `create table`-Block von
  /// [table].
  String primaryKeyOf(String table) {
    final block = RegExp(
      'create table public\\.$table \\((.*?)\\n\\);',
      dotAll: true,
    ).firstMatch(schema);
    expect(block, isNotNull, reason: 'Tabelle $table nicht in schema.sql');
    final key = RegExp(r'primary key \(([^)]*)\)').firstMatch(block!.group(1)!);
    expect(key, isNotNull, reason: '$table hat keinen primary key');
    return key!.group(1)!;
  }

  // Die Tabellen mit fachlichem (statt generiertem) Schlüssel. Bei `persons`
  // und `trips` ist der Schlüssel eine UUID und damit ohnehin global
  // eindeutig — dort wäre `group_id` im Schlüssel sinnlos.
  for (final table in ['plan_availability', 'plan_overrides']) {
    test('$table hat group_id im Primärschlüssel', () {
      expect(
        primaryKeyOf(table),
        contains('group_id'),
        reason:
            'Ohne group_id ist der Schlüssel über alle Gruppen eindeutig: '
            'Sobald eine zweite Gruppe denselben Tag plant, bricht ihr '
            'upsert mit einer Unique-Verletzung ab — auf einer Zeile, die '
            'die RLS ihr nicht einmal zeigt. Genau so lag plan_overrides '
            'bis v0.15.0 im Schema.',
      );
    });
  }

  // Weicht das Konfliktziel vom Schlüssel ab, meldet Postgres beim Speichern
  // „there is no unique or exclusion constraint matching the ON CONFLICT
  // specification". Auch das sieht man erst am Gerät.
  test('die upsert-Konfliktziele nennen genau den Primärschlüssel', () {
    final targets = RegExp(
      r"onConflict: '([^']*)'",
    ).allMatches(repository).map((m) => m.group(1)).toList();

    expect(
      targets,
      contains(primaryKeyOf('plan_availability').replaceAll(' ', '')),
      reason: 'setAvailability muss auf den vollen Schlüssel upserten.',
    );
    expect(
      targets,
      contains(primaryKeyOf('plan_overrides').replaceAll(' ', '')),
      reason: 'setPlanDriver muss auf den vollen Schlüssel upserten.',
    );
  });
}

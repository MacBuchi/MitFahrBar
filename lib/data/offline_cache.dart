/// offline_cache.dart – Der letzte bekannte Stand, damit die App ohne Netz
/// überhaupt etwas zeigen kann (Issue #169).
///
/// Bis v0.60.0 las jeder Screen live; ohne Empfang gab es nichts. Seit
/// v0.60.0 ist wenigstens der Weg zurück da (`_GateErrorScreen`), aber leer
/// blieb der Schirm trotzdem. Hier liegt jetzt der Stand, aus dem die App
/// startet, wenn das Netz schweigt.
///
/// Vier Regeln, und die erste ist die, an der alles hängt:
///
/// * **Gespeichert werden Zeilen, nie Kennzahlen.** Punkte, Quote, Ersparnis
///   und der vorgeschlagene Fahrer entstehen weiter in `core/fairness.dart`
///   aus diesen Zeilen. Läge eine berechnete Zahl im Speicher, gäbe es zwei
///   Wahrheiten über dieselbe Woche — genau das, was `plan_overrides` und
///   `push_outbox` an ihren jeweiligen Stellen vermeiden.
/// * **Je Gruppe getrennt, und Fremdes wird gelöscht.** Der Schlüssel trägt
///   die `group_id`; meldet sich eine andere Gruppe an, fliegen die Einträge
///   aller übrigen raus. Das ist die Mandantentrennung der RLS, auf dem
///   Gerät nachgezogen — ein geteiltes Handy darf nicht die Fahrten der
///   vorigen Gruppe zeigen.
/// * **Geschrieben wird nur nach einem erfolgreichen Netz-Lesezugriff.** Ein
///   Treffer aus dem Speicher darf seinen eigenen Zeitstempel nicht
///   auffrischen, sonst altert der Stand nie und die Leiste im Kopf log.
/// * **Ein Fehler beim Speichern ist kein Fehler.** Volle Platte, verweigerte
///   Freigabe, kaputter Eintrag: Alles endet still ohne Zwischenspeicher.
///   Dieselbe Linie wie bei `initPushMessaging` — die App muss starten.
///
/// Bewusst **nicht** drin: das Preisarchiv (`price_week`). Es sind mit
/// Abstand die meisten Zeilen, und ein Diagramm ohne Empfang zu haben war der
/// schwächste der Wünsche (entschieden mit Marcus, 05.08.2026).
///
/// Die Ablage ist SharedPreferences, wie bei der Geräte-Zuordnung. Damit gilt
/// auch deren Folge: `FlutterSharedPreferences.xml` ist vom Android-Backup
/// ausgeschlossen (dort liegt das Sitzungs-Token), der Zwischenspeicher
/// überlebt also keinen Gerätewechsel. Das ist richtig so — ein neues Gerät
/// gehört oft einer anderen Person.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/log.dart';

/// Ein gespeicherter Stand samt dem Zeitpunkt, an dem er vom Server kam.
class CachedAt<T> {
  const CachedAt(this.value, this.storedAt);

  final T value;

  /// Wann dieser Stand wirklich vom Server geholt wurde — die Zahl, die
  /// oben in der Leiste steht. Ohne sie hielte man einen alten Plan für den
  /// aktuellen und führe zur falschen Zeit los.
  final DateTime storedAt;
}

/// Die Ablage. Eine Implementierung fürs Gerät, eine für Tests.
abstract class OfflineCache {
  /// Liest den Stand zu [key] der Gruppe [groupId], oder `null`.
  Future<CachedAt<Object?>?> read(String groupId, String key);

  /// Legt [value] als Stand zu [key] ab. Scheitert still.
  Future<void> write(String groupId, String key, Object? value);

  /// Wirft alles weg, was NICHT zu [groupId] gehört.
  Future<void> keepOnly(String groupId);
}

/// SharedPreferences-Ablage. Ein Eintrag je (Gruppe, Schlüssel).
class PrefsOfflineCache implements OfflineCache {
  static const _prefix = 'mfb.cache.';

  String _key(String groupId, String key) => '$_prefix$groupId.$key';

  @override
  Future<CachedAt<Object?>?> read(String groupId, String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(groupId, key));
      if (raw == null) return null;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse(decoded['at'] as String? ?? '');
      if (at == null) return null;
      return CachedAt(decoded['v'], at);
    } catch (error) {
      // Ein kaputter Eintrag ist wie keiner. Ohne Fehlertext ins Log: Der
      // Inhalt sind Fahrten und Namen (siehe „Was geloggt wird, kann
      // öffentlich werden").
      log.w('cache read failed: $key');
      return null;
    }
  }

  @override
  Future<void> write(String groupId, String key, Object? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(groupId, key),
        jsonEncode({'at': DateTime.now().toIso8601String(), 'v': value}),
      );
    } catch (error) {
      log.w('cache write failed: $key');
    }
  }

  @override
  Future<void> keepOnly(String groupId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mine = '$_prefix$groupId.';
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_prefix) && !key.startsWith(mine)) {
          await prefs.remove(key);
        }
      }
    } catch (error) {
      log.w('cache cleanup failed');
    }
  }
}

/// Ablage im Speicher — für Tests und den Demo-Modus.
class InMemoryOfflineCache implements OfflineCache {
  InMemoryOfflineCache({this.clock});

  final DateTime Function()? clock;
  final Map<String, CachedAt<Object?>> entries = {};

  @override
  Future<CachedAt<Object?>?> read(String groupId, String key) async =>
      entries['$groupId.$key'];

  @override
  Future<void> write(String groupId, String key, Object? value) async {
    entries['$groupId.$key'] = CachedAt(
      jsonDecode(jsonEncode(value)),
      clock?.call() ?? DateTime.now(),
    );
  }

  @override
  Future<void> keepOnly(String groupId) async {
    entries.removeWhere((key, _) => !key.startsWith('$groupId.'));
  }
}

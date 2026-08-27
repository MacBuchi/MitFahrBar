/// read_retry.dart – Ein zweiter Anlauf, wenn PostgREST das Token für zu jung
/// hält (Issue #169).
///
/// PostgREST lehnt eine Anfrage mit `PGRST303 – JWT issued at future` ab, wenn
/// das `iat` des Tokens vor **seiner** Uhr in der Zukunft liegt. Ausgestellt
/// wird das Token von GoTrue, geprüft von PostgREST; stehen die beiden Uhren
/// ein paar Sekunden auseinander, ist ein frisch erneuertes Token für diesen
/// Moment ungültig. Danach nicht mehr — die Zeit läuft ja weiter.
///
/// Belegt in `error_reports`, KW 32: 12 Vorfälle, auf Android **und** Web, auf
/// 0.53.0 wie auf 0.59.1, und immer im Rudel (Personen, Fahrten, Plan und
/// Statistik im selben Atemzug). Das ist die Signatur des Falls: Nach einer
/// Token-Erneuerung feuern alle Provider gleichzeitig los.
///
/// Drei Entscheidungen daran sind nicht beliebig:
///
/// * **Gewartet wird, nicht erneuert.** `refreshSession()` ist hier der
///   naheliegende und genau falsche Griff: Es besorgt ein noch jüngeres Token,
///   dessen `iat` noch weiter in der Zukunft der prüfenden Uhr liegt. Der
///   Fehler heilt allein dadurch, dass Zeit vergeht — also dasselbe Token
///   nach einer kurzen Pause noch einmal schicken.
/// * **Nur Lesezugriffe.** Ein wiederholtes `createTrip` legte die Fahrt
///   zweimal an, und das verschiebt rückwirkend die Punkte *aller* Beteiligten
///   — dieselbe Klasse Schaden wie ein still angelegter Doppel-Name beim
///   CSV-Import. Schreibende Aufrufe müssen den Fehler weiterreichen; die
///   Nutzerin sieht dann eine Meldung und tippt noch einmal, und das ist der
///   ehrliche Ausgang.
/// * **Genau ein zweiter Anlauf**, keine Schleife. Der Versatz ist klein und
///   fest; hilft die Pause nicht, ist es kein Uhrenversatz mehr, und eine
///   Schleife machte aus einem sichtbaren Fehler ein zähes Hängen.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Der PostgREST-Code für „Token stammt aus der Zukunft".
const String clockSkewCode = 'PGRST303';

/// Ob [error] dieser Fall ist — **an zwei Stellen geprüft, und das ist der
/// Kern**.
///
/// Die Ausnahme kommt in zwei Formen an, je nachdem, ob der Client den Rumpf
/// als Fehlerobjekt lesen konnte oder ihn roh durchgereicht hat:
///
/// ```
/// PostgrestException(message: 'JWT issued at future', code: 'PGRST303', …)
/// PostgrestException(message: '{"code":"PGRST303",…}', code: '401', …)
/// ```
///
/// Bis v0.89.1 prüfte nur `code == clockSkewCode`. Die zweite Form trägt dort
/// **401**, der Riegel fiel also nie — belegt in `error_reports` am
/// 26.08.2026 (21:06 und 21:19, beide `myGroupProvider` bzw.
/// `groupDefaultsProvider`, beide über [readTolerant] gelaufen). Beweisbar am
/// Bericht selbst: Hätte der zweite Anlauf stattgefunden, trüge die
/// weitergeworfene Ausnahme dieselbe Form wie die erste — gemeldet wurde die
/// 401-Form, der erste Versuch war es also schon.
///
/// Dass der Test grün blieb, liegt daran, dass er die Ausnahme selbst mit
/// `code: clockSkewCode` baute: geprüft wurde eine Form, die so nicht ankommt.
/// Dieselbe Klasse wie der tote Update-Knopf aus 0.37.0 — der Riegel war da,
/// er konnte nur nicht fallen.
///
/// Über die **String-Form** unterschieden, nicht über den Typ: dieselbe Linie
/// wie `isPasswordRecovery` und `looksOffline`. Wer das „aufräumt" und wieder
/// nur auf `code` prüft, stellt genau diesen Ausfall wieder her.
bool isClockSkew(PostgrestException error) =>
    error.code == clockSkewCode || error.message.contains(clockSkewCode);

/// Wie lange vor dem zweiten Anlauf gewartet wird.
///
/// Muss den beobachteten Versatz überdauern (Sekundenbereich). Veränderbar
/// **nur**, damit die Testsuite nicht wirklich schläft — im Betrieb rührt das
/// niemand an.
@visibleForTesting
Duration skewRetryDelay = const Duration(seconds: 2);

/// Führt [read] aus und wiederholt genau einmal, wenn PostgREST das Token als
/// „in der Zukunft ausgestellt" abgelehnt hat.
///
/// Jeder andere Fehler fliegt unverändert weiter — insbesondere ein echtes
/// Netzproblem, das der Oberfläche als solches erhalten bleiben muss.
Future<T> readTolerant<T>(Future<T> Function() read) async {
  try {
    return await read();
  } on PostgrestException catch (error) {
    if (!isClockSkew(error)) rethrow;
    await Future<void>.delayed(skewRetryDelay);
    return await read();
  }
}

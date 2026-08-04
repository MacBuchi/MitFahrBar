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
    if (error.code != clockSkewCode) rethrow;
    await Future<void>.delayed(skewRetryDelay);
    return await read();
  }
}

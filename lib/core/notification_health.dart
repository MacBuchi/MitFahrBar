/// notification_health.dart – Was eine Benachrichtigung unterdrückt (#180).
///
/// Reine Auswertung: rein gehen die Rohwerte, die Android meldet, raus geht
/// eine Liste von Blockaden. Kein Flutter, keine Plattform, keine Texte —
/// dieselbe Linie wie `chart_data.dart` neben `charts.dart`.
///
/// **Warum es das überhaupt gibt.** Ein gültiges FCM-Token sagt nichts
/// darüber, ob Android etwas anzeigt. Am 05.08.2026 stand in `push_log`
/// beides als verschickt, FCM hatte `ok` gemeldet — und auf dem Gerät kam
/// nichts an, weil die Berechtigung aus war (#175). Bis dahin prüfte die App
/// den Zustand genau einmal: beim Einschalten. Danach nie wieder, während
/// Android jederzeit widerrufen kann — und es nach einigen Monaten
/// Nichtnutzung von selbst tut, ohne beim Aufwachen neu zu erteilen.
///
/// **Vier Achsen, die einander nicht ersetzen.** Jede kann allein alles
/// unterdrücken, jede hat einen eigenen Systemschirm. Genau deshalb ist das
/// eine Liste und kein Wahrheitswert: „Benachrichtigungen gehen nicht" wäre
/// wahr und wertlos.
///
/// **Unbekannt ist keine Blockade.** Jedes Feld ist `null`, wo die Plattform
/// es nicht kennt (Web, ältere Androids). Ein erfundener Vorgabewert stünde
/// hier als Behauptung im Schirm.
library;

/// Was eine Meldung daran hindert, beim Menschen anzukommen.
///
/// Die Reihenfolge ist die Reihenfolge der Anzeige: erst, was alles
/// unterdrückt, zuletzt, was nur leiser macht.
enum NotificationBlock {
  /// Die Berechtigung fehlt — entweder nie erteilt, vom Nutzer entzogen oder
  /// von Android nach Monaten der Nichtnutzung zurückgenommen.
  permission,

  /// Der Akku-Zustand steht auf „Eingeschränkt". Das ist NICHT die normale
  /// Akkuoptimierung: In diesem Zustand wird **keine** FCM-Nachricht mehr
  /// zugestellt, weder high noch normal priority. Gewöhnliche Optimierung
  /// schadet nicht — `priority: high` weckt aus Doze.
  batteryRestricted,

  /// Der Kanal selbst ist ausgeschaltet. Der App-Schalter kann dabei an sein.
  channelOff,

  /// „Nicht stören" ist aktiv und dieser Kanal darf nicht durch. Heilbar:
  /// Der Nutzer erlaubt es dem Kanal in den Systemeinstellungen.
  dndBlocks,

  /// „Nicht stören" steht auf totaler Stille (oder nur Wecker). Da kommt
  /// nichts durch — auch kein Ausnahmekanal. Das kann die App nicht lösen,
  /// und sie soll es auch nicht behaupten.
  dndSilences,

  /// Der Kanal ist zwar an, aber stumm gestellt. Die Meldung erscheint, ohne
  /// jemanden zu erreichen — für eine Erinnerung kurz vor der Abfahrt ist
  /// das dasselbe wie keine.
  channelSilent,
}

/// Androids Antwort auf „darf ich?" — roh, unbewertet.
class NotificationHealth {
  const NotificationHealth({
    this.notificationsEnabled,
    this.channelImportance,
    this.channelBypassesDnd,
    this.interruptionFilter,
    this.policyAccessGranted,
    this.backgroundRestricted,
  });

  /// Nichts bekannt — Web, oder die Abfrage ist gescheitert. Meldet keine
  /// Blockade: Ein Schirm, der ohne Wissen warnt, ist Lärm.
  static const unknown = NotificationHealth();

  /// `areNotificationsEnabled()`. Der einzige Aufruf, der Berechtigung UND
  /// Systemschalter abbildet — `checkSelfPermission` meldet vor Android 13
  /// immer „verweigert", auch bei erlaubten Benachrichtigungen.
  final bool? notificationsEnabled;

  /// `NotificationChannel.importance`: 0 = aus, 1–2 = stumm, ab 3 hörbar.
  /// `null` heißt „kein solcher Kanal" (vor Android 8 gibt es keine) — und
  /// das ist etwas anderes als ein stumm gestellter.
  final int? channelImportance;

  /// Ob dieser Kanal „Nicht stören" ignorieren darf.
  final bool? channelBypassesDnd;

  /// `currentInterruptionFilter`: 1 = alles, 2 = nur Prioritäten,
  /// 3 = totale Stille, 4 = nur Wecker.
  final int? interruptionFilter;

  /// Ob die App den Sonderzugriff auf „Nicht stören" hat. Nur damit dürfte
  /// sie einen Kanal selbst als Ausnahme anlegen — und auch dann nur, solange
  /// der Nutzer den Kanal seit seiner Erstellung nicht angefasst hat.
  final bool? policyAccessGranted;

  /// `isBackgroundRestricted()`.
  final bool? backgroundRestricted;

  /// Aus wird alles, was tatsächlich im Weg steht — nach Schwere sortiert.
  ///
  /// Es werden bewusst **alle** gefundenen Blockaden gemeldet, nicht nur die
  /// erste: Wer die Berechtigung erteilt und dann feststellt, dass „Nicht
  /// stören" es trotzdem schluckt, hat zweimal umsonst nachgesehen.
  List<NotificationBlock> get blocks {
    final found = <NotificationBlock>[];
    if (notificationsEnabled == false) found.add(NotificationBlock.permission);
    if (backgroundRestricted == true) {
      found.add(NotificationBlock.batteryRestricted);
    }

    final importance = channelImportance;
    if (importance == 0) found.add(NotificationBlock.channelOff);

    switch (interruptionFilter) {
      // Nur Prioritäten: Ein Kanal mit Ausnahme kommt durch, ein anderer nicht.
      case 2:
        if (channelBypassesDnd == false) found.add(NotificationBlock.dndBlocks);
      // Totale Stille und „nur Wecker" lassen nichts durch. `setBypassDnd`
      // gilt ausdrücklich nur für den Prioritäten-Modus.
      case 3:
      case 4:
        found.add(NotificationBlock.dndSilences);
    }

    // Zuletzt, weil es nichts unterdrückt, sondern nur unhörbar macht. Ein
    // ausgeschalteter Kanal ist bereits gemeldet und braucht das nicht doppelt.
    if (importance != null && importance > 0 && importance < 3) {
      found.add(NotificationBlock.channelSilent);
    }
    return found;
  }

  /// Nichts im Weg — oder nichts bekannt. Für den Schirm dasselbe: kein Alarm.
  bool get isClear => blocks.isEmpty;

  /// Baut den Zustand aus dem, was die Plattform-Brücke geliefert hat.
  ///
  /// Alles wird einzeln und tolerant gelesen: Ein fehlender oder falsch
  /// getippter Schlüssel wird zu `null` (= unbekannt = keine Blockade) und
  /// nicht zu einer Ausnahme. Diese Abfrage darf den Schirm nie kaputt machen.
  factory NotificationHealth.fromMap(Map<Object?, Object?> map) {
    bool? flag(String key) {
      final value = map[key];
      return value is bool ? value : null;
    }

    int? count(String key) {
      final value = map[key];
      return value is num ? value.toInt() : null;
    }

    return NotificationHealth(
      notificationsEnabled: flag('notificationsEnabled'),
      channelImportance: count('channelImportance'),
      channelBypassesDnd: flag('channelBypassesDnd'),
      interruptionFilter: count('interruptionFilter'),
      policyAccessGranted: flag('policyAccessGranted'),
      backgroundRestricted: flag('backgroundRestricted'),
    );
  }
}

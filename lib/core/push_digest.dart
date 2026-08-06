/// push_digest.dart – Wann geht welche Benachrichtigung an wen, und was steht
/// drin (Issue #101).
///
/// Reine Funktionen, kein Netz, keine Uhr: `now` kommt immer von außen. Das
/// ist dasselbe Muster wie `csv_export.dart` und `chart_data.dart` — die
/// Regeln bleiben mit `flutter test` prüfbar, und `tool/notify.dart` ist nur
/// noch die I/O-Schale drumherum.
///
/// **Der Fahrer-Vorschlag wird nirgends gespeichert.** Der Versand-Job
/// bekommt fertige [PlannedDay]s aus `planWeek` (also aus der echten
/// Fairness-Logik) und legt hier nur einen *Hash* des Tageszustands ab, um
/// beim nächsten Lauf zu erkennen, ob sich etwas geändert hat. Wer statt des
/// Hashes den Plan speichert, baut die zweite Wahrheit über den Tag.
///
/// **Zwei Abnehmer, ein Wortschatz** (seit #122): Neben `tool/notify.dart`
/// liest auch die Übersicht hier — das Banner „nächste Fahrt" nimmt
/// [composeGroupBody] und [dayLabel]. Der Wortlaut gehört deshalb hierher und
/// nicht ins Widget: Was das Handy meldet und was die App zeigt, darf nicht
/// auseinanderlaufen. Aus demselben Grund tragen seit #127 **beide**
/// compose-Funktionen die Anmerkungen: Nur eine zu ergänzen ließe Banner und
/// Benachrichtigung sofort abdriften.
library;

import '../models/group_defaults.dart';
import '../models/notification_prefs.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import 'fairness.dart';

/// Warum eine Nachricht rausgeht.
enum PushKind {
  /// Der Blick auf den Folgetag, einmal je Tag und Person.
  evening,

  /// Der Plan hat sich zwischen Abend-Push und Abfahrt geändert.
  change,

  /// Kurz vor der Abfahrt zur Arbeit (#164).
  departureOut,

  /// Kurz vor der Abfahrt nach Hause.
  departureReturn,

  /// Jemand anderes hat mich ein- oder ausgetragen (#163).
  roster,

  /// Eine eingetragene Fahrt wurde geändert oder gelöscht (#163).
  trip;

  /// Ob diese Art an der Uhr hängt statt am Plan-Fenster.
  ///
  /// Die beiden Erinnerungen haben ein eigenes, viel kürzeres Fenster und
  /// ihre eigene Bedingung — sie feuern auch an einem Tag, an dem die Fahrt
  /// längst eingetragen ist (dann sogar besonders zu Recht).
  bool get isDeparture =>
      this == PushKind.departureOut || this == PushKind.departureReturn;
}

/// Eine bereits verschickte Nachricht — eine Zeile aus `push_log`.
class SentPush {
  const SentPush({
    required this.personId,
    required this.planDate,
    required this.kind,
    required this.digest,
    required this.sentAt,
  });

  final String personId;
  final DateTime planDate;
  final PushKind kind;
  final String digest;
  final DateTime sentAt;
}

/// Eine fällige Nachricht.
class DuePush {
  const DuePush({
    required this.personId,
    required this.planDate,
    required this.kind,
    required this.title,
    required this.body,
    required this.digest,
  });

  final String personId;
  final DateTime planDate;
  final PushKind kind;
  final String title;
  final String body;

  /// Der Tageszustand zum Zeitpunkt dieser Nachricht — gehört nach dem
  /// Versand in `push_log`.
  final String digest;

  @override
  String toString() => '$kind→$personId ${planDate.toIso8601String()} $digest';
}

/// Der Digest einer Person, die an dem Tag nicht (mehr) eingetragen ist.
///
/// Ein fester Wert statt eines Hashes, und das ist der Trick am Austrag:
/// Sobald jemand raus ist, ändert sich sein Digest nicht mehr, egal wie oft
/// die anderen den Tag noch umbauen. Er bekommt also **genau eine**
/// Austrags-Nachricht — und wieder eine, falls ihn jemand zurückträgt.
const String removedDigest = 'raus';

/// Der Digest eines Tages, an dem die Fahrt schon eingetragen ist (#164).
///
/// Auch ein fester Wert, und zwar aus zwei Gründen. Erstens: Ein eingetragener
/// Tag ist geplant fertig — was danach noch an Punkten oder Vorschlägen
/// passiert, geht niemanden mehr an, und ein Hash über den Tageszustand
/// meldete jede Kleinigkeit als „Änderung". Zweitens braucht die
/// Abfahrts-Erinnerung eine Korb-Zeile für genau diesen Tag: Bis v0.57.0 ließ
/// [outboxEntries] eingetragene Tage aus, und die alte Zeile blieb mit ihrem
/// Plan-Hash stehen — ein Zustand, der nie mehr zu irgendetwas passte.
///
/// **Der Übergang in diesen Wert löst nichts aus** (der Änderungs-Zweig
/// schließt ihn aus, in Dart und in `push_due()`): Eine eingetragene Fahrt
/// ist keine Meldung wert, sie ist ja schon passiert. Der Übergang *heraus*
/// dagegen schon — eine gelöschte Fahrt macht den Tag wieder zur Planung.
const String confirmedDigest = 'fix';

/// Der Tageszustand aus Sicht von [personId], als kurzer Hash.
///
/// Drin ist, was diese Person auf dem Planer sähe: wer dabei ist (und ob nur
/// eine Richtung), wer fährt, wie die Autos besetzt sind, und ob der Tag
/// schon eingetragen ist.
///
/// **Nicht drin sind die Punkte.** Die ändern sich bei jeder eingetragenen
/// Fahrt und lösten sonst Nachrichten aus, die niemanden interessieren.
///
/// **Und nicht drin sind die festen Vorgaben der Gruppe** (#139: Abfahrt,
/// Rückfahrt, Treffpunkt). Sie stehen zwar im Text, aber eine geänderte
/// Abfahrtszeit ist eine Parameter-Änderung, keine Planänderung — sie
/// verschiebt keinen Tag und keinen Fahrer. Nähme der Digest sie auf,
/// bekäme beim Speichern im Parameter-Screen die halbe Gruppe eine
/// „Änderung"-Meldung über einen Tag, an dem sich nichts getan hat.
///
/// **[dayDefaults] dagegen schon** (#183) — und darin liegt die Trennung, um
/// die es geht: Die Vorgabe der Gruppe ist ein *Parameter*, die Abweichung
/// eines Tages ist eine *Tatsache über diesen Tag*. Wer sie verschiebt, muss
/// die Leute wecken, die an dem Tag mitfahren; sonst stünde die neue Zeit im
/// Planer und das Handy klingelte zur alten. Hier gehört ausschließlich die
/// **Abweichung** hinein, nie die aufgelöste Zeit — sonst käme die
/// Gruppen-Vorgabe durch die Hintertür in den Digest zurück.
///
/// **Und nur, wenn es sie wirklich gibt.** Ein Client von vor v0.64.0 kennt
/// die Abweichung nicht und rechnet ohne sie. Flösse hier auch bei leerer
/// Abweichung etwas ein, unterschieden sich die Digests zweier Clients für
/// denselben unveränderten Tag — und jeder Wechsel wäre eine „Änderung"-
/// Meldung an alle Anwesenden. So sind alle normalen Tage versionsübergreifend
/// bitgleich, und pendeln kann höchstens ein Tag, an dem gerade jemand
/// bewusst etwas geändert hat: Dort ist die Meldung ohnehin gewollt.
///
/// [notes] darf die Anmerkungen **aller** Tage enthalten — hier wird auf
/// [day] gefiltert. Eine flache Liste statt einer Map nach Tag ist Absicht:
/// Ein Aufrufer, der falsch auf Tagesbeginn normiert, könnte Anmerkungen
/// sonst unsichtbar am Tag vorbeischieben.
String dayDigestFor(
  PlannedDay day,
  String personId, {
  List<PlanNote> notes = const [],
  GroupDefaults? dayDefaults,
}) {
  if (!day.availableIds.contains(personId)) return removedDigest;

  // Ist die Fahrt eingetragen, zählt nur noch, wer wirklich mitfuhr — das
  // steht in den Autos, nicht in der Verfügbarkeit. `planWeek` vereint für
  // einen bestätigten Tag beides (#85), wer also verfügbar war und dann doch
  // nicht mitfuhr, steht weiter in `availableIds`. Für ihn ist der Tag
  // vorbei wie für einen Ausgetragenen — und genau das sagt sein Digest.
  if (day.confirmed) {
    return _carOf(day, personId) == null ? removedDigest : confirmedDigest;
  }

  final state = StringBuffer();
  for (final id in day.availableIds) {
    state
      ..write(id)
      ..write(day.oneWayIds.contains(id) ? ':w' : ':v')
      ..write('/');
  }
  state.write('|');
  for (final car in day.cars) {
    state
      ..write(car.driverId)
      ..write('(')
      ..write(car.fullIds.join(','))
      ..write(';')
      ..write(car.oneWayIds.join(','))
      ..write(')');
  }
  state.write(day.confirmed ? '|x' : '|-');

  // Anmerkungen (#127): Eine neue oder gelöschte verändert den Tag für alle
  // und soll deshalb eine Meldung auslösen.
  //
  // **Die Sortierung ist der Kern dieser Zeile, keine Kosmetik.** Der
  // Versand-Job liest per PostgREST, das ohne `order` keine Reihenfolge
  // zusichert. Ungesortiert unterschiede sich der Hash zwischen zwei Läufen
  // ohne jede Datenänderung — Ergebnis wäre im Abstand des Cooldowns eine
  // „Änderung"-Meldung an jeden Anwesenden, dauerhaft, über eine
  // Planänderung, die es nie gab.
  //
  // Nur die IDs, nicht der Text: Es gibt kein Bearbeiten, die ID ist exakt.
  // Löschen und neu schreiben ergibt eine neue ID und damit richtigerweise
  // eine Meldung.
  final ids = [
    for (final note in notes)
      if (_dayOnly(note.date) == _dayOnly(day.date)) note.id,
  ]..sort();
  state
    ..write('|')
    ..write(ids.join(','));

  // Die Abweichung dieses Tages (#183). Nur wenn es sie gibt — siehe oben:
  // Ein leerer Anhang hier machte jeden normalen Tag versionsabhängig.
  if (dayDefaults != null && !dayDefaults.isEmpty) {
    state
      ..write('|')
      ..write(dayDefaults.outboundTime?.format() ?? '')
      ..write('~')
      ..write(dayDefaults.returnTime?.format() ?? '')
      ..write('~')
      ..write(dayDefaults.meetingPoint ?? '');
  }

  return _hash(state.toString());
}

/// Alle Nachrichten, die zu [now] fällig sind.
///
/// [week] kommt aus `planWeek`, [prefs] und [sent] aus der Datenbank. Wer
/// keine Zeile in [prefs] hat, bekommt nichts — das Einschalten im Screen
/// legt sie an, und damit gibt es genau eine Wahrheit darüber, wer etwas
/// bekommt.
///
/// **Eine Änderungs-Meldung setzt den Abend-Push voraus** (unten: der
/// `evening == null`-Zweig endet immer mit `continue`). Ohne ihn wäre sie
/// die erste Nachricht des Tages und ohne Bezug — mit abgeschaltetem
/// Abend-Blick ist `changesEnabled` deshalb wirkungslos.
/// `features/notifications/notifications_screen.dart` spiegelt genau das,
/// indem es den Änderungs-Schalter dann sperrt; wer die Regel hier ändert,
/// ändert sie dort mit.
///
/// [notes] sind die Anmerkungen (#127) **aller** Tage; sie reisen bewusst als
/// `change` mit und bekommen keine eigene [PushKind]. Eine eigene Art müsste
/// die Empfängerfrage neu beantworten und bräuchte ein Gegenstück zu
/// [removedDigest] — sonst bekäme jemand, der aus dem Tag heraus ist, weiter
/// Anmerkungs-Meldungen. **Der Preis, der dazugehört:** Wer den Abend-Blick
/// abgeschaltet hat, bekommt auch keine Anmerkungs-Meldung; der
/// Benachrichtigungs-Screen sagt das.
///
/// [defaults] sind die festen Vorgaben der Gruppe (#139). Sie stehen im Text,
/// aber **nicht** im Digest — siehe [dayDigestFor]: Eine geänderte Abfahrtszeit
/// ist eine Parameter-, keine Planänderung und weckt niemanden.
///
/// [dayDefaults] sind die Abweichungen einzelner Tage (#183). Sie schlagen
/// [defaults] feldweise und stehen — anders als jene — sehr wohl im Digest.
/// Dies ist der Dart-Spiegel von `push_due()`; weicht er ab, prüft
/// `test/push_outbox_test.dart` einen Weg, den es in Produktion nicht gibt.
List<DuePush> dueMessages({
  required List<PlannedDay> week,
  required Map<String, NotificationPrefs> prefs,
  required List<SentPush> sent,
  required Map<String, Person> persons,
  required DateTime now,
  List<PlanNote> notes = const [],
  GroupDefaults defaults = const GroupDefaults(),
  Map<DateTime, GroupDefaults> dayDefaults = const {},
  Duration changeCooldown = const Duration(minutes: 30),
}) {
  final index = <String, SentPush>{
    for (final s in sent) _logKey(s.personId, s.planDate, s.kind): s,
  };
  final due = <DuePush>[];

  for (final day in week) {
    final date = _dayOnly(day.date);
    // Was an diesem Tag wirklich gilt (#183) — die Abweichung schlägt die
    // Vorgabe, feldweise. `deviation` allein geht in den Digest, `effective`
    // in Zeiten und Text.
    final deviation = dayDefaults[date];
    final effective = effectiveDefaults(defaults, deviation);

    // ------------------------------------------ Erinnerungen zur Abfahrt
    //
    // Eigenes Fenster, eigene Bedingung, eigener Riegel: Sie hängen an der
    // Uhr der Gruppe, nicht am Plan-Fenster. Die Rückfahrt liegt sogar weit
    // hinter der persönlichen `departureTime`, die den Plan-Teil schließt —
    // in einem gemeinsamen Fenster wäre sie nie fällig geworden.
    for (final (kind, legTime) in [
      (PushKind.departureOut, effective.outboundTime),
      (PushKind.departureReturn, effective.returnTime),
    ]) {
      if (legTime == null) continue;
      for (final personId in day.availableIds) {
        final pref = prefs[personId];
        if (pref == null || !pref.remindersEnabled) continue;

        final digest = dayDigestFor(day, personId, notes: notes, dayDefaults: deviation);
        // `raus` ist der einzige Ausschluss — `fix` fährt mit: An einem
        // eingetragenen Tag fährt die Gruppe ja gerade, das ist der Moment,
        // für den die Erinnerung gebaut wurde.
        if (digest == removedDigest) continue;
        // Zeitgetriggert, also genau einmal: Ein Nachholen wäre eine
        // Erinnerung an eine Abfahrt, die schon war.
        if (index[_logKey(personId, date, kind)] != null) continue;

        final departs = legTime.on(date);
        // Je Richtung ein eigener Vorlauf (#168): Hin- und Rückweg starten
        // nicht am selben Ort. Der Spiegel dazu steht in `push_due()` als
        // vierte Spalte des `values`-Paars — driften beide auseinander,
        // weckt die Datenbank zu anderen Zeiten als dieser Code behauptet.
        final lead = kind == PushKind.departureOut
            ? pref.reminderLeadMinutes
            : pref.reminderLeadReturnMinutes;
        final wakes = departs.subtract(Duration(minutes: lead));
        if (now.isBefore(wakes) || !now.isBefore(departs)) continue;

        due.add(
          DuePush(
            personId: personId,
            planDate: date,
            kind: kind,
            title: composeTitle(
              date,
              kind,
              now,
              removed: false,
              legTime: legTime,
            ),
            body: composeBody(
              day,
              personId,
              persons,
              notes: notes,
              defaults: effective,
            ),
            digest: digest,
          ),
        );
      }
    }

    // ------------------------------------------------- Plan-Meldungen
    //
    // Kandidaten sind die Anwesenden — plus die, die schon einen Abend-Push
    // für den Tag haben. Sonst erführe niemand, dass er ausgetragen wurde.
    final candidates = <String>{
      ...day.availableIds,
      for (final s in sent)
        if (s.kind == PushKind.evening && _dayOnly(s.planDate) == date)
          s.personId,
    };

    for (final personId in candidates) {
      final pref = prefs[personId];
      if (pref == null) continue;

      // Das Fenster: vom Abend davor bis zur Abfahrt. Gesendet wird
      // „sobald fällig", nicht „um genau" — ein verspäteter Lauf holt also
      // nach. Die Abfahrt ist der harte Riegel dagegen, dass ein Ausfall
      // jemanden nachts weckt.
      final opens = pref.eveningTime.on(date.subtract(const Duration(days: 1)));
      final closes = pref.departureTime.on(date);
      if (now.isBefore(opens) || !now.isBefore(closes)) continue;

      final digest = dayDigestFor(day, personId, notes: notes, dayDefaults: deviation);
      // Ein eingetragener Tag ist geplant fertig: Weder ein Abend-Blick noch
      // eine Änderungs-Meldung hat dazu noch etwas zu sagen. Bis v0.57.0
      // sprang die Schleife dafür ganz aus dem Tag heraus — seit es
      // Erinnerungen gibt, braucht der Tag seine Korb-Zeile, und der Riegel
      // sitzt hier. Der Weg HERAUS aus `fix` (gelöschte Fahrt) meldet sich
      // dagegen: Dann ist der Tag wieder Planung.
      if (digest == confirmedDigest) continue;
      final evening = index[_logKey(personId, date, PushKind.evening)];
      final change = index[_logKey(personId, date, PushKind.change)];

      if (evening == null) {
        // Der Abend-Push geht nur an Anwesende. Wer gar nicht eingetragen
        // ist, bekommt auch kein „du bist nicht dabei" — das wäre Lärm.
        if (!day.availableIds.contains(personId)) continue;
        if (!pref.eveningEnabled) continue;
        due.add(
          DuePush(
            personId: personId,
            planDate: date,
            kind: PushKind.evening,
            title: composeTitle(date, PushKind.evening, now, removed: false),
            body: composeBody(
              day,
              personId,
              persons,
              notes: notes,
              defaults: effective,
            ),
            digest: digest,
          ),
        );
        continue;
      }

      if (!pref.changesEnabled) continue;
      final lastDigest = change?.digest ?? evening.digest;
      if (digest == lastDigest) continue;
      // Mindestabstand gegen Nachnagen, wenn jemand länger im Planer
      // herumräumt. Der 10-Minuten-Takt des Jobs entprellt zusätzlich,
      // weil er immer nur den fertigen Zustand sieht.
      if (change != null && now.difference(change.sentAt) < changeCooldown) {
        continue;
      }
      due.add(
        DuePush(
          personId: personId,
          planDate: date,
          kind: PushKind.change,
          title: composeTitle(
            date,
            PushKind.change,
            now,
            removed: digest == removedDigest,
          ),
          body: composeBody(
            day,
            personId,
            persons,
            notes: notes,
            defaults: effective,
          ),
          digest: digest,
        ),
      );
    }
  }

  return due;
}

/// Die Kopfzeile der Nachricht.
///
/// [legTime] gilt nur für die beiden Abfahrts-Erinnerungen (#164) und ist die
/// Gruppenzeit, nicht der Weckzeitpunkt: Auf dem Sperrbildschirm soll stehen,
/// wann es losgeht, nicht wann die Meldung kam. Fehlt sie, bleibt die
/// Kopfzeile ohne Uhrzeit — aufgerufen wird das nicht, denn ohne Gruppenzeit
/// entsteht gar keine Erinnerung.
String composeTitle(
  DateTime date,
  PushKind kind,
  DateTime now, {
  required bool removed,
  DayTime? legTime,
}) {
  final label = dayLabel(date, now);
  final at = legTime == null ? '' : ' ${legTime.format()} Uhr';
  return switch ((kind, removed)) {
    (PushKind.evening, _) => label,
    (PushKind.change, true) => 'Ausgetragen · $label',
    (PushKind.change, false) => 'Änderung · $label',
    (PushKind.departureOut, _) => 'Abfahrt$at',
    (PushKind.departureReturn, _) => 'Rückfahrt$at',
    // Die „Ausgetragen"-Fassung ist wörtlich die der Änderungs-Meldung, und
    // `push_due()` greift für diesen Fall auch dort zu: Ein zweites Wort für
    // dieselbe Sache wäre eine zweite Sprache.
    (PushKind.roster, true) => 'Ausgetragen · $label',
    (PushKind.roster, false) => 'Eingetragen · $label',
    (PushKind.trip, true) => 'Fahrt entfernt · $label',
    (PushKind.trip, false) => 'Fahrt geändert · $label',
  };
}

/// Der Text der Nachricht — was diese Person über den Tag wissen will.
String composeBody(
  PlannedDay day,
  String personId,
  Map<String, Person> persons, {
  List<PlanNote> notes = const [],
  GroupDefaults defaults = const GroupDefaults(),
}) {
  // Dieselbe Frage wie in [dayDigestFor], und sie muss dieselbe Antwort
  // geben: Steht im Digest „raus", darf der Text nicht von einer Fahrt
  // erzählen, an der die Person nicht teilnimmt — die Kopfzeile sagt dann
  // „Ausgetragen".
  final riding = day.confirmed
      ? _carOf(day, personId) != null
      : day.availableIds.contains(personId);
  if (!riding) {
    return 'Du bist für diesen Tag nicht mehr eingetragen.';
  }

  final parts = <String>[];
  final myCar = _carOf(day, personId);

  if (day.cars.isEmpty) {
    final allOneWay =
        day.availableIds.isNotEmpty &&
        day.oneWayIds.length == day.availableIds.length;
    parts.add(
      allOneWay
          ? 'Kein Fahrer möglich — alle nur eine Richtung'
          : 'Kein Fahrer',
    );
    parts.add('${day.availableIds.length} dabei');
  } else if (myCar == null) {
    // Sollte nicht vorkommen (planWeek teilt alle Anwesenden zu), aber ein
    // stiller Absturz im Versand-Job wäre der schlechtere Ausgang.
    parts.add(_driverPhrase(day.driverIds, persons));
    parts.add('${day.availableIds.length} dabei');
  } else if (myCar.driverId == personId) {
    parts.add('Du fährst');
    final riders = [...myCar.fullIds, ...myCar.oneWayIds];
    parts.add(
      riders.isEmpty
          ? 'niemand mitzunehmen'
          : 'dabei: ${_names(riders, persons)}',
    );
  } else {
    parts.add('${_name(myCar.driverId, persons)} fährt');
    final others = [
      ...myCar.fullIds,
      ...myCar.oneWayIds,
    ].where((id) => id != personId).toList();
    if (others.isNotEmpty) parts.add('dabei: ${_names(others, persons)}');
    if (day.oneWayIds.contains(personId)) parts.add('du nur eine Richtung');
  }

  if (day.cars.length > 1) parts.add('${day.cars.length} Autos');
  parts.addAll(_defaultPhrases(defaults));
  final note = _notePhrase(day, persons, notes);
  if (note != null) parts.add(note);
  return parts.join(' · ');
}

/// Derselbe Tag, aber aus Sicht der ganzen Gruppe — für die Übersicht (#122),
/// wo niemand „du" ist.
///
/// [composeBody] braucht eine `personId`, und die kennt nur ein Gerät mit
/// Push-Zuordnung: im Browser und auf nicht zugeordneten Geräten gibt es sie
/// nicht. Diese Fassung nennt den Fahrer beim Namen und zählt alle übrigen
/// Anwesenden als Mitfahrer — sie teilt sich [_driverPhrase] und [_names] mit
/// der persönlichen, damit beide dieselbe Sprache sprechen.
String composeGroupBody(
  PlannedDay day,
  Map<String, Person> persons, {
  List<PlanNote> notes = const [],
  GroupDefaults defaults = const GroupDefaults(),
}) {
  final parts = <String>[];

  if (day.cars.isEmpty) {
    final allOneWay =
        day.availableIds.isNotEmpty &&
        day.oneWayIds.length == day.availableIds.length;
    parts.add(
      allOneWay
          ? 'Kein Fahrer möglich — alle nur eine Richtung'
          : 'Kein Fahrer',
    );
    parts.add('${day.availableIds.length} dabei');
  } else {
    parts.add(_driverPhrase(day.driverIds, persons));
    // Alle Anwesenden außer den Fahrern — bei mehreren Autos ist „dabei" die
    // Gruppe des Tages, nicht die eines Autos.
    final riders = day.availableIds
        .where((id) => !day.driverIds.contains(id))
        .toList();
    parts.add(
      riders.isEmpty
          ? 'niemand mitzunehmen'
          : 'dabei: ${_names(riders, persons)}',
    );
  }

  if (day.cars.length > 1) parts.add('${day.cars.length} Autos');
  parts.addAll(_defaultPhrases(defaults));
  final note = _notePhrase(day, persons, notes);
  if (note != null) parts.add(note);
  return parts.join(' · ');
}

/// Die festen Vorgaben der Gruppe (#139) als Satzteile — leer, wenn nichts
/// gepflegt ist.
///
/// Sie stehen **vor** der Anmerkung und nach allem anderen: Eine Anmerkung ist
/// die Abweichung von genau diesen Vorgaben („komme erst um 9"), und sie
/// zuletzt zu lesen ist die Reihenfolge, in der man es sich sagen würde.
///
/// Ein nicht gepflegter Wert erzeugt **kein** Wort — kein „Abfahrt —", kein
/// „Treffpunkt unbekannt". Wer die Felder nie ausfüllt, merkt von der ganzen
/// Sache nichts.
List<String> _defaultPhrases(GroupDefaults defaults) => [
  if (defaults.outboundTime case final time?) 'Abfahrt ${time.format()}',
  if (defaults.returnTime case final time?) 'Rückfahrt ${time.format()}',
  if (defaults.meetingPoint case final point?) 'Treffpunkt $point',
];

/// Die jüngste Anmerkung des Tages als `Anna: komme erst um 9`, ältere nur
/// gezählt — oder `null`, wenn es keine gibt.
///
/// **Der Text steht bewusst drin, nicht nur eine Zahl.** Zugestellt wird über
/// den 10-Minuten-Job (real deutlich träger, Issue #115); eine späte Meldung,
/// die nur „1 Anmerkung" sagt, wäre zweimal wertlos. Gekürzt wird aus
/// demselben Grund wie bei [_names]: Eine Benachrichtigung wird ohnehin
/// abgeschnitten, lieber lesbar kurz als vollständig unlesbar.
///
/// Was hier entsteht, darf **niemals** in einem `log`-Aufruf landen —
/// dieselbe Regel wie beim Einladungstext: `logRing` hängt an der
/// Rückmeldung, und die wird ein öffentliches Issue.
String? _notePhrase(
  PlannedDay day,
  Map<String, Person> persons,
  List<PlanNote> notes,
) {
  final mine = [
    for (final note in notes)
      if (_dayOnly(note.date) == _dayOnly(day.date)) note,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (mine.isEmpty) return null;

  final latest = mine.last;
  final body = latest.body.trim();
  final short = body.length <= _noteMaxChars
      ? body
      : '${body.substring(0, _noteMaxChars).trimRight()}…';
  final phrase = '${_name(latest.personId, persons)}: $short';
  return mine.length == 1 ? phrase : '$phrase (+${mine.length - 1} weitere)';
}

/// Ab hier wird die Anmerkung in der Benachrichtigung gekürzt. Android und
/// die Browser schneiden je nach Gerät früher oder später ab — dieser Wert
/// sorgt dafür, dass wenigstens das Kürzungszeichen sichtbar wird und nicht
/// mitten im Wort abgeschnitten aussieht.
const int _noteMaxChars = 60;

/// `Morgen (Di, 28.07.)` — bezogen auf [now], damit ein nachgeholter Lauf am
/// Morgen nicht „morgen" schreibt, wenn der Tag längst da ist.
String dayLabel(DateTime date, DateTime now) {
  final target = _dayOnly(date);
  final today = _dayOnly(now);
  final stamp =
      '${_weekdays[target.weekday - 1]}, '
      '${target.day.toString().padLeft(2, '0')}.'
      '${target.month.toString().padLeft(2, '0')}.';
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'Heute ($stamp)';
  if (diff == 1) return 'Morgen ($stamp)';
  return stamp;
}

const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

DateTime _dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _logKey(String personId, DateTime date, PushKind kind) {
  final day = _dayOnly(date);
  return '$personId|${day.year}-${day.month}-${day.day}|${kind.name}';
}

PlannedCar? _carOf(PlannedDay day, String personId) {
  for (final car in day.cars) {
    if (car.driverId == personId ||
        car.fullIds.contains(personId) ||
        car.oneWayIds.contains(personId)) {
      return car;
    }
  }
  return null;
}

String _name(String id, Map<String, Person> persons) =>
    persons[id]?.name ?? 'jemand';

/// Bis zu vier Namen, alphabetisch; der Rest als `+n`. Eine Benachrichtigung
/// wird ohnehin abgeschnitten — lieber lesbar kurz als vollständig unlesbar.
String _names(Iterable<String> ids, Map<String, Person> persons) {
  final names = ids.map((id) => _name(id, persons)).toList()..sort();
  if (names.length <= 4) return names.join(', ');
  return '${names.take(4).join(', ')} +${names.length - 4}';
}

String _driverPhrase(List<String> driverIds, Map<String, Person> persons) {
  if (driverIds.isEmpty) return 'Kein Fahrer';
  final names = driverIds.map((id) => _name(id, persons)).toList()..sort();
  if (names.length == 1) return '${names.first} fährt';
  return '${names.join(' und ')} fahren';
}

/// Derselbe Hash wie im Tages-Digest — für Zustände, die kein Plantag sind
/// (Fahrt-Meldungen, #163). Öffentlich, damit es bei EINER Rechenart bleibt:
/// Zwei Hash-Funktionen im selben Korb sähen gleich aus und verglichen sich
/// nie.
String pushHash(String input) => _hash(input);

/// djb2 mit 32-Bit-Maske, als Hex.
///
/// Bewusst kein 64-Bit-FNV und keine Krypto-Abhängigkeit: `int` ist im
/// Web-Build eine JS-Zahl mit 53 Bit Genauigkeit. Bei 64 Bit lieferten VM
/// und Web still **verschiedene** Digests, und das fiele erst auf, wenn
/// jemand den Digest später auch im Client berechnet. `hash * 33` bleibt
/// unter 2^37 und ist damit auf beiden Zielen exakt.
///
/// 32 Bit reichen: Verglichen werden immer nur zwei konkrete Zustände
/// desselben Tages, nicht eine große Menge gegeneinander.
String _hash(String input) {
  var hash = 5381;
  for (final unit in input.codeUnits) {
    hash = ((hash * 33) ^ unit) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

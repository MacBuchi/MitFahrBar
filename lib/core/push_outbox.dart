/// push_outbox.dart – Was in den Ausgangskorb geschrieben wird (Issue #132).
///
/// Reine Aufbereitung, kein Netz und kein Flutter — testbar getrennt vom
/// Schreiben, dieselbe Linie wie `chart_data.dart` neben `charts.dart`.
///
/// **Warum es das gibt.** Der Versand lief über einen GitHub-Actions-Cron,
/// den GitHub unter Last verwirft (#115: real gut stündlich statt alle zehn
/// Minuten). Eine Änderung um 7:05 kam damit womöglich nach der Abfahrt an,
/// also nie. Ereignisgetrieben zu senden scheiterte bisher daran, dass der
/// Entscheider die Fairness-Regel braucht — und die lebt in Dart.
///
/// Die Auflösung ist eine Arbeitsteilung: **Den Text rechnet der Client**
/// (hier), mit demselben `planWeek`, `composeBody` und `composeTitle`, die
/// auch das Banner und der Job benutzen. Die Datenbank entscheidet nur noch,
/// *ob* und *wann* etwas rausgeht. Damit verlässt die Fairness-Regel Dart
/// nie, und trotzdem hängt der Versand nicht mehr an einem fremden
/// Zeitplan.
///
/// **Was hier NICHT entschieden wird**: ob eine Nachricht fällig ist. Das
/// braucht `push_log` und die eingestellten Zeiten — beides sieht der
/// Versender, nicht der Client. Deshalb stehen hier auch **beide**
/// Kopfzeilen: Welche Art die Meldung ist, weiß erst er.
library;

import '../models/group_defaults.dart';
import '../models/notification_prefs.dart';
import '../models/person.dart';
import '../models/plan_note.dart';
import 'fairness.dart';
import 'push_digest.dart';

/// Eine Zeile des Ausgangskorbs: was dieser Person zu diesem Tag zu sagen
/// wäre.
class OutboxEntry {
  const OutboxEntry({
    required this.personId,
    required this.date,
    required this.digest,
    required this.body,
    required this.titleEvening,
    required this.titleChange,
    this.titleOut,
    this.titleReturn,
    this.titleRoster,
    this.kind = 'plan',
    this.suppressRoster = false,
    this.outboundTime,
    this.returnTime,
  });

  final String personId;
  final DateTime date;

  /// `plan` oder `trip` (#163) — seit v0.59.0 Teil des Schlüssels. Zum selben
  /// Tag können eine Plan-Zeile und eine Fahrt-Meldung gleichzeitig offen
  /// sein; sie sagen Verschiedenes.
  final String kind;

  /// Derselbe Hash wie in `push_log` — daran erkennt der Versand eine
  /// Änderung.
  final String digest;

  final String body;
  final String titleEvening;
  final String titleChange;

  /// Die Kopfzeilen der Abfahrts-Erinnerungen (#164) — `null`, solange die
  /// Gruppe keine Zeit gepflegt hat. Ohne Zeit gibt es keine Erinnerung, also
  /// auch keine Kopfzeile; `push_due()` verlangt beides.
  final String? titleOut;
  final String? titleReturn;

  /// Die Kopfzeile der Eintrag-Meldung (#163). Für den Austrag greift
  /// `push_due()` auf [titleChange] zurück — dieselbe „Ausgetragen"-Fassung
  /// wie bei der Änderungs-Meldung.
  final String? titleRoster;

  /// Unterdrückt die Eintrag-Meldung für genau diese Zeile: Wer selbst
  /// tippt, braucht keine Meldung darüber.
  ///
  /// **Best effort, keine Zugriffskontrolle.** Sie hängt an der
  /// Geräte-Zuordnung „Ich bin" (#121), und die ist ausdrücklich kein Login:
  /// Ein Gerät ohne Zuordnung unterdrückt gar nichts, und der stündliche Job
  /// schreibt sie als `false`. Lieber eine Meldung zu viel als eine, die
  /// jemand nie bekommt.
  final bool suppressRoster;

  /// Die **wirksamen** Abfahrtszeiten dieses Tages (#183) — die Abweichung
  /// des Tages, sonst die Vorgabe der Gruppe. `null`, solange weder das eine
  /// noch das andere gepflegt ist.
  ///
  /// Sie stehen hier und nicht in `push_due()`, weil die wirksame Zeit ab
  /// Stufe B davon abhängt, in **welchem Auto** die Person sitzt — und diese
  /// Zuordnung kommt aus `planWeek`. Sie im Versand nachzurechnen hieße, die
  /// Fairness-Regel ein zweites Mal zu schreiben, diesmal in SQL. Genau
  /// dieselbe Arbeitsteilung wie beim Text und den Kopfzeilen: Der Client
  /// rechnet, die Datenbank entscheidet nur noch *ob* und *wann*.
  final DayTime? outboundTime;
  final DayTime? returnTime;

  Map<String, Object?> toJson() => {
    'person_id': personId,
    'plan_date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'kind': kind,
    'digest': digest,
    'body': body,
    'title_evening': titleEvening,
    'title_change': titleChange,
    'title_out': titleOut,
    'title_return': titleReturn,
    'title_roster': titleRoster,
    'suppress_roster': suppressRoster,
    'outbound_time': outboundTime?.format(),
    'return_time': returnTime?.format(),
  };
}

/// Der erste Tag, der im Ausgangskorb stehen bleiben darf (#177).
///
/// **Der Planer darf vorausblicken, der Korb darf nicht den Tag wegwerfen,
/// über den er noch meldet.** Ab Freitagmittag liefert [planningWeek] die
/// kommende Woche — genau dafür ist es da, der Planer zeigt dann schon den
/// Montag. Als `keep_from` weitergereicht löschte derselbe Wert aber die
/// Zeilen **dieses** Freitags: `publish_push_outbox` räumt alles vor
/// `keep_from` weg, und Freitag liegt vor dem nächsten Montag. Die
/// Rückfahrt-Erinnerung um 16:20 hätte danach keine Zeile mehr, aus der sie
/// feuern könnte, und die Sofort-Meldungen dieses Tages (#163) stürben mit
/// ihr — sie reisen als `plan`-Zeilen mit `roster_due_at`.
///
/// Bis zur Abfahrts-Erinnerung (v0.58.0) fiel das nicht auf: Abend-Blick und
/// Änderungs-Meldung sind mit dem Freitag an dessen persönlicher
/// `departure_time` (Vorgabe 7:30) durch, das Wegräumen um zwölf kostete
/// nichts. Eine **Rückfahrt** um 16:20 ist das Erste, was die Zeile über den
/// eigenen Mittag hinaus braucht.
///
/// Deshalb der frühere der beiden Tage: vor Freitagmittag unverändert der
/// Wochenmontag, danach heute. Am Samstag ist der Freitag dann wirklich vorbei
/// und darf weg.
///
/// Gehört bewusst hierher und nicht an die drei Aufrufstellen: `lib/data` und
/// `tool/notify.dart` schreiben denselben Korb, und drei von Hand gerechnete
/// Vergleiche wären drei Gelegenheiten, den Fall verschieden zu beantworten.
DateTime outboxKeepFrom(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final planned = planningWeek(now).first;
  return planned.isBefore(today) ? planned : today;
}

/// Der ganze Ausgangskorb für [week].
///
/// Geschrieben wird für **alle** aktiven Personen, nicht nur für die
/// Anwesenden: Wer aus einem Tag herausfällt, soll genau eine Meldung darüber
/// bekommen ([removedDigest]), und ob er vorher schon eine Abend-Meldung
/// hatte, weiß nur der Versender. Zeilen zu Personen, für die nie etwas
/// fällig wird, kosten nichts — der Versand schickt einem Abwesenden keinen
/// Abend-Blick.
///
/// **Eingetragene Tage sind seit v0.58.0 dabei** (#164). Bis dahin ließ diese
/// Schleife sie aus — mit dem Ergebnis, dass die Zeile des Tages mit ihrem
/// alten Plan-Hash stehen blieb und zu nichts mehr passte. Für die
/// Abfahrts-Erinnerung braucht der Tag aber eine Zeile: Sie meldet sich
/// gerade dann, wenn die Fahrt feststeht. Dass daraus keine Plan-Meldung
/// wird, regelt [confirmedDigest] und nicht diese Schleife.
/// [suppressPersonId] ist, wer an diesem Gerät sitzt (#121) — seine Zeile
/// bekommt keine Eintrag-Meldung (#163). Der stündliche Job übergibt hier
/// nichts und hebt die Unterdrückung damit wieder auf: Er weiß nicht, wer
/// getippt hat, und eine Meldung zu viel ist besser als eine verlorene.
/// [dayDefaults] sind die Abweichungen einzelner Tage (#183), auf Tagesbeginn
/// normiert. Sie schlagen [defaults] feldweise; was ein Tag nicht setzt,
/// kommt weiter aus der Vorgabe der Gruppe.
///
/// [carDefaults] sind die Abweichungen einzelner **Autos** (Tag → Fahrer),
/// die dritte und stärkste Ebene: `Auto → Tag → Gruppe`. Ein Eintrag zu
/// einem Fahrer, der an dem Tag nicht (mehr) fährt, fällt beim Auflösen
/// heraus — nachgeräumt wird er nie, denn dafür müsste jemand den Plan
/// nachrechnen.
List<OutboxEntry> outboxEntries({
  required List<PlannedDay> week,
  required Map<String, Person> persons,
  required DateTime now,
  List<PlanNote> notes = const [],
  GroupDefaults defaults = const GroupDefaults(),
  Map<DateTime, GroupDefaults> dayDefaults = const {},
  Map<DateTime, Map<String, GroupDefaults>> carDefaults = const {},
  String? suppressPersonId,
}) {
  final entries = <OutboxEntry>[];
  for (final day in week) {
    // Die Abweichung dieses Tages und die daraus aufgelöste Wahrheit. Der
    // Digest bekommt NUR die Abweichung — nähme er die aufgelöste Zeit,
    // stünde die Gruppen-Vorgabe wieder drin, und jede Änderung im
    // Parameter-Screen weckte die halbe Gruppe.
    final dayKey = DateTime(day.date.year, day.date.month, day.date.day);
    final dayDeviation = dayDefaults[dayKey];
    final carsOfDay = carDefaults[dayKey] ?? const <String, GroupDefaults>{};
    for (final personId in persons.keys) {
      // Ab Stufe B hängt die wirksame Zeit daran, in welchem Auto jemand
      // sitzt: `Auto → Tag → Gruppe`, feldweise. Zwei Personen desselben
      // Tages tragen dadurch verschiedene Zeiten in ihren Zeilen — genau
      // deshalb steht die Zeit je Zeile im Korb und nicht in `push_due()`.
      final car = carOf(day, personId);
      final carDeviation = car == null ? null : carsOfDay[car.driverId];
      // **Was für DIESE Person abweicht**: Tag und Auto verschmolzen, und
      // nichts sonst. Leer heißt „nichts abweichend", egal aus welcher der
      // beiden Ebenen — deshalb genügt dem Digest ein Wert. Und weil hier
      // keine Gruppen-Vorgabe einfließt, kommt sie auch nicht über die
      // Hintertür in den Digest zurück.
      //
      // Der Nebeneffekt ist der gewollte: Verschiebt Auto 2 seine Abfahrt,
      // ändert sich der Digest **nur** bei denen, die darin sitzen. Eine
      // Meldung an den ganzen Tag wäre falsch — die anderen fahren
      // unverändert.
      final deviation = effectiveDefaults(
        dayDeviation ?? const GroupDefaults(),
        carDeviation,
      );
      final effective = effectiveDefaults(defaults, deviation);
      final digest = dayDigestFor(
        day,
        personId,
        notes: notes,
        dayDefaults: deviation,
      );
      entries.add(
        OutboxEntry(
          personId: personId,
          date: day.date,
          digest: digest,
          outboundTime: effective.outboundTime,
          returnTime: effective.returnTime,
          body: composeBody(
            day,
            personId,
            persons,
            notes: notes,
            defaults: effective,
          ),
          // Beide Fassungen, weil die Art erst beim Versand feststeht. Der
          // Abend-Blick geht nie an Ausgetragene, deshalb dort `removed:
          // false`; die Änderungs-Meldung ist genau dann die
          // „Ausgetragen"-Fassung, wenn der Digest das sagt.
          titleEvening: composeTitle(
            day.date,
            PushKind.evening,
            now,
            removed: false,
          ),
          titleChange: composeTitle(
            day.date,
            PushKind.change,
            now,
            removed: digest == removedDigest,
          ),
          // Die Uhrzeit steht in der Kopfzeile, nicht im Text: Auf dem
          // Sperrbildschirm soll „Abfahrt 07:30" stehen, nicht „Heute".
          titleOut: _legTitle(
            day.date,
            PushKind.departureOut,
            now,
            effective.outboundTime,
          ),
          titleReturn: _legTitle(
            day.date,
            PushKind.departureReturn,
            now,
            effective.returnTime,
          ),
          titleRoster: composeTitle(
            day.date,
            PushKind.roster,
            now,
            removed: false,
          ),
          suppressRoster: personId == suppressPersonId,
        ),
      );
    }
  }
  return entries;
}

/// Kopfzeile einer Abfahrts-Erinnerung — oder `null`, wenn die Gruppe für
/// diese Richtung keine Zeit gepflegt hat.
///
/// Der `null`-Fall ist kein Sonderweg, sondern der Normalfall einer Gruppe,
/// die #139 nie benutzt: Ohne Zeit gibt es keine Erinnerung, und eine
/// Kopfzeile ohne Uhrzeit („Abfahrt") wäre eine Meldung, die nichts sagt.
String? _legTitle(
  DateTime date,
  PushKind kind,
  DateTime now,
  DayTime? legTime,
) => legTime == null
    ? null
    : composeTitle(date, kind, now, removed: false, legTime: legTime);

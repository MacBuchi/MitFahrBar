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
  });

  final String personId;
  final DateTime date;

  /// Derselbe Hash wie in `push_log` — daran erkennt der Versand eine
  /// Änderung.
  final String digest;

  final String body;
  final String titleEvening;
  final String titleChange;

  Map<String, Object?> toJson() => {
    'person_id': personId,
    'plan_date':
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'digest': digest,
    'body': body,
    'title_evening': titleEvening,
    'title_change': titleChange,
  };
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
/// Eingetragene Tage bleiben draußen: Dort gibt es nichts mehr zu planen und
/// nichts mehr zu melden — dieselbe Regel wie in [dueMessages].
List<OutboxEntry> outboxEntries({
  required List<PlannedDay> week,
  required Map<String, Person> persons,
  required DateTime now,
  List<PlanNote> notes = const [],
  GroupDefaults defaults = const GroupDefaults(),
}) {
  final entries = <OutboxEntry>[];
  for (final day in week) {
    if (day.confirmed) continue;
    for (final personId in persons.keys) {
      final digest = dayDigestFor(day, personId, notes: notes);
      entries.add(
        OutboxEntry(
          personId: personId,
          date: day.date,
          digest: digest,
          body: composeBody(
            day,
            personId,
            persons,
            notes: notes,
            defaults: defaults,
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
        ),
      );
    }
  }
  return entries;
}

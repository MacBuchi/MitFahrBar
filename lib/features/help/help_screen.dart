/// help_screen.dart – „So funktioniert MitFahrBar": die Bedienungsanleitung.
///
/// Bewusst als Screen in der App statt als externe Seite: Er erbt Theme,
/// Schriften, Hell/Dunkel und Textskalierung, zeigt die **echten** Symbole
/// und Gesichter — und kann deshalb nie stilistisch von der App wegdriften.
///
/// Wer die Bedienung ändert, pflegt diesen Text mit (dieselbe Paar-Regel
/// wie Issue-Templates ↔ Feedback-Dialog).
library;

import 'package:flutter/material.dart';

import '../../core/mood.dart';
import '../../core/tokens.dart';
import '../../core/widgets/mood_face.dart';
import '../../core/widgets/mitfahrbar_mark.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('So funktioniert MitFahrBar')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.m),
        children: [
          // Kopf: Marke + der eine Satz, wozu es die App gibt.
          Row(
            children: [
              const MitFahrBarMark(size: 56),
              const SizedBox(width: AppSpacing.m),
              Expanded(
                child: Text(
                  'Euer Fahrtenbuch mit eingebautem Fairness-Rechner: '
                  'MitFahrBar zählt mit und sagt, wer als Nächstes fährt.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.l),

          // Die eine Regel — hervorgehoben, alles andere hängt daran.
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Die eine Regel',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s),
                  Text(
                    'Wer jemanden mitnimmt, bekommt einen Punkt pro Kopf. '
                    'Wer mitfährt, gibt einen ab — bei nur einer Richtung '
                    'einen halben. Wer am wenigsten Punkte hat, ist dran.\n\n'
                    '„Schuldet 2" heißt also nicht Schulden bei der Bank: '
                    'Die anderen haben dich öfter mitgenommen als du sie. '
                    'Gezählt wird nur, was wirklich gefahren und '
                    'eingetragen ist.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.m),

          const _Section(
            icon: Icons.home_outlined,
            title: 'Übersicht',
            children: [
              _Line(
                leading: Icon(Icons.directions_car, color: AppColors.driver),
                text:
                    'Oben steht, wer dran ist — das Auto markiert, wer als '
                    'Nächstes fährt.',
              ),
              _Line(
                leading: MoodFace(mood: Mood.ecstatic, size: 22),
                text:
                    'Das Gesicht zeigt, wie oft jemand fahren musste: Wer '
                    'selten dran war, strahlt; wer ständig fährt, schaut '
                    'grimmig.',
              ),
              _Line(
                text:
                    '„Volle Kischd" trägt, wer im Schnitt die meisten '
                    'mitnimmt, „Faschd alloi", wer meist allein fährt.',
              ),
              _Line(
                text:
                    'Darunter: was ihr gemeinsam erreicht habt, Fahrten pro '
                    'Monat und wie jede und jeder unterwegs war.',
              ),
            ],
          ),

          const _Section(
            icon: Icons.add_circle_outline,
            title: 'Fahrt eintragen',
            children: [
              _Line(
                text:
                    'Der Knopf unten rechts auf der Übersicht. Datum: heute, '
                    'gestern oder über den Kalender — nur nichts in der '
                    'Zukunft, dafür ist die Woche da. Tage mit Fahrt tragen '
                    'im Kalender einen Punkt, so seht ihr beim Nachtragen '
                    'sofort, was noch fehlt.',
              ),
              _Line(
                leading: Icon(Icons.touch_app_outlined),
                text:
                    'Einmal auf eine Person tippen: dabei. Noch einmal: nur '
                    'eine Richtung. Ein drittes Mal: wieder raus.',
              ),
              _Line(
                leading: Icon(Icons.event_available_outlined),
                text:
                    'Steht der Tag schon im Wochenplan, sind die Leute von '
                    'dort vorausgewählt — Antippen ändert es wie gewohnt.',
              ),
              _Line(
                leading: Icon(Icons.directions_car, color: AppColors.driver),
                text:
                    'Den Fahrer setzt MitFahrBar automatisch — wer laut '
                    'Punkten dran ist, rutscht nach oben. Passt es nicht, '
                    'zieht ihr eine andere Kachel aufs Fahrer-Feld.',
              ),
              _Line(
                leading: Icon(
                  Icons.airline_seat_recline_normal_outlined,
                  color: AppColors.oneWay,
                ),
                text:
                    'Seid ihr mehr Leute als das Auto Sitze hat, sagt die '
                    'App das — eintragen könnt ihr trotzdem, manchmal '
                    'fahren eben zwei Autos.',
              ),
            ],
          ),

          const _Section(
            icon: Icons.calendar_month_outlined,
            title: 'Woche',
            children: [
              _Line(
                text:
                    'Tippt an, wer wann kann — gleiche Tipp-Folge wie beim '
                    'Eintragen, zweimal heißt nur eine Richtung. Jeder darf '
                    'für jeden eintragen. Oben links steht zur Orientierung '
                    'die Kalenderwoche mit ihrem Zeitraum.',
              ),
              _Line(
                text:
                    'MitFahrBar schlägt für jeden Tag vor, wer fährt, und '
                    'denkt dabei die ganze Woche mit — deshalb wechseln '
                    'sich die Namen ab. Wer nur eine Richtung kann, wird '
                    'nicht vorgeschlagen. Steht es bei den Punkten fast '
                    'gleich, bekommt, wer selten fährt, eher die kleinen '
                    'Tage — so gleicht sich auch aus, wie oft jede und '
                    'jeder fährt.',
              ),
              _Line(
                leading: Icon(Icons.directions_car, color: AppColors.driver),
                text:
                    'Reicht kein einzelnes Auto für alle, teilt MitFahrBar '
                    'den Tag auf mehrere Autos — so wenige wie möglich, '
                    'ein großes schlägt zwei kleine. Die Zeile sagt dann '
                    'zum Beispiel „Anna + Ben fahren · 2 Autos".',
              ),
              _Line(
                leading: Icon(Icons.swap_horiz),
                text:
                    'Über das Tausch-Symbol wählt ihr selbst, wer fährt — '
                    'auch mehrere. Die Zeile sagt dann „von Hand gesetzt", '
                    'und der Dialog rechnet mit, ob die Plätze reichen.',
              ),
              _Line(
                leading: Icon(Icons.check_circle, color: AppColors.driver),
                text:
                    '„Eintragen" geht frühestens am Fahrtag. Fahren mehrere '
                    'Autos, öffnet sich der Editor für jedes nacheinander, '
                    'fertig vorbelegt — gebucht wird erst mit jedem '
                    'Speichern. Wer zwischendrin abbricht, trägt den Rest '
                    'einfach von Hand nach. Danach ist der Tag blass und '
                    'gesperrt und das Raster zeigt, wer laut Fahrt dabei '
                    'war — auch wenn vorher niemand angetippt hatte; über '
                    '„Bearbeiten" kommt ihr zur Fahrt.',
              ),
              _Line(
                leading: MoodFace(mood: Mood.celebrating, size: 22),
                text:
                    'Hajo! Das Konfetti bekommt, wer das vollste Auto der '
                    'Woche fährt — gezählt wie die Punkte, eine 1-way-'
                    'Mitfahrt also halb. Bei Gleichstand alle.',
              ),
              _Line(
                leading: Icon(Icons.tune),
                text:
                    '„Was diese Woche ändert" rechnet die geplante Woche '
                    'vor: je Person der Punktediff oder — umgeschaltet — '
                    'die Fahrraten-Änderung in Promille.',
              ),
            ],
          ),

          const _Section(
            icon: Icons.history_outlined,
            title: 'Historie & Statistik',
            children: [
              _Line(
                text:
                    'Die Historie listet alle Fahrten. Antippen zum Ändern '
                    '— die App fragt vorher nach, weil sich dabei die '
                    'Punkte aller Beteiligten rückwirkend verschieben.',
              ),
              _Line(
                text:
                    'Fahren an einem Tag mehrere Autos, hat jede Fahrt ihre '
                    'eigene Zeile — ab der zweiten mit der Marke „2. Auto".',
              ),
              _Line(
                text:
                    'Wer ganz allein fährt, steht blass in der Liste: So '
                    'eine Fahrt zählt in keiner Kennzahl — weder Punkte '
                    'noch Fahranteil.',
              ),
              _Line(
                text:
                    'Die Statistik zeigt je Person Punkte, Fahrten, '
                    'Fahranteil, Ø Mitgenommene, Kilometer und was sie an '
                    'Kraftstoff gespart hat.',
              ),
            ],
          ),

          const _Section(
            icon: Icons.account_circle_outlined,
            title: 'Das Menü oben rechts',
            children: [
              _Line(
                leading: Icon(Icons.group_outlined),
                text:
                    'Personen verwalten: Name, Fahrzeug, Verbrauch und '
                    'Sitzplätze (inklusive Fahrer — die Zahl aus dem '
                    'Fahrzeugschein). Gelöscht wird niemand, nur auf '
                    'inaktiv gestellt, damit alte Fahrten zählen bleiben.',
              ),
              _Line(
                leading: Icon(Icons.tune),
                text:
                    'Parameter: euer Arbeitsweg in Kilometern und die Preise '
                    'für Strom, Diesel und Benzin. Daraus entstehen die '
                    'Kilometer und die gesparten Kosten in der Statistik — '
                    'an den Punkten ändert sich dadurch nichts.',
              ),
              _Line(
                leading: Icon(Icons.person_add_alt),
                text:
                    'Jemanden einladen baut eine fertige Nachricht mit Link '
                    'und Zugang. Das Passwort könnt ihr mitschicken — '
                    'bedenkt: Im Chat bleibt es für immer stehen. Sicherer '
                    'ist, es persönlich weiterzugeben.',
              ),
              _Line(
                leading: Icon(Icons.download_outlined),
                text:
                    'Fahrten exportieren erzeugt eine Tabelle (CSV) — eure '
                    'eigene Sicherung, legt sie ab und zu irgendwo ab.',
              ),
              _Line(
                leading: Icon(Icons.upload_outlined),
                text:
                    'Fahrten importieren liest so eine Tabelle wieder ein. '
                    'Vor dem Übernehmen zeigt die App, was passieren '
                    'würde, und fragt bei unbekannten Namen nach.',
              ),
              _Line(
                leading: Icon(Icons.lightbulb_outline),
                text:
                    'Wunsch oder Fehler melden geht direkt an die '
                    'Entwicklung — genau so sind die meisten Funktionen '
                    'hier entstanden.',
              ),
            ],
          ),

          const _Section(
            icon: Icons.info_outline,
            title: 'Gut zu wissen',
            children: [
              _Line(
                text:
                    'Ihr teilt euch einen Zugang. Wer eingeladen ist, sieht '
                    'und ändert alles — wie an einer gemeinsamen Pinnwand.',
              ),
              _Line(
                leading: Icon(Icons.admin_panel_settings_outlined),
                text:
                    'Eine Person je Gruppe kann sich auf dem Login-Bildschirm '
                    'eine Verwalter-Konsole einrichten (eigenes E-Mail-Konto): '
                    'Dort wird das Gruppenpasswort neu gesetzt, wenn es '
                    'verloren geht — und nur dort lässt sich die Gruppe '
                    'löschen. Eure E-Mail sieht dabei niemand aus der Gruppe. '
                    'Soll jemand anderes übernehmen, löst die Verwalterin '
                    'die Verknüpfung in der Konsole; auch die E-Mail-Adresse '
                    'lässt sich dort ändern. Nur wer Postfach UND Passwort '
                    'zugleich verliert, kommt nicht mehr an das '
                    'Verwalter-Konto — darum beides gut aufheben.',
              ),
              _Line(
                text:
                    'Geplantes zählt nicht. Punkte entstehen erst, wenn '
                    'eine Fahrt eingetragen ist — Absagen kostet also '
                    'nichts.',
              ),
              _Line(
                leading: Icon(Icons.system_update),
                text:
                    'Meldet die App eine neue Version, lohnt das Update. '
                    'Steht dort „Update erforderlich", geht es erst danach '
                    'weiter — die alte Version würde falsche Zahlen zeigen.',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

/// Abschnittskarte mit Titelzeile — bewusst dieselbe ruhige Card-Optik wie
/// Dashboard und Statistik.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.s),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.s),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Eine Erklärzeile, optional mit dem echten Symbol davor — dem aus der App,
/// nicht einem Nachbau.
class _Line extends StatelessWidget {
  const _Line({this.leading, required this.text});

  final Widget? leading;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: leading == null
                ? const SizedBox.shrink()
                : IconTheme.merge(
                    data: const IconThemeData(size: 20),
                    child: leading!,
                  ),
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

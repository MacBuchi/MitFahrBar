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
                leading: Icon(Icons.badge_outlined),
                text:
                    'Beim ersten Start fragt die App, wer du bist. Das ist '
                    'keine Anmeldung — ihr teilt euch einen Zugang. Es sagt '
                    'nur diesem Gerät, wen es meint. Ändern kannst du das '
                    'jederzeit im Menü oben rechts unter „Ich bin".',
              ),
              _Line(
                text:
                    'Ganz oben steht die nächste Fahrt: welcher Tag, wer '
                    'fährt und wer dabei ist. Fahrt ihr mit mehreren Autos, '
                    'bekommt jedes seine eigene Zeile — mit derselben Farbe '
                    'und Nummer wie im Wochenplan. Weicht eines von euren '
                    'festen Zeiten ab, klebt ein farbiger Hinweis daran: '
                    'eine Uhr für eine andere Zeit, eine Ortsmarke für '
                    'einen anderen Treffpunkt. '
                    'Ab 12 Uhr blickt sie auf morgen — der Vormittag gehört '
                    'der heutigen Fahrt. Ein Tipp darauf führt in die Woche '
                    '— die Sprechblase rechts in die Anmerkungen des Tages; '
                    'sie färbt sich, sobald jemand etwas geschrieben hat.',
              ),
              _Line(
                leading: Icon(Icons.directions_car, color: AppColors.driver),
                text:
                    'Darunter steht, wer dran ist — das Auto markiert, wer '
                    'als Nächstes fährt.',
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
                    'Darunter: was ihr gemeinsam erreicht habt, Fahrten und '
                    'Ersparnis über die Zeit und wie jede und jeder '
                    'unterwegs war.',
              ),
              _Line(
                text:
                    'Im Fahrten-und-Ersparnis-Diagramm zoomen zwei Finger '
                    'die Zeitachse, ein Finger schiebt den Ausschnitt, '
                    'Doppeltipp zeigt wieder alles. Ein Tipp auf einen '
                    'Namen in der Legende blendet dessen Linie aus.',
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
                leading: Icon(Icons.event_repeat),
                text:
                    'Wer an dem Tag schon in einer Fahrt steht, ist blass '
                    'und nicht wählbar — doppelt zählte doppelte Punkte. '
                    'Ausnahme: Wer nur eine Richtung dabei war, dem kann '
                    'die Rückfahrt noch fehlen.',
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
                    'Ein Tipp auf ein leeres Feld deiner Zeile trägt dich '
                    'ein — mehr braucht der Normalfall nicht. Oben links '
                    'steht zur Orientierung die Kalenderwoche mit ihrem '
                    'Zeitraum.',
              ),
              _Line(
                leading: Icon(Icons.badge_outlined),
                text:
                    'Tippst du noch einmal auf dasselbe Feld, geht ein '
                    'kleines Menü auf: nur eine Richtung, doch selbst '
                    'fahren, wieder austragen. „Ich möchte fahren" trägt '
                    'dich auch gleich ein, falls du es noch nicht warst — '
                    'und hat schon jemand anderes sich selbst als Fahrer '
                    'gesetzt, entsteht ein zweites Auto, statt ihn zu '
                    'verdrängen. Bei allen anderen geht das Menü sofort '
                    'auf — damit niemand aus Versehen bei jemandem dreht. '
                    'Eintragen darfst du weiterhin für jeden.',
              ),
              _Line(
                leading: Icon(Icons.looks_two_outlined),
                text:
                    'Fahrt ihr an einem Tag mit zwei oder mehr Autos, '
                    'bekommt jedes eine Farbe und eine Nummer. Die kleine '
                    'Marke an deinem Feld sagt dir, in welchem Auto du '
                    'sitzt — dieselbe Nummer wie bei deinem Fahrer. Bei '
                    'einem Auto steht keine Marke da: Dann fahren ohnehin '
                    'alle zusammen.',
              ),
              _Line(
                leading: Icon(Icons.schedule),
                text:
                    'Abfahrt und Treffpunkt für genau diesen Tag setzt, wer '
                    'an dem Tag fährt — sie stehen im Menü seines Feldes. '
                    'Fahrt ihr einmal früher los, tragt ihr es dort ein: '
                    'Alle, die an dem Tag mitfahren, bekommen ihre '
                    'Erinnerung dann zur neuen Zeit. Was ihr leer lasst, '
                    'bleibt bei euren festen Vorgaben. Ein Uhrsymbol am Tag '
                    'zeigt, dass dort etwas abweicht.',
              ),
              _Line(
                text:
                    'Fahrt ihr mit mehreren Autos und nicht gleichzeitig los, '
                    'steht in demselben Schirm oben ein Umschalter: „Ganzer '
                    'Tag" oder „Auto 2" — also sein eigenes. Dann bekommt '
                    'jeder seine Erinnerung zur Zeit seines Autos, und bei '
                    'einer Änderung wird nur geweckt, wer darin sitzt. Damit '
                    'die Zeit nicht am nächsten Tag am falschen Auto hängt, '
                    'hält MitFahrBar die Fahrer dieses Tages fest. Am Fahrer '
                    'eines abweichenden Autos hängt im Raster eine kleine '
                    'Uhr, und die Tageszeile nennt die Zeiten.',
              ),
              _Line(
                leading: Icon(Icons.event_seat),
                text:
                    'Landest du beim Eintragen in einem Auto, das anders '
                    'fährt als eure festen Zeiten, fragt dich MitFahrBar, ob '
                    'das passt. Mit „Passt" ist dir dein Platz in genau '
                    'diesem Auto sicher; mit „Nein, so nicht" fährst du dort '
                    'nicht mit, und es wird ein weiteres Auto eingeplant. '
                    'Umentscheiden geht jederzeit über das Menü deines '
                    'Feldes. Dein Ja gilt für genau die Zeit, der du '
                    'zugestimmt hast — ändert sie sich, wirst du neu '
                    'gefragt. Und wollen mehr in ein Auto, als hineinpassen, '
                    'sitzt drin, wer zuerst zugesagt hat.',
              ),
              _Line(
                leading: Icon(Icons.groups_outlined),
                text:
                    'Du kannst dir dein Auto auch selbst aussuchen: Ab zwei '
                    'Autos steht im Menü deines Feldes „Mit wem fahren?". '
                    'Dort siehst du jedes Auto mit seinem Fahrer, wer sonst '
                    'noch drinsitzt und ob es anders losfährt. Ein Auto, in '
                    'dem alle Plätze schon fest zugesagt sind, steht als '
                    '„voll" da und lässt sich nicht wählen. Mit „Egal" '
                    'nimmst du deine Wahl zurück und MitFahrBar verteilt '
                    'wieder selbst.',
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
                leading: Icon(Icons.chat_bubble_outline),
                text:
                    'Ein Tipp auf eine Tageszeile öffnet die Anmerkungen: '
                    'kurze Hinweise wie „Komme erst um 9". Sie ändern nichts '
                    'am Plan und nichts an den Punkten — sie sagen den '
                    'anderen Bescheid. Wer für den Tag benachrichtigt wird, '
                    'bekommt sie mit dem Abend-Blick oder der '
                    'Änderungs-Meldung aufs Handy; das kann aber dauern. '
                    'Was sofort ankommen muss, gehört weiter in WhatsApp '
                    'oder ans Telefon. Am Tag danach räumen sich '
                    'Anmerkungen von selbst weg — sie gelten nur ihrem Tag.',
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
                    'Die Statistik erzählt eure Zahlen: Fahrten pro Woche '
                    'mit Rekordwoche, die gemeinsame Ersparnis als Kurve '
                    'und als Ring je Person — zusammen immer dieselbe '
                    'Summe wie auf der Übersicht.',
              ),
              _Line(
                text:
                    'CO₂ rechnet die App aus Verbrauch und Spritart eurer '
                    'Autos; E-Autos zählen dabei 0 — geschätzt wird nichts.',
              ),
              _Line(
                text:
                    'Ganz oben wechseln kleine Insight-Karten wöchentlich: '
                    'Meilensteine, Rekorde und wer im Monat am meisten am '
                    'Steuer saß. Auch die Spritpreise eurer Region stehen '
                    'auf der Seite — verwaltet werden sie in den Parametern.',
              ),
              _Line(
                text:
                    'Am Ende stehen alle Zahlen je Person: Punkte, Fahrten, '
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
                    'an den Punkten ändert sich dadurch nichts. Von dort '
                    'kommt ihr auch zu den Spritpreisen: Die App sieht sich '
                    'die Tankstellen in eurem Umkreis an und merkt sich je '
                    'Woche einen Preis. Das ist noch in Arbeit und geht in '
                    'die Kostenrechnung nicht ein — eure eingetragenen '
                    'Werte gelten weiter.',
              ),
              _Line(
                leading: Icon(Icons.wb_twilight),
                text:
                    'Unter „Fahrt & Treffpunkt" stehen die Zeiten, die bei '
                    'euch immer gelten: Abfahrt hin, Abfahrt zurück und wo '
                    'ihr euch trefft. Sie erscheinen auf der Übersicht und '
                    'in der Benachrichtigung, damit niemand nachfragen muss. '
                    'Wer sie leer lässt, sieht davon nichts — und für den '
                    'einzelnen Tag bleibt die Anmerkung („komme erst um 9"). '
                    'Sind sie gepflegt, kann jeder sich unter '
                    '„Benachrichtigungen" kurz vor der Abfahrt erinnern '
                    'lassen.',
              ),
              _Line(
                leading: Icon(Icons.notifications_outlined),
                text:
                    'Benachrichtigungen: Sag der App, wer du bist, und dieses '
                    'Gerät bekommt abends den Blick auf morgen — und Bescheid, '
                    'wenn jemand den Plan bis zur Abfahrt noch umstellt. '
                    'Beide Uhrzeiten stellst du selbst ein, sie gelten nur für '
                    'dich. Nachricht kommt nur an Tagen, an denen du '
                    'eingetragen bist. Die Änderungs-Meldung hängt am '
                    'Abend-Blick: Schaltest du den aus, kommt gar nichts mehr. '
                    'Die Erinnerung zur Abfahrt ist davon unabhängig — sie '
                    'meldet sich kurz bevor es losgeht, hin und zurück, und '
                    'ist standardmäßig aus. Sie braucht die Abfahrtszeiten '
                    'unter „Parameter → Fahrt & Treffpunkt"; wie lange vorher, '
                    'stellst du selbst ein. '
                    'Die Sofort-Meldungen sind der dritte Fall und '
                    'standardmäßig an: Sie kommen, wenn dich jemand anderes '
                    'ein- oder austrägt und wenn eine eingetragene Fahrt '
                    'geändert oder gelöscht wird — auch eine ältere, denn '
                    'das verschiebt die Punkte aller Beteiligten. Was du '
                    'selbst änderst, bleibt still. '
                    'Hast du MitFahrBar gerade offen, erscheint sie als '
                    'Hinweis in der App statt als Benachrichtigung.',
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
              _Line(
                leading: Icon(Icons.info_outline),
                text:
                    'Über MitFahrBar zeigt, welche Version läuft und was '
                    'sich mit ihr geändert hat — und führt zum Update, '
                    'wenn eines bereitsteht.',
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
                leading: Icon(Icons.cloud_off_outlined),
                text:
                    'Ohne Empfang zeigt MitFahrBar den zuletzt geladenen '
                    'Stand. Oben steht dann, von wann er ist — im Funkloch '
                    'oder in der Tiefgarage siehst du also weiter, wer '
                    'fährt. Ändern lässt sich in diesem Zustand nichts: Ein '
                    'Eintrag braucht Verbindung, damit die anderen ihn auch '
                    'bekommen. Sobald das Netz zurück ist, verschwindet der '
                    'Hinweis von allein.',
              ),
              _Line(
                leading: Icon(Icons.admin_panel_settings_outlined),
                text:
                    'Gruppen entstehen in der Verwalter-Konsole, erreichbar '
                    'über den Login-Bildschirm: Wer eine Fahrgemeinschaft '
                    'gründet, richtet sich dort einmal ein eigenes Konto mit '
                    'echter E-Mail-Adresse ein und legt seine Gruppe an — '
                    'sofort nutzbar, bis zu fünf Gruppen je Konto. Dort wird '
                    'auch das Gruppenpasswort neu gesetzt, wenn es verloren '
                    'geht, und nur dort lässt sich eine Gruppe löschen. Eure '
                    'E-Mail sieht dabei niemand aus der Gruppe. Soll jemand '
                    'anderes übernehmen, löst die Verwalterin die Verknüpfung '
                    'in der Konsole; auch die E-Mail-Adresse lässt sich dort '
                    'ändern. Nur wer Postfach UND Passwort zugleich verliert, '
                    'kommt nicht mehr an das Verwalter-Konto — darum beides '
                    'gut aufheben.',
              ),
              _Line(
                text:
                    'Geplantes zählt nicht. Punkte entstehen erst, wenn '
                    'eine Fahrt eingetragen ist — Absagen kostet also '
                    'nichts.',
              ),
              _Line(
                leading: Icon(Icons.bug_report_outlined),
                text:
                    'Geht technisch etwas schief, meldet die App das von '
                    'selbst an die Entwicklung — nur Fehlertyp, App-Version '
                    'und Plattform, nie Namen oder Fahrten. Nach 90 Tagen '
                    'wird das automatisch gelöscht.',
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

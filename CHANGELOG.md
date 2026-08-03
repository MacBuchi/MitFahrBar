# Changelog

Alle nennenswerten Änderungen an diesem Projekt. Versionsschema:
`MAJOR.MINOR.PATCH`, gepflegt in `pubspec.yaml`; jeder Versions-Bump auf
`main` erzeugt automatisch Tag, GitHub-Release und den Web-Deploy.

## [0.59.0] – 2026-08-03

### Neu

- **Sofort Bescheid, wenn dich jemand ein- oder austrägt.** Bisher erfuhr man
  das erst mit der Abend-Meldung — jetzt kommt es binnen einer Minute, auch
  mittags. Nur die betroffene Person wird benachrichtigt, und wer selbst
  tippt, bleibt still (sofern im Menü unter „Ich bin" jemand gewählt ist).
- **Meldung, wenn eine eingetragene Fahrt geändert oder gelöscht wird** — an
  alle Beteiligten, die alten wie die neuen. Das gilt **auch für ältere
  Fahrten**: Wer eine Fahrt von letzter Woche korrigiert, verschiebt damit
  die Punkte aller Beteiligten, und das soll niemand übersehen.
- Beides schaltet ein Schalter „Sofort-Meldungen" unter „Benachrichtigungen",
  standardmäßig **an**. Er hängt bewusst nicht am Abend-Blick: Diese
  Meldungen kommen ja gerade außerhalb der Abendzeit.

### Bekannte Grenze

- Die Fahrt-Meldung entsteht auf dem Gerät, das die Änderung sieht. Wird die
  App in genau diesem Moment geschlossen, entfällt sie — anders als beim
  Wochenplan kann der stündliche Nachlauf eine Änderung nicht nachträglich
  erkennen.

## [0.58.0] – 2026-08-03

### Neu

- **Erinnerung kurz vor der Abfahrt.** Wer will, bekommt eine Meldung, bevor
  es losgeht — morgens zur Hinfahrt und nachmittags zur Rückfahrt, mit der
  Uhrzeit in der Kopfzeile („Abfahrt 07:30 Uhr"). Wie lange vorher, stellt
  jede Person selbst ein (Vorgabe: 15 Minuten).
- Sie ist **standardmäßig aus**: Anders als der Abend-Blick meldet sie sich
  auch an einem Tag, an dem sich gar nichts getan hat. Einzuschalten unter
  „Benachrichtigungen"; sie braucht die Abfahrtszeiten aus „Parameter →
  Fahrt & Treffpunkt" und ist unabhängig vom Abend-Blick.
- Die Erinnerung kommt **gerade auch dann, wenn die Fahrt schon eingetragen
  ist** — das ist ja der Moment, für den sie gedacht ist.

### Geändert

- Ein eingetragener Tag löst keine „Änderung"-Meldung mehr aus, wenn er
  eingetragen wird — wohl aber, wenn die Fahrt wieder gelöscht wird.

## [0.57.0] – 2026-08-03

### Neu

- **Feste Abfahrtszeiten und ein Treffpunkt.** Unter „Parameter" gibt es den
  neuen Abschnitt „Fahrt & Treffpunkt": Abfahrt hin, Abfahrt zurück und wo
  ihr euch trefft. Was ihr dort eintragt, steht ab sofort auf der Übersicht
  im Streifen „nächste Fahrt" **und** in der Benachrichtigung — niemand muss
  mehr nachfragen, und niemand muss in WhatsApp danach suchen.
- Ausfüllen ist freiwillig: Bleiben die Felder leer, ändert sich nichts, und
  jede Zeit lässt sich mit einem Tipp wieder herausnehmen. Für Abweichungen
  an einem einzelnen Tag bleibt die Anmerkung am Plantag der richtige Ort.

### Geändert

- Der Parameter-Screen ist in zwei Abschnitte geteilt („Strecke & Kosten",
  „Fahrt & Treffpunkt"). An den Punkten ändert weiterhin nichts davon etwas —
  auch eine neue Abfahrtszeit löst deshalb bewusst **keine**
  „Änderung"-Meldung aus.

## [0.56.0] – 2026-08-03

### Neu

- **Die Statistik erzählt jetzt eure Zahlen.** Der Reiter ist eine echte
  Auswertungs-Seite geworden: Fahrten pro Woche mit markierter Rekordwoche,
  „Gemeinsam gespart" als Kurve mit Meilenstein und einer ehrlichen
  Hochrechnung („bei eurem Tempo … bis Jahresende"), ein Ring, der die
  Ersparnis auf die Mitfahrenden aufteilt — zusammen immer dieselbe Summe
  wie auf der Übersicht — und euer Wochen-Muster als Raster, samt Hinweis,
  wenn ein Wochentag fast immer an derselben Person hängt. Die gewohnten
  Zahlen je Person stehen weiter am Ende der Seite.
- **CO₂ eingespart.** Gerechnet aus dem Verbrauch und der Spritart eurer
  eigenen Autos, nicht aus einer Pauschale — E-Autos zählen dabei 0. Mit
  Baum-Vergleich und den vermiedenen Solo-Kilometern.
- **Wöchentlich wechselnde Insight-Karten** ganz oben auf der Statistik:
  Strecken-Meilenstein („… — einmal bis Lissabon"), sparsamste Woche,
  Kilometerheld des Monats und Serien-Rekord ohne Solo-Fahrt.
- **Die Spritpreis-Verläufe stehen jetzt auch in der Statistik.** Verwaltet
  (Region, „Jetzt abfragen") werden sie wie bisher über die Parameter.

## [0.55.1] – 2026-08-02

### Behoben

- **Die Zeitachse von „Fahrten und Ersparnis" reicht nicht mehr in die
  Zukunft.** Ein versehentlich mit künftigem Datum eingetragener Fahrtag —
  im Erst-Import steckt so ein Tippfehler — streckte das Diagramm bis zu
  diesem Datum, und alle echten Wochen quetschten sich in den linken Rand.
  Die Achse endet jetzt wieder bei der letzten wirklich gefahrenen Woche.
  An der gesparten Summe und an den Punkten ändert sich nichts.

## [0.55.0] – 2026-08-02

### Neu

- **Fahrten und Ersparnis in einem Diagramm auf der Übersicht.** Ihr seht
  jetzt, was das Mitfahren über die Jahre gespart hat — als Kurve je
  Person und für die ganze Gruppe zusammen, gerechnet mit dem Spritpreis
  der jeweiligen Woche aus dem Preisarchiv statt mit einem Pauschalwert.
  Die Fahrten je Woche liegen als blasse Säulen dahinter, auf derselben
  Zeitachse.
- **Das Diagramm lässt sich bedienen:** Zwei Finger zoomen die Zeitachse,
  ein Finger schiebt den Ausschnitt, Doppeltipp zeigt wieder alles. Ein
  Tipp auf einen Namen in der Legende blendet dessen Linie aus.

### Geändert

- **„Kraftstoff gespart" ist jetzt eine ehrlichere Zahl.** Die Kachel
  rechnet mit denselben Wochenpreisen wie das Diagramm darunter — beide
  nennen immer dieselbe Summe. Weil die echten Preise über weite Strecken
  höher lagen als der Pauschalwert aus den Parametern, fällt die Zahl
  spürbar höher aus als bisher; sie war vorher zu niedrig, nicht falsch
  gerechnet.
- **„Fahrten pro Monat" ist in das neue Diagramm umgezogen.** Die Säulen
  zeigen weiter, wann gefahren wurde — jetzt je Woche und im selben Bild
  wie die Ersparnis. Die Jahresmarken bleiben. Die genaue Zahl je Monat
  zeigt das Bild nicht mehr; dafür gibt es Zoom und eine gemeinsame
  Zeitachse.
- Wo eine Woche keinen gemessenen Spritpreis hat, ist die Kurve ab dort
  gestrichelt („Preis geschätzt"). Strom zählt dabei nicht als Schätzung:
  Der Preis kommt bewusst aus euren Parametern.

## [0.54.0] – 2026-08-02

### Neu

- **Das Preisdiagramm reicht jetzt so weit zurück, wie es Daten gibt.**
  Bisher zeigte es immer nur die letzten 26 Wochen. Inzwischen sind die
  Preise seit Anfang 2023 nachgetragen — dreieinhalb Jahre, von denen ihr
  fünf Monate gesehen hättet. Das Fenster wächst nun von selbst mit; eine
  frisch eingerichtete Gruppe sieht weiterhin ein halbes Jahr.

### Geändert

- **Wochen ohne Fahrt reißen das Diagramm nicht mehr nach unten.** Für
  solche Wochen gibt es keinen Preis, und bisher setzte die App dort den
  Wert aus euren *Parametern* ein. Der liegt aber deutlich unter dem, was
  Sprit tatsächlich kostet — die Kurve stürzte also jedes Mal ab und stieg
  danach wieder, obwohl gar nichts passiert war. Jetzt wird zwischen den
  beiden benachbarten Messungen durchgezogen, weiter gestrichelt. Die
  Zahlen aus den Parametern erscheinen nur noch, solange überhaupt nichts
  gemessen wurde.
- **Die Kurve endet, wo die Messungen enden.** Bisher wäre sie bis zum
  heutigen Tag weitergelaufen und hätte dabei den zuletzt bekannten Preis
  gehalten — wer ein Jahr nicht fährt, hätte eine schnurgerade Linie über
  das ganze Jahr gesehen und einen Preis, den nie jemand gemessen hat.
- Die Zeitachse nennt die Jahreszahl, sobald das Diagramm über einen
  Jahreswechsel geht. „05.06." bis „27.07." las sich wie sieben Wochen,
  gemeint waren dreieinhalb Jahre.
- Unter *Über MitFahrBar* steht jetzt auch, woher die **zurückliegenden**
  Preise stammen: aus dem historischen Preisarchiv von Tankerkönig, das
  unter einer anderen Lizenz steht als die tagesaktuelle Abfrage.

## [0.53.0] – 2026-08-02

### Neu

- **Die App schaut sich jetzt selbst an, was Sprit kostet** — noch in
  Arbeit, und bewusst ohne Wirkung auf eure Zahlen. Unter *Parameter*
  gibt es den neuen Weg „Spritpreise ansehen": Ihr sagt einmal, wo ihr
  tankt, und die App sieht sich dreimal täglich die Tankstellen im
  Umkreis von 20 Kilometern an. Daraus entsteht je Woche **ein** Preis
  für Diesel, Super E5 und Super E10 — nicht der billigste, den man
  ohnehin nie erwischt, sondern ein günstiger: der Wert, den zehn
  Prozent aller Messungen unterbieten.
- **Warum das noch nichts kostet oder spart:** Die Ersparnis in der
  Statistik rechnet weiter mit den Preisen, die ihr von Hand pflegt.
  Umgestellt wird erst, wenn für **jede** gefahrene Woche ein Preis
  vorliegt — vorher wäre es eine Rechnung mit Löchern. Im Diagramm seht
  ihr genau das: Wochen ohne Messung sind gestrichelt und heller
  gezeichnet, mit dem Hinweis „aus den Parametern".
- **Strom bleibt vorerst Handarbeit.** Neu ist, dass ihr Hausstrom und
  Ladesäule getrennt eintragen könnt, ebenso Super E5 und Super E10 —
  bisher gab es je einen gemeinsamen Wert. Eure bisherigen Angaben
  bleiben; E10 startet zehn Cent unter E5, die Ladesäule mit 0,59 €.

- **Unter „Über MitFahrBar" steht jetzt, woher die Daten kommen** —
  Spritpreise von der Tankerkönig-Spritpreis-API (CC BY 4.0, Daten der
  Markttransparenzstelle für Kraftstoffe), Ortssuche über OpenStreetMap.
  Beide Lizenzen verlangen die Nennung; sie gehört dorthin, wo man nach
  Herkunft sucht, und nicht nur auf den Screen, der die Daten zeigt.

## [0.52.0] – 2026-07-30

### Neu

- **Auch Abstürze und Einfrieren melden sich jetzt von selbst** (Wunsch
  #144, Ausbau der Fehler-Meldung aus 0.50.0). Bisher blieb unsichtbar,
  wenn die App hart beendet wurde — eingefroren, abgestürzt oder vom
  System wegen Speichermangel beendet: So etwas überlebt keine App, also
  konnte sie es auch nicht melden. Jetzt fragt die App beim nächsten
  Start das Android-System, warum sie zuletzt beendet wurde (ab
  Android 11), und meldet es mit dem Zeitpunkt des Vorfalls. Normales
  Schließen wird selbstverständlich nicht gemeldet, und es gilt dieselbe
  Zusage wie bisher: **nie Namen, nie Fahrten**, automatische Löschung
  nach 90 Tagen. Im Browser ändert sich nichts.

## [0.51.0] – 2026-07-30

### Neu

- **Ab 12 Uhr blickt die Übersicht auf morgen** (Wunsch #131). Der
  Vormittag gehört der heutigen Fahrt, der Nachmittag der morgigen — das
  „Nächste Fahrt"-Banner wechselt jetzt mittags, nicht erst wenn die
  heutige Fahrt eingetragen ist. Der Wochenplaner zieht mit: Ab
  Freitagmittag zeigt er die kommende Woche, so wie bisher erst am
  Wochenende. Nachtragen geht wie gewohnt über den Eintragen-Knopf und
  die Historie.
- **Anmerkungen räumen sich am Folgetag von selbst weg** (ebenfalls #131).
  Eine Anmerkung wie „Komme erst um 9" gilt ihrem Tag — danach ist sie
  erledigt und wird automatisch gelöscht. Nebeneffekt: Namen bleiben
  nicht länger gespeichert als nötig. Anmerkungen für die weiteren
  Plantage gab es übrigens schon — die Übersicht zeigt immer die des
  Tages, um den es als Nächstes geht.

## [0.50.1] – 2026-07-30

### Behoben

- **Wer am Tag schon in einer Fahrt steht, lässt sich nicht mehr doppelt
  eintragen** (Rückmeldung #143). Die Kachel bleibt sichtbar, ist aber blass
  und zeigt „eingetragen" — so sieht man beim zweiten Auto sofort, wer schon
  versorgt ist, und niemand bekommt aus Versehen doppelte Punkte. Ausnahme:
  Wer nur eine Richtung (1-way) dabei war, bleibt wählbar — die Rückfahrt
  kann ja noch fehlen. Auch die Vorauswahl aus dem Wochenplan überspringt
  jetzt, wer schon in einer Fahrt steht. Und wer erst gewählt und dann auf
  einen Tag gewechselt wird, an dem er schon fährt, wird namentlich
  angemerkt statt still mitgespeichert.

## [0.50.0] – 2026-07-30

### Neu

- **Technische Fehler melden sich jetzt von selbst bei der Entwicklung**
  (Wunsch #136). Bisher blieb ein Fehler unsichtbar, wenn ihn niemand von
  Hand als Rückmeldung schickte — und wer einen Absturz erlebt, schreibt
  selten noch eine. Übertragen wird bewusst wenig: Fehlertyp, App-Version
  und Plattform — **nie Namen, nie Fahrten**, und nach 90 Tagen wird alles
  automatisch gelöscht. Funklöcher und ähnliches Alltagsrauschen werden
  gar nicht erst gemeldet. Die Bedienungsanleitung erklärt das im
  Abschnitt „Gut zu wissen"; an der Rückmeldung von Hand ändert sich
  nichts.

## [0.49.1] – 2026-07-29

### Behoben

- **Die Minuten-Zustellung aus 0.49.0 lief auf dem Server noch nicht an** —
  eine benötigte Datenbank-Erweiterung war dort nicht eingeschaltet (auf dem
  Teststack ist sie es immer, deshalb fiel es erst in Produktion auf).
  Verpasst wurde nichts: Die Meldungen lagen bereit und der stündliche
  Auffang-Weg lief weiter. An der App selbst ändert sich nichts.

## [0.49.0] – 2026-07-29

### Verbessert

- **Änderungen am Wochenplan kommen jetzt binnen einer Minute aufs Handy.**
  Bisher fragte ein Dienst in Abständen nach, ob es etwas zu melden gibt —
  und kam dabei oft erst nach einer Stunde dazu. Wer morgens um 7:05 umplante,
  dessen Meldung erreichte die anderen manchmal erst nach der Abfahrt.
  Jetzt meldet sich die Datenbank selbst, sobald sich etwas geändert hat.
- **Wer im Planer mehrmals hintereinander tippt, löst trotzdem nur eine
  Meldung aus.** Nach der letzten Änderung wird eine Minute gewartet — so
  bekommt die Gruppe den fertigen Stand und nicht jeden Zwischenschritt.
- Am Abend-Blick ändert sich nichts: Er kommt wie gewohnt zur eingestellten
  Zeit, und wer ihn abgeschaltet hat, bekommt weiterhin nichts.

## [0.48.0] – 2026-07-29

### Verbessert

- **Vorbereitung: Benachrichtigungen sollen bald in einer Minute ankommen
  statt erst nach Stunden.** Bisher fragt ein Dienst alle zehn Minuten nach,
  ob es etwas zu melden gibt — tatsächlich kommt er oft nur stündlich dazu.
  Wer morgens um 7:05 den Plan umstellt, dessen Meldung erreicht die anderen
  deshalb manchmal erst nach der Abfahrt. Diese Version legt dafür die
  Grundlage: Die App hinterlegt beim Ändern schon, was zu melden wäre.
  **Für euch ändert sich noch nichts** — verschickt wird weiter wie bisher.
  Die Umstellung kommt mit der nächsten Version.

## [0.47.0] – 2026-07-28

### Verbessert

- **Im Monats-Diagramm seht ihr jetzt, wo ein Jahr endet.** An jedem
  Jahreswechsel steht eine senkrechte Linie mit der Jahreszahl daneben —
  vorher folgte auf „Dez" ein „Jan", das genauso aussah wie das vorige.
- **Eure eigene Zeile im Wochenplan ist zart hinterlegt** und der Name etwas
  kräftiger, sobald ihr unter „Ich bin" jemanden ausgewählt habt. Das ist nur
  Orientierung: Eintragen dürft ihr weiterhin für jeden.
- **Die Banner über der Übersicht sind neu eingefärbt** — nach den Vorlagen
  aus dem Design-Set der App. Die Kachel mit der nächsten Fahrt trägt jetzt
  einen Farbverlauf im Türkis der Marke; der fliederfarbene Ton, der aus der
  Reihe fiel, ist weg.
- **Der Hinweis auf eine neue Version fällt bewusst heraus**: Er ist der
  einzige in einem warmen Orange. Er kommt und geht — auffallen ist sein
  Zweck.
- **Der Zähler an der Sprechblase hat eine eigene Farbe.** Liegt eine
  Anmerkung für den Tag vor, ist sie am Banner nicht mehr zu übersehen.
- **Benachrichtigungen sind farbig.** Auf Android trägt das kleine Symbol in
  der Leiste jetzt die Farbe der App statt eines Graus, und was ankommt,
  während ihr die App gerade offen habt, sieht genauso aus wie draußen.

Alle Farbpaare sind auf Lesbarkeit nachgerechnet — auch die auf dem Verlauf.

## [0.46.0] – 2026-07-27

### Neu

- **Ihr könnt jetzt Anmerkungen an einen Tag schreiben** — kurze Hinweise wie
  „Komme erst um 9" oder „Ich parke heute woanders". Zu finden über die
  Sprechblase am Banner der nächsten Fahrt oder mit einem Tipp auf eine
  Tageszeile im Wochenplan; dort steht auch, wie viele es sind.
- **Wer benachrichtigt wird, bekommt die neueste Anmerkung aufs Handy** — im
  Abend-Blick oder als Änderungs-Meldung. Achtung: **Das kann eine Weile
  dauern.** Was sofort ankommen muss, sagt ihr weiterhin besser per WhatsApp
  oder am Telefon. Wer den Abend-Blick abgeschaltet hat, bekommt auch keine
  Anmerkungen — der Benachrichtigungs-Screen sagt das jetzt dazu.
- Wer unter „Ich bin" jemanden ausgewählt hat, schreibt sofort los; sonst
  wählt ihr vorher kurz aus, wer schreibt. Löschen darf jeder — es ist wie
  im Planer, wo auch jeder für jeden einträgt.

Die Anmerkungen ändern **nichts** am Plan und nichts an den Punkten. Damit
ist auch der Wunsch nach einer Kennzeichnung für abweichende Zeiten erledigt.

## [0.45.0] – 2026-07-27

### Neu

- **Im Wochenplaner tippst du deine eigene Zeile direkt durch.** Bei allen
  anderen fragt die App kurz nach — damit niemand aus Versehen bei jemandem
  dreht. Eintragen darfst du weiterhin für jeden: Die Rückfrage bietet gleich
  alle drei Möglichkeiten an („dabei", „nur eine Richtung", „kann nicht"), das
  sind zwei Tipps statt bis zu drei beim Durchschalten.
- Wer im Menü unter „Ich bin" niemanden ausgewählt hat, für den bleibt das
  Raster wie bisher — freies Tippen, keine Rückfrage.

## [0.44.0] – 2026-07-27

### Neu

- **Die App fragt beim ersten Start, wer du bist.** Das ist keine Anmeldung —
  ihr teilt euch weiterhin einen Zugang. Es sagt nur diesem Gerät, wen es
  meint. Ändern lässt sich das jederzeit im Menü oben rechts unter „Ich bin",
  und wer für jemand anderen eintragen will, stellt einfach um.
- **Wer schon Benachrichtigungen eingerichtet hat, wird nicht neu gefragt** —
  die App übernimmt die bestehende Zuordnung.
- **Wer die Frage überspringt**, sieht auf der Startseite einen Hinweis: Ohne
  Auswahl gibt es keine Benachrichtigungen. Ein Tipp darauf holt die Auswahl
  nach.

### Geändert

- **Die Personen-Auswahl ist aus den Benachrichtigungen ausgezogen.** Dort
  steht jetzt ein einfacher Schalter „Benachrichtigungen auf diesem Gerät";
  für wen sie gelten, sagt die Auswahl im Menü. Solange niemand gewählt ist,
  ist der Menüpunkt ausgegraut und sagt auch, warum.

## [0.43.0] – 2026-07-27

### Neu

- **„Fahrten pro Monat" zeigt jetzt eure ganze Historie.** Bisher standen dort
  zwölf Monate, egal wie lange ihr schon fahrt. Jetzt reicht das Diagramm bis
  zur ersten eingetragenen Fahrt zurück — was nicht in die Breite passt, holt
  ihr mit einem Wisch nach rechts herein.
- **Das Diagramm hat eine Werteachse bekommen.** Links stehen runde Zahlen mit
  dezenten Hilfslinien, dafür sind die Zahlen über den Säulen weggefallen. Bei
  zwei Dutzend Monaten wäre an jeder Säule ohnehin kein Platz mehr gewesen.

## [0.42.0] – 2026-07-27

### Neu

- **Die nächste Fahrt steht jetzt ganz oben auf der Übersicht.** Wer die App
  öffnet, sieht sofort, um welchen Tag es geht, wer fährt und wer dabei ist —
  dasselbe, was abends aufs Handy kommt, nur ohne Benachrichtigung. Ein Tipp
  darauf führt direkt in die Woche. Ist für den Tag schon eine Fahrt
  eingetragen, rückt der Hinweis auf den nächsten offenen Tag; am Freitag und
  Samstag steht dort bereits der kommende Montag.

### Behoben

- **Exportierte Dateien heißen wieder richtig.** Eine Sicherung hieß seit der
  Umbenennung weiterhin `ridebuddy-fahrten-….csv` — jetzt
  `mitfahrbar-fahrten-….csv`. Ältere Dateien lassen sich unverändert weiter
  importieren; der Import liest den Inhalt, nicht den Namen.

## [0.41.0] – 2026-07-26

### Behoben

- **Zwei Gruppen konnten nicht beide eine „Anna" haben.** Namen von Personen
  mussten bisher über *alle* Fahrgemeinschaften hinweg verschieden sein — ein
  Überbleibsel aus der Zeit, als es nur eine einzige Gruppe gab. Wer einen
  Namen anlegte, den eine fremde Gruppe schon führte, bekam ihn nicht. Jetzt
  gilt die Regel nur noch innerhalb der eigenen Gruppe: Dort gehört ein Name
  genau einer Person, außerhalb ist er frei.

- **Ein abgelehnter Name verschwand still.** Klappte das Anlegen nicht, schloss
  sich der Dialog, als wäre alles gut — die Person fehlte einfach in der Liste.
  Jetzt sagt die App, was los ist: „„Anna" gibt es in der Gruppe schon."
  Dasselbe gilt für den Schalter „aktiv": Scheitert das Speichern, steht es
  jetzt da, statt dass nichts passiert.

### Geändert

- **Groß-/Kleinschreibung zählt bei Namen nicht mehr.** „anna" und „Anna" sind
  dieselbe Person, ebenso ein versehentliches Leerzeichen am Ende. Das
  verhindert Doppel-Einträge, die später niemand mehr auseinanderhalten kann —
  und ist genau die Regel, mit der der CSV-Import Namen ohnehin zuordnet.

## [0.40.1] – 2026-07-26

### Geändert

- **„Änderungen bis zur Abfahrt" sagt jetzt, dass es den Abend-Blick
  braucht.** Beides hing schon immer zusammen: Eine Änderungsmeldung kommt
  nur, wenn ihr an dem Abend schon den Blick auf morgen bekommen habt — ohne
  ihn wäre sie die erste Nachricht des Tages und ohne Bezug. Im Screen sah es
  aber nach zwei unabhängigen Schaltern aus. Wer den Abend-Blick abschaltete,
  bekam still gar nichts mehr. Jetzt ist der zweite Schalter in dem Fall
  ausgegraut und erklärt sich. Eure Einstellung bleibt dabei gespeichert:
  Schaltet ihr den Abend-Blick wieder ein, ist sie unverändert da.

## [0.40.0] – 2026-07-26

### Behoben

- **Benachrichtigungen kamen nicht an, wenn die App gerade offen war.** Weder
  Android noch der Browser zeigen eine Benachrichtigung an, solange man in der
  App ist — sie wurde bisher einfach verworfen. Das betraf nicht nur den
  Test-Knopf: Auch der Abend-Blick auf den nächsten Tag konnte so verloren
  gehen, und er wurde danach nicht noch einmal geschickt. Jetzt erscheint sie
  als Hinweis in der App, egal auf welchem Bildschirm ihr gerade seid.

- **Im Browser ließen sich Benachrichtigungen gar nicht einrichten.** Die
  Auswahl „Ich bin …" sprang immer auf „niemand" zurück. Ursache war eine
  Hintergrund-Datei, die MitFahrBar an der falschen Stelle gesucht hat.

- **Der Test-Knopf meldet nur noch Erfolg, wenn wirklich etwas verschickt
  wurde**, und sagt dazu, dass die Benachrichtigung erst auf dem
  Startbildschirm sichtbar wird. Vorher meldete er „unterwegs", auch wenn
  nichts ankam.

## [0.39.0] – 2026-07-26

### Geändert

- **Freigaben gibt es nicht mehr.** Der Bildschirm „Gruppen-Freigaben" und die
  Sonderrolle der Verwaltungs-Gruppe entfallen. Verwaltet wird ausschließlich
  über die **Verwalter-Konsole** mit echter E-Mail-Adresse — dort funktioniert
  „Passwort vergessen", ein vergessenes geteiltes Gruppenpasswort kann also
  niemanden mehr blockieren. Genau das war vorher der Fall: Die Freigabe hing
  an einem Zugang, den mehrere Leute teilen und für den es keinen Weg zurück
  gab.

- **Gruppen, die noch auf Freigabe warteten, gehören jetzt ihrem Verwalter**
  und sind nutzbar. Alte Anfragen ohne Verwalter-Konto wurden entfernt; ihr
  Anmeldename ist damit wieder frei.

- Meldet sich ein Zugang an, der nie als Fahrgemeinschaft eingerichtet wurde,
  erklärt die App das jetzt statt auf eine Freigabe zu verweisen, die es nicht
  mehr gibt.

## [0.38.0] – 2026-07-26

### Behoben

- **Der Update-Knopf auf dem Sperr-Bildschirm tat nichts.** Wer die Meldung
  „Update erforderlich" bekam, saß fest: Tippen bewirkte nichts, und die App
  ließ sich nur retten, indem man sie löschte und neu installierte. Der Knopf
  öffnet jetzt wieder den Update-Dialog.

  Damit so etwas nicht noch einmal alles blockiert, steht darunter ein
  **zweiter Weg: „Stattdessen im Browser laden"**. Er kommt ohne den Dialog
  aus. Meldet sich gar kein Browser, zeigt der Bildschirm die Adresse zum
  Abtippen — es bleibt in jedem Fall ein Weg zur neuen Version.

## [0.37.0] – 2026-07-26

### Geändert

- **Gruppen entstehen jetzt in der Verwalter-Konsole.** Wer eine
  Fahrgemeinschaft anlegen will, richtet sich dort einmal ein eigenes Konto
  mit echter E-Mail-Adresse ein und legt seine Gruppe selbst an — **sofort
  nutzbar**, ohne Warten auf eine Freigabe. Ein Konto darf bis zu **fünf**
  Gruppen betreuen, jede mit eigener Karte in der Konsole. Anmeldename und
  Gruppenpasswort gibt man wie bisher an alle Mitglieder weiter; die melden
  sich damit ganz normal an.

  „Neue Gruppe anfragen" verschwindet damit vom Anmelde-Bildschirm. Der Weg
  dorthin führt über **„Verwalter-Konsole"**.

- **Das Gruppenpasswort wird beim Anlegen zweimal eingetippt.** Bei einem
  Tippfehler kam vorher niemand mehr in die neue Gruppe hinein — auch die
  Person nicht, die sie angelegt hatte.

- **Eine Gruppe zu löschen löscht nicht mehr das eigene Verwalter-Konto.**
  Es betreut ja möglicherweise weitere Gruppen. Nach dem Löschen bleibt man
  angemeldet und sieht die restliche Liste.

## [0.36.0] – 2026-07-26

### Neu

- **Benachrichtigungen zum Wochenplan.** Am Abend vorher zeigt euch die App,
  wie der nächste Tag aussieht: wer fährt, wer dabei ist und was ihr selbst
  eingetragen habt. Ändert danach noch jemand den Plan, kommt bis zur
  Abfahrt eine kurze Meldung hinterher — und wer ausgetragen wird, erfährt
  es auch.

  Einzurichten unter **Menü → Benachrichtigungen**: einmal sagen, wer ihr
  seid, dann die beiden Uhrzeiten wählen (abends 21 Uhr und Abfahrt 7:30 Uhr
  sind vorgeschlagen). Beide gelten nur für euch selbst — jeder stellt sich
  ein, was ihm passt. Es kommt nur an Tagen etwas, an denen ihr auch
  eingetragen seid, und nach der Abfahrtszeit nie.

  Wer nichts einstellt, bekommt nichts. Zum Ausprobieren gibt es im selben
  Bildschirm einen Knopf für eine Test-Benachrichtigung.

  Auf Android braucht es dafür einmal die Erlaubnis für Benachrichtigungen;
  im Browser funktioniert es, wenn ihr MitFahrBar zum Startbildschirm
  hinzugefügt habt.

## [0.35.0] – 2026-07-26

### Behoben

- **„Passwort vergessen" funktioniert jetzt auch vom Handy.** Wer sein
  Verwalter-Passwort in der App zurücksetzen wollte, bekam eine Mail, deren
  Link ins Leere lief — ohne jede Fehlermeldung. Statt eines Links schickt
  MitFahrBar nun einen **sechsstelligen Code**: eintippen, neues Passwort
  wählen, fertig — alles in derselben Maske und auf jedem Gerät. Betrifft
  nur die Verwalter-Konsole; am Gruppen-Login ändert sich nichts.

### Geändert

- **Auch die Registrierung der Verwalter-Konsole bestätigt jetzt per Code.**
  Kein Umweg mehr über den Browser: Code aus der Mail eintippen, und man ist
  direkt in der Konsole. Die „Bestätigungs-Mail erneut senden"-Hilfe gibt es
  weiterhin.

## [0.34.2] – 2026-07-25

### Neu

- **„Über MitFahrBar" im Menü:** zeigt, welche Version bei euch läuft
  und was sich mit ihr geändert hat („Was ist neu") — und führt direkt
  zum Update, wenn eines bereitsteht. Bisher war die Versionsnummer nur
  tief im Lizenz-Dialog zu finden.

## [0.34.1] – 2026-07-25

### Behoben

- **Der Startbildschirm und die Anmeldeseite sagen jetzt auch
  MitFahrBar.** Der zweifarbige Schriftzug war bei der Umbenennung
  durchgerutscht und begrüßte euch noch als RideBuddy.
- **Die gelbe Doppellinie unter dem Namen ist weg.** Sie war nie
  Absicht, sondern ein Darstellungsfehler des Startbildschirms.
- **Im dunklen Design sind die Reifen wieder zu sehen.** Ihr
  Fast-Schwarz versank bisher im dunklen Hintergrund — übrig blieben
  nur die hellen Radnaben.

### Geändert

- **Der Schriftzug betont jetzt „Fahr"** — Mit**Fahr**Bar, die Mitte in
  Markenblau.
- **Das Auto steht auf einer Straße:** eine dezente Linie unter den
  Rädern, auf dem Startbildschirm und der Anmeldeseite. Und während der
  Anfahrt biegen sich die drei Fahrtwind-Streifen hinter dem Auto leicht
  — wie echte Verwirbelung.

## [0.34.0] – 2026-07-24

### Wichtig

- **Die App heißt jetzt MitFahrBar.** Neuer Name, gleiche App — eure
  Fahrten, Punkte und Einstellungen bleiben unverändert.
- **Auf Android müsst ihr einmalig neu installieren.** Der Umzug ändert
  die Kennung der App, und für Android ist sie damit eine neue: Die alte
  RideBuddy-App bekommt kein Update mehr. Ladet euch MitFahrBar einmal
  neu herunter — danach läuft alles wie gewohnt weiter, und die alte App
  könnt ihr löschen. Am Zugang ändert sich nichts: gleicher Gruppenname,
  gleiches Passwort.
- **Die Web-Adresse ist neu:** `https://macbuchi.github.io/MitFahrBar/`.
  Die alte Adresse leitet weiter, aber wer die App auf dem Startbildschirm
  hat, legt sie am besten einmal neu an.
- **Mails kommen künftig von einem neuen Absender** (`MitFahrBar`,
  `noreply-mitfahrbar@mcbuchi.de`) — falls ihr irgendwann einen Link zum
  Zurücksetzen des Passworts anfordert, sucht danach.

## [0.33.0] – 2026-07-24

### Neu

- **Arbeitsweg und Spritpreise stellt ihr jetzt selbst ein** (euer
  Wunsch): Menü oben rechts → **Parameter**. Dort stehen die einfache
  Strecke in Kilometern und die Preise für Strom, Diesel und Benzin.
  Bisher rechnete RideBuddy fest mit 30 km — jetzt mit eurer Zahl, und
  Kilometer wie gesparte Kosten stimmen sofort für alle. An den Punkten
  ändert sich dadurch nichts.
- Die Preise pflegt ihr weiterhin von Hand. Automatisch aus dem Netz holt
  RideBuddy sie bewusst nicht: Für die Ersparnis reicht ein grober Wert,
  und dafür wäre ein weiterer Fremddienst nötig.

## [0.32.1] – 2026-07-24

### Geändert

- **Die beiden Auszeichnungen im Dashboard heißen jetzt richtig
  geschrieben „Volle Kischd" und „Faschd alloi"** — wie es die Gruppe
  ausspricht.

## [0.32.0] – 2026-07-24

Euer Feedback vom 24. Juli — danke, weiter so!

### Behoben

- **Der Wochenplaner zeigt zu eingetragenen Fahrten wieder alle
  Mitfahrenden.** Bisher war im Raster nur der Fahrer zu sehen, wenn die
  Fahrt direkt über „Fahrt eintragen" entstanden war; Mitfahrer standen
  fälschlich auf „kann nicht". Jetzt zeigt ein eingetragener Tag die
  komplette Besetzung der Fahrt — inklusive 1-way.

### Neu

- **Der Wochenplaner nennt oben links die Kalenderwoche** samt Zeitraum
  (z. B. „KW 30, 20.7.–24.7.") — zur Orientierung, welche Woche gerade
  geplant wird.
- **Der Kalender beim Eintragen markiert Tage, an denen schon eine Fahrt
  steht**, mit einem Punkt. So seht ihr beim Nachtragen sofort, welche
  Tage noch fehlen.

## [0.31.0] – 2026-07-24

### Verbessert

- **Der Wochenplaner gleicht die Fahrhäufigkeit besser aus.** Wie oft
  jemand fährt, hängt jetzt noch enger am Durchschnitt der Gruppe: Wer
  zuletzt seltener dran war, bekommt eher die kleinen Tage, Vielfahrer
  die vollen. Am Grundprinzip ändert sich nichts — wer die wenigsten
  Punkte hat, ist dran; der Feinausgleich wirkt nur bei praktisch
  gleichem Punktestand. Grundlage ist eine Langzeit-Simulation über
  acht Jahre mit den echten Fahrmustern der Gruppe: Punkte und
  Fahranteile pendeln damit dauerhaft eng um den Mittelwert — enger,
  als es die von Hand geplante Vergangenheit je war.

## [0.30.1] – 2026-07-24

### Intern

- **Für die Gruppen ändert sich nichts Sichtbares.** Das Testsystem fährt
  die App jetzt zusätzlich als echte Web-App im echten Browser durch die
  Verwalter-Abläufe — inklusive der Bestätigungs-Mail, die dabei wirklich
  geöffnet wird. Noch ein Sicherheitsnetz mehr, bevor Updates zu euch
  gehen.

## [0.30.0] – 2026-07-24

### Verbessert

- **Schutz vor automatisiertem Missbrauch:** Neue Gruppen-Anfragen sind
  jetzt serverseitig gedrosselt — mehr als eine Handvoll pro Stunde geht
  nicht mehr durch. Echte Fahrgemeinschaften merken davon nichts; wer in
  die (unwahrscheinliche) Drossel läuft, bekommt eine ehrliche Meldung
  statt eines Fehlers und versucht es einfach später noch einmal.

## [0.29.0] – 2026-07-24

### Neu

- **Die Verwalter-Konsole ist übergabefähig.** Wer die Gruppe verwaltet,
  kann die Verknüpfung jetzt selbst lösen (mit Passwort-Bestätigung) —
  danach kann sich die Nachfolgerin ganz normal mit dem Gruppen-Login
  verknüpfen. Fahrten und Einstellungen bleiben dabei unberührt.
- **E-Mail-Adresse des Verwalter-Kontos änderbar.** Zur Sicherheit gehen
  Bestätigungs-Links an die alte und die neue Adresse; erst wenn beide
  angetippt sind, gilt die neue.
- Gut zu wissen: Nur wer Postfach **und** Passwort zugleich verliert,
  kommt nicht mehr an sein Verwalter-Konto — darum beides gut aufheben.
  Die Anleitung erklärt das jetzt auch.

## [0.28.0] – 2026-07-24

### Neu

- **Mehrere Autos an einem Tag** (euer Wunsch, Teil 2): Reicht kein
  einzelnes Auto für alle, schlägt der Wochenplaner jetzt mehrere Fahrer
  vor — so wenige Autos wie möglich, ein großes schlägt zwei kleine, und
  wer fährt, entscheiden wie immer die Punkte. Die Tageszeile sagt dann
  z. B. „Anna + Ben fahren · 2 Autos".
- **Fahrer selbst wählen, auch mehrere:** Das Tausch-Symbol öffnet eine
  Mehrfach-Auswahl mit Live-Rechnung, ob die Plätze reichen. „Zurück zum
  Vorschlag" räumt das Übersteuern wieder ab.
- **Eintragen je Auto:** Bei einem geteilten Tag öffnet sich der
  Fahrten-Editor für jedes Auto nacheinander, fertig vorbelegt — gebucht
  wird erst mit jedem Speichern, nichts passiert still im Hintergrund.
  Wer zwischendrin abbricht, trägt den Rest einfach von Hand nach.
- **Historie:** Fahren an einem Tag mehrere Autos, trägt die zweite
  Fahrt die Marke „2. Auto".

### Wichtig

- Ältere App-Versionen können das Übersteuern des Fahrers nicht mehr
  speichern — die App bittet nach diesem Update einmalig um die neue
  Version. Einfach aktualisieren, alles andere bleibt, wie es war.

## [0.27.0] – 2026-07-24

### Neu

- **Auge-Symbol an allen Passwortfeldern.** Antippen zeigt das Getippte —
  der beste Schutz vor Tippfehlern, gerade auf dem Handy.
- **Bestätigungs-Mail im Griff.** Wer ein Verwalter-Konto anlegt und den
  Bestätigungs-Link verlegt (oder ihn im Spam vermutet), kann die Mail
  jetzt direkt in der Konsole erneut anfordern. Und wer sich vor der
  Bestätigung anzumelden versucht, erfährt, woran es liegt — statt eines
  irreführenden „Passwort falsch".

### Behoben

- **„Neue Gruppe anfragen" wäre ins Leere gelaufen.** Seit Verwalter-
  Konten ihre E-Mail-Adresse wirklich bestätigen müssen, hätte auch eine
  neue Gruppen-Anfrage auf eine Bestätigungsmail gewartet — die bei einem
  Gruppen-Zugang nie ankommen kann. Die Anlage läuft jetzt auf dem Server
  und braucht gar keine Mail mehr. Betroffen war niemand: Seit der
  Umstellung gab es keine neue Anfrage.

## [0.26.0] – 2026-07-24

### Intern

- **Für die Gruppen ändert sich nichts Sichtbares.** Unter der Haube lernt
  der Wochenplaner, mit mehreren Autos an einem Tag zu rechnen (euer
  Wunsch, Teil 1): Reicht kein einzelnes Auto für alle, kann er künftig
  so wenige Autos wie möglich vorschlagen — sichtbar und bedienbar wird
  das mit dem nächsten Release. Nebenbei behoben: Ein Tag mit zwei
  bereits eingetragenen Fahrten zeigte im Planer nur eine davon, und das
  Hajo zählte dort die Plan-Einträge statt der tatsächlichen Mitfahrer.

## [0.25.1] – 2026-07-24

### Verbessert

- **Verwalter-Konsole: rundere Anmeldung.** „Passwort vergessen" fragt
  jetzt nur noch die E-Mail-Adresse ab — das Passwortfeld verschwindet,
  bis der Reset-Link angefordert ist. Und beim Registrieren will
  RideBuddy das Passwort zweimal sehen: Ein Tippfehler sperrte sonst
  das frische Konto sofort wieder aus.

## [0.25.0] – 2026-07-23

### Neu

- **„Fahrt eintragen" übernimmt den Wochenplan** (euer Wunsch): Wer für
  den gewählten Tag im Planer eingetragen ist, steht beim Öffnen schon
  in der Auswahl — 1-way bleibt 1-way. Wechselt das Datum, wandert die
  Vorauswahl mit, solange nichts von Hand geändert wurde; Handarbeit
  gewinnt immer. Den Fahrer schlägt RideBuddy wie gewohnt nach
  Punktestand vor.

## [0.24.0] – 2026-07-23

### Neu

- **„Was diese Woche ändert" im Wochenplaner** (euer Wunsch): Unter dem
  Raster rechnet RideBuddy vor, was die geplante Woche je Person
  bewirken würde — als Punktediff oder, umgeschaltet, als Änderung der
  Fahrrate in Promille. Reine Vorschau: An den echten Punkten ändert
  die Planung weiterhin nichts.

### Verbessert

- **Allein fahren zählt nicht mehr** (euer Wunsch): Eine Fahrt, bei der
  nur eine Person im Auto sitzt, geht in keine Kennzahl mehr ein —
  weder Punkte noch Fahranteil. In der Historie steht sie blass mit dem
  Hinweis „zählt nicht". Und wer beim Eintragen als Einziger dabei ist,
  kann nicht mehr versehentlich auf „nur eine Richtung" springen.

## [0.23.2] – 2026-07-23

### Verbessert

- **Das Hajo im Wochenplaner rechnet jetzt wie die Punkte** (euer
  Wunsch aus der Rückmeldung): Eine 1-way-Mitfahrt zählt fürs „vollste
  Auto der Woche" nur noch halb — genau wie beim Punktestand. Vorher
  zählte jeder Kopf ganz, und zwei halbe Mitfahrten wirkten „voller"
  als eine ganze.

## [0.23.1] – 2026-07-23

### Intern

- **Für die Gruppen ändert sich nichts Sichtbares.** Unter der Haube
  bekommt RideBuddy ein automatisches Testsystem: Jede Änderung wird ab
  jetzt gegen eine echte Test-Datenbank geprüft — inklusive der neuen
  Verwalter-Konsole und der Passwort-E-Mails. Dabei wurden die
  Datenbank-Zugriffsrechte ausdrücklich festgeschrieben (bisher galten
  sie nur stillschweigend). Das macht kommende Updates sicherer.

## [0.23.0] – 2026-07-22

### Neu

- **Die Verwalter-Konsole.** Eine Person je Gruppe — die, die sich um
  die Verwaltung kümmert — kann sich über den Login-Bildschirm ein
  eigenes Verwalter-Konto mit ihrer E-Mail-Adresse anlegen und mit der
  Gruppe verknüpfen. Damit gehen zwei Dinge, die bisher niemand konnte:
  das **Gruppenpasswort neu setzen**, wenn es verloren ging, und die
  **Gruppe endgültig löschen** (mit doppelter Bestätigung und deutlicher
  Warnung). Für alle anderen ändert sich nichts: Der Gruppen-Login
  bleibt Name + geteiltes Passwort, und die E-Mail des Verwalters
  bekommt niemand aus der Gruppe zu sehen.
- **„Passwort vergessen" für den Verwalter** läuft klassisch per E-Mail
  — Link anklicken, neues Passwort setzen, fertig.

### Verbessert

- **„Passwort ändern" ist aus dem Gruppen-Menü verschwunden.** Das
  Gruppenpasswort setzt jetzt ausschließlich die Verwalter-Konsole neu.
  Vorher konnte jedes Mitglied es ändern und damit versehentlich alle
  aussperren — und niemand hätte es selbst reparieren können.

## [0.22.1] – 2026-07-22

### Behoben

- **Inaktive Personen zählen im Wochenplan nicht mehr mit.** Wer inaktiv
  gestellt ist, konnte über alte Verfügbarkeits-Einträge unsichtbar als
  Kopf mitzählen — falsches Konfetti, und beim Eintragen wäre die Person
  sogar als Mitfahrt gebucht worden, was rückwirkend die Punkte
  verschoben hätte. Auf einem echten Handy gefunden, bevor es passieren
  konnte.
- **„Person anlegen" verdeckt niemanden mehr.** Der Knopf schwebte über
  der Liste und lag genau auf dem untersten Eintrag — jetzt steht er
  unter dem letzten Teilnehmer und scrollt mit.

## [0.22.0] – 2026-07-22

### Neu

- **Die Gesichter leben.** Alle Stimmungs-Gesichter sind jetzt animiert —
  sie blinzeln, nicken, wippen oder zittern, jedes auf seine Art, und das
  Konfetti-Gesicht feiert richtig. Wer im System „Bewegung reduzieren"
  eingestellt hat, sieht weiterhin die ruhigen Gesichter.
- **Der Wochenplan reagiert sofort.** Ein Tipp im Raster wird auf der
  Stelle sichtbar; gespeichert wird im Hintergrund. Klappt das Speichern
  ausnahmsweise nicht, sagt die App Bescheid und stellt den alten Stand
  wieder her.

### Verbessert

- **Das Konfetti feiert das vollste Auto.** Ausgezeichnet wird, wer am
  vollsten Tag der Woche fährt — stehen mehrere gleichauf, bekommen alle
  ihr Konfetti (bisher ging bei Gleichstand niemand mit Titel heim).
- **Der Fahrer-Vorschlag gleicht jetzt auch aus, wie oft jemand fährt.**
  Steht es bei den Punkten fast gleich (bis zu 2 Punkte Unterschied, je
  näher, desto eher), bekommt, wer selten fährt, eher die kleinen Tage
  und, wer oft fährt, die vollen. So nähern sich die Fahranteile an,
  ohne dass die Punkte-Regel kippt — bei größerem Abstand entscheiden
  wie immer allein die Punkte.
- Beim Losfahren im Startbildschirm bäumt sich das Auto ganz kurz auf —
  wie im echten Leben.

## [0.21.0] – 2026-07-22

### Neu

- **RideBuddy fährt jetzt vor.** Beim Öffnen der App kommt das Auto von
  rechts ins Bild, bremst, die Mitfahrer ploppen auf — und los geht's.
  Wer es eilig hat: einmal tippen, und die Animation ist übersprungen.
  Ist im System „Bewegung reduzieren" eingestellt, startet die App wie
  bisher direkt.
- **Der Wochenplan zeigt den Punktestand.** Vor jedem Namen steht jetzt
  die kleine Zahl, um die es geht — so sieht man dem Vorschlag an, warum
  er auf diese Person fällt.

### Verbessert

- **Update-Hinweise auf Deutsch.** Unter „Was ist neu" steht künftig
  dieser Änderungstext hier — nicht mehr die englischen technischen
  Notizen, die dort bisher auftauchten.
- **Der Import-Knopf sagt die ehrliche Zahl.** Wer Personen weglässt oder
  schon eingetragene Tage importiert, sieht schon vor dem Übernehmen, wie
  viele Fahrten wirklich ankommen — nicht mehr, wie viele in der Datei
  stehen.
- Die Erklärung über dem Wochenplan sagt jetzt korrekt: Der Vorschlag
  richtet sich allein nach den Punkten.

## [0.20.0] – 2026-07-21

### Neu

- **Die Anleitung wohnt jetzt in der App.** Im Menü hinter dem
  Personen-Symbol steht „So funktioniert RideBuddy": alle Funktionen auf
  einer Seite, einfach erklärt — von der Punkte-Regel über den Wochenplan
  bis zum Einladen. Mit den echten Symbolen und Gesichtern der App, damit
  ihr wiedererkennt, was gemeint ist. Auch offline da.

## [0.19.0] – 2026-07-21

### Neu

- **Jemanden in die Gruppe einladen.** Im Menü hinter dem Personen-Symbol
  steht jetzt „Jemanden einladen". RideBuddy baut daraus eine fertige
  Nachricht mit dem Link zur App und eurem Zugangsnamen — auf dem Handy geht
  sie ins Teilen-Menü, im Browser in die Zwischenablage.
- **Das Passwort ist freiwillig.** Ihr könnt es in die Nachricht aufnehmen,
  dann ist die Einladung ein Schritt. Lasst ihr das Feld leer, steht in der
  Nachricht, dass ihr das Passwort selbst weitergebt — das ist sicherer,
  denn ein Passwort im Chat bleibt dort dauerhaft stehen, samt Sicherungen
  des Empfängers. Ihr seht die vollständige Nachricht, bevor sie rausgeht.
- Zur Erinnerung, weil die Einladung es sichtbar macht: **Alle in der Gruppe
  teilen sich einen Zugang.** Wer die Einladung bekommt, sieht und ändert
  alles.

## [0.18.0] – 2026-07-21

### Neu

- **Zu alte App-Versionen werden künftig gestoppt.** Wenn eine Änderung an der
  Datenbank eine ältere App unbrauchbar macht, zeigt diese ab jetzt einen
  klaren „Update erforderlich"-Schirm statt Fahrten und Punkte unvollständig
  anzuzeigen. Bisher konnte man den Update-Hinweis wegklicken und danach mit
  einer App weiterarbeiten, die stillschweigend falsche Zahlen zeigt.
- **Ausgesperrt wird niemand.** Der Schirm erscheint nur, wenn es auch
  wirklich ein Update zu installieren gibt — wer schon die neueste Version
  hat, kommt immer in die App. Und wenn RideBuddy gerade kein Netz hat, wird
  ebenfalls nicht gesperrt.
- Für euch ändert sich mit diesem Update erst mal nichts: Die Mindestversion
  steht auf „egal". Sie wird erst dann angehoben, wenn eine Änderung es
  wirklich nötig macht.

## [0.17.0] – 2026-07-21

### Neu

- **Fahrten aus einer CSV übernehmen.** Im Menü hinter dem Personen-Symbol
  steht jetzt „Fahrten importieren (CSV)". Am einfachsten nehmt ihr eine Datei
  aus dem Export — sie hat genau das richtige Format. Gebraucht werden nur
  Datum und wer gefahren bzw. mitgefahren ist; Fahrzeug, Verbrauch und
  Sitzplätze pflegt ihr weiter in der App.
- **Erst wird gezeigt, dann geschrieben.** RideBuddy liest die Datei, sagt
  euch, wie viele Fahrten drinstehen und welche Zeilen nicht stimmen — und
  erst wenn ihr bestätigt, wird etwas übernommen.
- **Ihr entscheidet, wer wer ist.** Bekannte Namen werden automatisch
  zugeordnet. Für jeden unbekannten Namen könnt ihr wählen: neu anlegen, einer
  vorhandenen Person zuordnen (praktisch bei Tippfehlern) oder weglassen. Das
  ist wichtig, weil aus „Bernd" und „Bernnd" sonst zwei Personen würden — und
  das verschiebt rückwirkend die Punkte aller anderen.
- **Nichts wird still verfälscht.** Tage, an denen schon eine Fahrt
  eingetragen ist, bleiben unberührt. Und wer jemanden weglässt, dessen Fahrten
  werden komplett übersprungen statt ohne ihn angelegt — sonst stimmten die
  Punkte der übrigen Mitfahrer an dem Tag nicht mehr.

## [0.16.0] – 2026-07-21

### Neu

- **Sitzplätze je Auto.** Bei jeder Person lässt sich jetzt eintragen, wie
  viele Sitzplätze das Auto hat — **inklusive Fahrer**, also die Zahl aus dem
  Fahrzeugschein, die ihr von eurem Auto kennt. Voreingestellt sind **5**
  (Fahrer + 4), der normale PKW: Damit greifen die folgenden zwei Punkte
  sofort, ohne dass jemand etwas pflegen muss. Wer einen Van oder einen
  Zweisitzer fährt, korrigiert es einmal.
- **Der Wochenplaner schlägt ein Auto vor, in das alle passen.** Können an
  einem Tag vier Leute und hat einer davon nur einen Viersitzer, schlägt
  RideBuddy jemanden mit genug Plätzen vor. Passt niemandes Auto, bleibt es
  beim normalen Vorschlag und der Tag sagt dazu „nur 4 Plätze für 5" — lieber
  ein Hinweis als gar kein Fahrer.
- **Beim Eintragen fällt Überbelegung auf.** Sind mehr Leute ausgewählt als
  Sitzplätze da sind, erscheint ein Hinweis wie „Annas Auto hat 4 Sitzplätze
  — ihr seid 5". Speichern geht trotzdem: Zur Not rückt man zusammen, oder es
  sind zwei Autos gefahren, und beides muss eintragbar bleiben.

## [0.15.0] – 2026-07-21

### Neu

- **1-way in der Wochenplanung.** Zweiter Tap auf eine Zelle heißt jetzt „nur
  eine Richtung", ein dritter nimmt die Zelle wieder zurück — dieselbe Geste
  wie beim Eintragen einer Fahrt. **Wer nur eine Richtung mitfährt, wird an
  dem Tag nicht als Fahrer vorgeschlagen**; ein halber Weg stellt schließlich
  kein Auto. Beim Eintragen landet die 1-way-Fahrt korrekt in den Punkten.
- **„Hajo!" für das vollste Auto.** Wer über die Woche die meisten Leute
  mitnimmt, bekommt im Planer ein Konfetti-Gesicht neben den Namen. Bei
  Gleichstand gibt es keine Auszeichnung — sonst wäre sie beliebig.
- **Eingetragene Tage sind im Planer gesperrt.** Sie stehen blass da und
  lassen sich nicht mehr antippen, damit niemand aus Versehen an einer
  bereits gefahrenen Fahrt dreht. Statt „Eintragen" steht dort jetzt
  „Bearbeiten" — anders eingefärbt und direkt in der Fahrt, kein Suchen in
  der Historie.
- **Eine eingetragene Fahrt zu ändern fragt nach.** Änderungen verschieben
  die Punkte aller Beteiligten rückwirkend; das soll kein Tipper auslösen.
- **Für die Zukunft lässt sich nichts mehr eintragen.** Der Kalender endet
  bei heute, und aus dem Schnellwahl-Knopf „Morgen" ist „Gestern" geworden —
  Nachtragen ist der Fall, der wirklich vorkommt. Vorausgeplant wird im
  Wochenplan; eingetragen wird, was gefahren wurde.

### Geändert

- **Die Gesichter auf der Startseite sind jetzt die eigenen.** Statt der
  grauen Standard-Symbole steht dort das RideBuddy-Smiley-Set: sieben Stufen
  von strahlend grün bis verärgert rot.
- **Das Gesicht zeigt den Fahranteil im Vergleich zur Runde.** Wer von euch
  am seltensten selbst fahren musste, bekommt das glücklichste Gesicht, wer
  am häufigsten fuhr, das traurigste; dazwischen wird gleichmäßig verteilt.
  Fahrt alle gleich viel, bleiben alle Gesichter neutral.
- **Der Fahranteil steht wieder als Prozentzahl in der Zeile.** Dafür ist die
  Angabe „Ø 1,5 mit" daraus verschwunden — wie voll euer Auto ist, sagen
  weiterhin die Titel „Volle Kischt" und „Fast alloi".

### Behoben

- **Zwei Gruppen konnten sich in der Wochenplanung gegenseitig blockieren.**
  Hatte eine Gruppe an einem Tag den Fahrer von Hand gesetzt, schlug dieselbe
  Aktion bei jeder anderen Gruppe an genau diesem Tag mit einer Fehlermeldung
  fehl. Grund war ein Schlüssel in der Datenbank, der die Gruppe nicht
  mitgezählt hat. Betroffen war nur das Übersteuern des Fahrers; eingetragene
  Fahrten und Punkte waren nie in Gefahr.

## [0.14.0] – 2026-07-21

### Geändert

- **Wer dran ist, entscheiden ab jetzt allein die Punkte.** Bisher zählte
  zusätzlich der Fahranteil — also wie oft jemand im Verhältnis zu seinen
  Anwesenheitstagen selbst gefahren ist. Das ist raus: Die Reihenfolge auf
  der Startseite und der Fahrer-Vorschlag richten sich nur noch danach, wer
  im Punktestand am weitesten hinten liegt.
- **Was das für euch bedeutet.** Wer selten fährt, dann aber mit vollem Auto,
  sammelt schnell Punkte und kommt dadurch seltener an die Reihe als vorher.
  Wer oft mit ein bis zwei Mitfahrern fährt, kommt öfter dran. Das ist so
  gewollt — falls es sich im Alltag schief anfühlt, sagt Bescheid, es lässt
  sich ohne Umbau zurückstellen.

### Neu

- **Der Fahranteil steht jetzt als Gesicht neben dem Namen.** Wer im
  Vergleich zur Gruppe wenig fahren musste, bekommt ein zufriedenes Gesicht,
  wer viel gefahren ist, ein unzufriedenes. Verglichen wird immer mit eurem
  eigenen Schnitt — in einer Fünfergruppe sind 20 % genau der eigene Teil,
  zu zweit wären dieselben 20 % auffällig wenig.

## [0.13.0] – 2026-07-21

### Neu

- **Fahrten als CSV exportieren.** Im Menü hinter dem Personen-Symbol steht
  jetzt „Fahrten exportieren (CSV)". Auf dem Handy landet die Datei im
  Teilen-Menü — ihr könnt sie also direkt in Drive legen, per Mail schicken
  oder speichern; im Browser wird sie heruntergeladen.
- **Damit habt ihr endlich eine eigene Sicherung.** Bisher lagen alle
  eingetragenen Fahrten ausschließlich auf dem Server. Der Export ist die
  erste Kopie, die euch selbst gehört — legt sie ab und zu irgendwo ab.
- **Die Datei öffnet sich in Excel ohne Gefummel.** Semikolon als Trenner und
  richtige Umlaute, also ein Doppelklick statt eines Import-Assistenten.
  Aufgebaut ist sie wie die alte Tabelle: eine Zeile je Fahrt, eine Spalte je
  Person, darin „Fahrer", „Mit" oder „Einfach".
- **Sie ist zugleich die Vorlage für den späteren Import.** Wer noch keine
  Fahrten hat, bekommt die leere Tabelle mit allen Personen-Spalten. Das
  Einlesen einer solchen Datei kommt in einem eigenen Schritt — dann mit
  Rückfrage, bevor neue Personen angelegt werden.

## [0.12.1] – 2026-07-20

### Geändert

- **Nichts, was ihr seht.** Diese Version schärft nur die automatischen
  Prüfungen, mit denen der Code vor jeder Veröffentlichung kontrolliert wird —
  etwa darauf, dass kein Ergebnis einer Speicheraktion versehentlich ignoriert
  wird. Sie soll Fehler abfangen, bevor sie bei euch ankommen.

## [0.12.0] – 2026-07-20

### Neu

- **Wochenplaner.** Der neue Tab „Woche" zeigt Montag bis Freitag als Raster:
  jede Person eine Zeile, jeder Tag eine Spalte. Tippt an, wann ihr könnt —
  daraufhin schlägt RideBuddy für jeden Tag einen Fahrer vor.
- **Der Vorschlag denkt die ganze Woche mit.** Er rechnet jeden Tag gegen die
  Vortage der Woche, nicht nur gegen die bisherige Statistik. Sonst stünde an
  allen fünf Tagen derselbe Name, weil sich die Punkte erst ändern, wenn eine
  Fahrt tatsächlich eingetragen ist.
- **Ändern geht immer.** Über das Tausch-Symbol wählt ihr einen anderen
  Fahrer; die Zeile schreibt dann „von Hand gesetzt" statt „Vorschlag", und
  ein Tipp bringt euch zum Vorschlag zurück.
- **Eingetragen wird frühestens am Fahrtag.** Vorher steht nicht fest, wer
  wirklich mitfährt — und eine im Voraus eingetragene Fahrt würde die Punkte
  aller anderen für etwas verschieben, das noch gar nicht passiert ist. Bis
  dahin ist der Plan nur ein Plan und taucht in keiner Auswertung auf.

## [0.11.1] – 2026-07-20

### Neu

- **Fehlerprotokoll an eine Rückmeldung anhängen.** Meldet ihr einen Fehler,
  könnt ihr die letzten technischen Meldungen der App mitschicken — das sagt
  meist mehr darüber, was schiefging, als sich beschreiben lässt. Der Haken
  ist standardmäßig aus, und was mitgehen würde, steht vorher im Klartext im
  Dialog: Die Rückmeldung wird ein öffentlicher Eintrag im GitHub-Projekt,
  also sollt ihr vorher sehen können, was ihr da absendet. Die Meldungen
  liegen nur im Arbeitsspeicher und verschwinden beim Schließen der App.

## [0.11.0] – 2026-07-20

### Geändert

- **„Wer ist dran" sagt jetzt, in welche Richtung die Zahlen zeigen.** Statt
  „2,5 Punkte" steht dort „schuldet 2,5" beziehungsweise „hat 2,5 gut" — die
  Punkte sind ausgeglichen über die Gruppe, negativ heißt also, dass euch
  noch Fahrten zustehen. Das war vorher genau andersherum zu lesen, als es
  gemeint ist.
- **Neu daneben: Ø Mitfahrer je eigener Fahrt.** Die Zahl erklärt die
  Rangliste. Der Aufwand ist pro Fahrt für alle gleich, die Punkte sind es
  nicht: Wer immer drei Leute mitnimmt, sammelt dreimal so schnell wie
  jemand, der meist zu zweit unterwegs ist.
- **Zwei Auffälligkeiten werden benannt:** „Volle Kischt" für den, der
  regelmäßig das vollste Auto fährt, und „Fast alloi" für den, der meist mit
  einem Mitfahrer unterwegs ist. Beides erscheint erst ab drei eigenen
  Fahrten und nur, wenn sich die Gruppe darin wirklich unterscheidet — sonst
  wäre es Dekoration statt Aussage.

## [0.10.1] – 2026-07-20

### Behoben

- **Die Anmeldung wandert nicht mehr ins Google-Backup.** Android sichert die
  App-Daten standardmäßig ins Konto des Geräts und spielt sie auf einem neuen
  Handy wieder ein — bisher inklusive der gespeicherten Anmeldung. Da eine
  Gruppe genau einen Zugang teilt, ist das der Schlüssel zur ganzen Gruppe.
  Er bleibt jetzt auf dem Gerät. Für euch ändert sich nichts, außer dass ihr
  euch auf einem neu eingerichteten Handy einmal neu anmeldet.

## [0.10.0] – 2026-07-20

### Neu

- **Mitfahrer lassen sich jetzt in der App anlegen.** Über „Personen
  verwalten" im Konto-Menü kommt man zur Personenliste: neue Person anlegen,
  Fahrzeug, Antrieb und Verbrauch nachtragen (Letzteres braucht die App, um
  die Ersparnis zu berechnen) und Namen korrigieren. Bisher ging das nur
  direkt in der Datenbank.
- **Wer nicht mehr mitfährt, wird stillgelegt statt gelöscht.** Ein Schalter
  je Person nimmt sie aus „Wer ist dran" und aus der Auswahl beim Eintragen,
  lässt die gefahrenen Fahrten aber unangetastet. Löschen gibt es bewusst
  nicht: Es würde die vergangenen Teilnahmen mitreißen und damit die Punkte
  aller anderen rückwirkend verändern.
- **Beim Eintragen stehen die Stammgäste oben.** Wer in den letzten 60 Tagen
  dabei war, erscheint zuerst; alle anderen rutschen unter eine Zwischen-
  überschrift „Länger nicht dabei". In gewachsenen Gruppen muss man die
  täglichen Mitfahrer damit nicht mehr aus einer langen alphabetischen Liste
  heraussuchen.

## [0.9.0] – 2026-07-20

### Neu

- **Die verwendeten Open-Source-Lizenzen stehen jetzt in der App.** Im
  Konto-Menü oben rechts führt „Open-Source-Lizenzen" zu einer Übersicht aller
  Bausteine, auf denen RideBuddy aufbaut — samt der Lizenztexte der beiden
  Schriften Space Grotesk und Manrope, deren Lizenz genau das verlangt. Der
  Eintrag ist auch ohne Anmeldung erreichbar.

## [0.8.0] – 2026-07-20

### Behoben

- **Der Download im Update-Hinweis funktioniert wieder.** Bisher passierte
  beim Tippen auf „Herunterladen" nichts: Die App durfte seit Android 11 gar
  keinen Browser ansprechen, und der stille Fehlschlag wurde nirgends
  angezeigt. Betroffen war jede Android-Installation.

### Neu

- **Updates laden und installieren direkt in der App.** Statt in den Browser
  zu wechseln, lädt RideBuddy die neue Version selbst — mit Fortschritts-
  anzeige — und übergibt sie anschließend an die Android-Installation. Eure
  Daten bleiben dabei erhalten. Beim allerersten Mal fragt Android einmalig,
  ob RideBuddy Apps installieren darf; das muss einmal bestätigt werden.
- Klappt der direkte Weg nicht, bietet der Dialog weiterhin den Umweg über
  den Browser an — diesmal mit sichtbarer Rückmeldung statt stillem Nichts.

## [0.7.0] – 2026-07-20

### Neu

- **Auswertungen auf der Startseite.** Unter „Wer ist dran?" stehen jetzt drei
  Blöcke:
  - **Gemeinsam erreicht** — zurückgelegte Personen-Kilometer, gesparter
    Kraftstoff und die Zahl der Fahrten auf einen Blick.
  - **Fahrten pro Monat** — die letzten zwölf Monate als Säulen. Ruhige
    Monate bleiben sichtbar, damit die Achse nicht mehr Betrieb vortäuscht,
    als tatsächlich war. Beschriftet sind der stärkste und der laufende Monat.
  - **Wie ihr unterwegs seid** — je Person ein Balken, aufgeteilt nach
    gefahren, 1-way und mitgefahren. Die Länge zeigt, wie oft jemand dabei
    war, die Aufteilung wie. Es sind dieselben Farben wie in der
    Fahrt-Erfassung.

  Solange keine Fahrten erfasst sind, erscheinen die beiden Diagramme nicht —
  eine leere Achse sagt weniger als gar keine Karte.

## [0.6.1] – 2026-07-20

### Behoben

- **Der Login in der Android-App funktioniert wieder.** Der App fehlte die
  Berechtigung, überhaupt ins Internet zu gehen — sie konnte den Server
  deshalb nie erreichen, und jeder Anmeldeversuch endete mit „Name oder
  Passwort falsch", auch wenn beides stimmte. Im Browser war davon nichts
  zu merken. Betroffen waren alle bisherigen Android-Installationen.

## [0.6.0] – 2026-07-20

### Neu

- **Die App heißt jetzt RideBuddy** und hat ein eigenes Gesicht: Logo,
  Farben (Cyan/Teal mit Eco-Grün) und die Schriften Space Grotesk und
  Manrope — nach dem Design-Set „RideBuddy Design Set".
- **Neue App-Icons** für Web und Android, inklusive Adaptive Icon mit
  Markenverlauf und Favicon.

## [0.5.1] – 2026-07-20

### Behoben

- **Die Android-App wird jetzt mit dem echten Release-Schlüssel signiert.**
  Zuvor griff die Signaturkonfiguration nicht, sodass eine Testsignatur
  verwendet worden wäre — damit hätte sich die App später nicht mehr
  aktualisieren lassen.

## [0.5.0] – 2026-07-20

### Neu

- **Hinweis auf neue Versionen**: Erscheint eine neuere Version, zeigt die
  Übersicht ein Banner — im Web mit „Neu laden", auf Android mit Download.
- **Rückmeldung aus der App**: Wunsch oder Fehler melden, direkt über das
  Banner oder dauerhaft über das Konto-Menü.
- **Android-App**: Die App wird jetzt auch als Android-Paket gebaut.

### Behoben

- **Abstürze beim Öffnen der Fahrt-Maske**: Die Daten wurden bei jedem
  Anmelde-Ereignis neu geladen und konnten sich dabei mitten im Bildaufbau
  verheddern. Aufgefallen durch die neuen Ablauf-Tests.

## [0.4.1] – 2026-07-20

### Behoben

- **Passwort-Manager funktionieren jetzt** bei Anmeldung, Gruppen-Anfrage und
  Passwort-Ändern. Die Felder waren zwar benannt, lagen aber nicht in einer
  zusammengehörigen Anmeldemaske, und nach dem Login fehlte das Signal zum
  Speichern – dadurch bot kein Manager das Ausfüllen oder Sichern an.

## [0.4.0] – 2026-07-19

### Neu

- **Passwort ändern in der App**: Konto-Menü auf der Startseite mit
  „Passwort ändern" (und Abmelden). Läuft über die eigene Sitzung, jede
  Gruppe verwaltet ihr Passwort selbst – kein Admin-Zugriff nötig.

## [0.3.1] – 2026-07-19

### Geändert

- Login akzeptiert jetzt **Gruppenname oder vollständige E-Mail**, damit
  bestehende Zugänge mit echter Adresse weiter funktionieren.
- Interne Login-Domain auf eine reguläre TLD umgestellt
  (`grp.fahrgemeinschaft.app`), damit sie jede Adressprüfung besteht.

## [0.3.0] – 2026-07-19

### Neu

- **Mehrere Gruppen (Mandantenfähigkeit)**: Eine Gruppe = ein Zugang, jede
  Gruppe sieht ausschließlich ihre eigenen Daten. Durchgesetzt in der
  Datenbank (Row Level Security), nicht nur in der Oberfläche.
- **Selbst-Registrierung mit Freigabe**: „Neue Gruppe anfragen" legt eine
  Gruppe im Status *pending* an; sie sieht bis zur Freigabe keine Daten.
- **Admin-Bereich** zum Freigeben oder Ablehnen offener Anfragen.
- Anmeldung mit **Gruppenname statt E-Mail**.

### Geändert

- Bestehende Daten wurden ohne Verlust in eine aktive Gruppe überführt.

## [0.2.1] – 2026-07-19

### Behoben

- **Excel-Import**: Teilnahmen wurden über das Datum zugeordnet. Da an
  einem Tag mehrere Fahrten möglich sind, fielen Zwei-Auto-Tage auf
  dieselbe Fahrt zusammen. Die Zuordnung erfolgt jetzt über die
  Einfüge-Reihenfolge.

## [0.2.0] – 2026-07-19

### Behoben

- **Mehrere Fahrten pro Tag** sind jetzt möglich. Bisher erzwang die
  Datenbank eine Fahrt je Kalendertag – die Gruppe fährt an manchen Tagen
  aber in zwei getrennten Autos.

### Geändert

- Ein zweiter Eintrag am selben Tag wird nicht mehr blockiert, sondern nur
  noch mit einer Rückfrage bestätigt.

## [0.1.0] – 2026-07-19

### Neu

- Erste Version: Fahrtenprotokoll, Punktesystem (ein Punkt je Mitfahrer,
  0,5 für 1-way) und Fahrer-Vorschlag über einen kombinierten
  Fairness-Rang aus Punkten und Fahranteil.
- **Fahrt-Erfassung über Kacheln** mit automatisch gesetztem Fahrer,
  Vortags-Eintrag für die Planung.
- **Historie** mit Bearbeiten und Löschen, **Statistik** mit Kilometern,
  gesparten Kraftstoffkosten und „Kilometerheld".
- Supabase-Backend, Auslieferung als PWA über GitHub Pages; Demo-Modus mit
  Beispieldaten, solange kein Backend hinterlegt ist.
- Einmal-Import der bisherigen Excel-Historie; die berechneten Punkte
  stimmen exakt mit der Tabelle überein (durch Tests abgesichert).

[0.12.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.12.1
[0.12.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.12.0
[0.11.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.11.1
[0.11.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.11.0
[0.10.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.10.1
[0.10.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.10.0
[0.9.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.9.0
[0.8.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.8.0
[0.7.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.7.0
[0.6.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.6.1
[0.6.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.6.0
[0.5.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.5.1
[0.5.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.5.0
[0.4.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.4.1
[0.4.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.4.0
[0.3.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.3.1
[0.3.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.3.0
[0.2.1]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.2.1
[0.2.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.2.0
[0.1.0]: https://github.com/MacBuchi/Fahrgemeinschaft/releases/tag/v0.1.0

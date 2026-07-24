# Changelog

Alle nennenswerten Änderungen an diesem Projekt. Versionsschema:
`MAJOR.MINOR.PATCH`, gepflegt in `pubspec.yaml`; jeder Versions-Bump auf
`main` erzeugt automatisch Tag, GitHub-Release und den Web-Deploy.

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

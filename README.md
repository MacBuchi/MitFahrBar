# Fahrgemeinschaft

Web-App zur Verwaltung einer Fahrgemeinschaft: Fahrten dokumentieren, Punkte
zählen und auf einen Blick sehen, **wer als Nächstes fahren sollte**.
Mehrere Gruppen können die App unabhängig voneinander nutzen.

**➡️ App öffnen: <https://macbuchi.github.io/Fahrgemeinschaft/>**

Auf dem Handy lässt sie sich über „Zum Home-Bildschirm hinzufügen" wie eine
normale App installieren (PWA).

## Was die App macht

- **Fahrten dokumentieren** – pro Fahrtag: wer ist gefahren, wer mitgefahren,
  wer nur eine Strecke (1-way). Mehrere Autos am selben Tag sind möglich.
- **Punkte & Fairness** – die App rechnet aus, wer wie viel getragen hat, und
  schlägt den nächsten Fahrer vor.
- **Statistik** – gefahrene Kilometer, gesparte Kraftstoffkosten,
  „Kilometerheld".
- **Dokumentation, kein Chat** – die Absprache bleibt in WhatsApp, die App
  hält fest, was tatsächlich gefahren wurde.

## Bedienung

### Anmelden

Anmeldung mit **Gruppenname + gemeinsamem Passwort**. Der Zugang gilt für die
ganze Gruppe – jeder kann für jeden eintragen.

### Fahrt eintragen (der 10-Sekunden-Weg)

1. Auf **„Fahrt eintragen"** tippen. Datum steht auf *heute*, **morgen** ist
   ein Tap entfernt (für die Planung am Vorabend).
2. **Teilnehmer-Kacheln antippen**: 1× = dabei, 2× = nur eine Strecke
   (1-way), 3× = wieder abgewählt.
3. Die App setzt **automatisch den Fahrer** (wer laut Fairness-Rang dran ist)
   und zeigt ihn oben. Passt es nicht, eine andere Kachel auf das Fahrer-Feld
   ziehen.
4. Speichern – die Punkte aktualisieren sich sofort.

### Wer ist dran?

Die Startseite sortiert die aktiven Fahrer nach einem **kombinierten
Fairness-Rang** aus zwei Kennzahlen:

- **Punkte** = mitgenommene Personen − eigene Mitfahrten − 0,5 × eigene
  1-way-Fahrten. Wenig Punkte = viel „Schuld".
- **Fahranteil** = eigene Fahrten ÷ eigene Teilnahmetage. Wer selten fährt,
  rückt nach vorn.

Beides zusammen verhindert, dass jemand, der immer viele Leute mitnimmt, an
kleinen Tagen nie drankommt. Bei Gleichstand fährt, wessen letzte Fahrt am
längsten her ist. Die App **schlägt vor – entschieden wird von Menschen**.

### Passwort ändern

Startseite → Konto-Symbol oben rechts → **Passwort ändern**. Achtung: Es gilt
für den ganzen Gruppen-Zugang, danach brauchen es alle neu.

## Eigene Gruppe anlegen

1. Auf dem Anmelde-Bildschirm **„Neue Gruppe anfragen"** wählen.
2. Gruppenname, kurzen Anmeldenamen und ein gemeinsames Passwort festlegen.
   Eine E-Mail-Adresse wird nicht gebraucht.
3. Die Anfrage wird geprüft. Nach der **Freigabe** meldet ihr euch mit
   Anmeldename + Passwort an und legt eure eigenen Personen und Fahrten an –
   vollständig getrennt von anderen Gruppen.

## Entwicklung

Flutter Web (PWA) mit Riverpod, go_router und Material 3; Backend ist Supabase
(PostgreSQL + Auth, Zugriffsschutz über Row Level Security). Details zu
Konzept und Fachlogik: [KONZEPT.md](KONZEPT.md), Arbeitsregeln:
[CLAUDE.md](CLAUDE.md), Änderungen: [CHANGELOG.md](CHANGELOG.md).

```bash
flutter pub get
flutter run -d chrome     # ohne Supabase-Konfiguration: Demo-Modus
flutter analyze && flutter test
```

Ohne hinterlegtes Supabase-Projekt (`lib/core/supabase_config.dart`) startet
die App in einem **Demo-Modus** mit Beispieldaten – praktisch zum Ausprobieren
ohne Backend.

Datenbank-Schema und Migrationen liegen unter [supabase/](supabase/) und
werden bei Push auf `main` automatisch eingespielt. Ein Release entsteht durch
Erhöhen von `version:` in `pubspec.yaml`.

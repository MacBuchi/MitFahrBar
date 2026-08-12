# Play Console — Ausfüllhilfe und offene Blocker

Vorlage für das **Data-Safety-Formular** und das **Store-Listing**, abgeleitet
aus `supabase/schema.sql`, `android/app/src/main/AndroidManifest.xml` und den
tatsächlich aufgerufenen Endpunkten — nicht aus einer Vorlage.

> **Warum das hier steht und nicht nur in der Konsole:** Google lehnt ab, wenn
> Formular und Binary auseinanderlaufen. Ändert sich, was die App erhebt oder
> wohin sie verbindet, gehört diese Datei in denselben PR — dann sieht man beim
> Review, dass die Konsole nachzuziehen ist. Dasselbe Verfahren fährt PilzBuddy
> (`docs/play-console.md` dort).

Stand: 12. August 2026, App-Version 0.80.1+110.

**MitFahrBar ist noch NICHT einreichbar.** Die Blocker stehen ganz unten —
sie sind der eigentliche Inhalt dieser Datei. Der Data-Safety-Teil ist die
Vorarbeit, die unabhängig davon gilt.

---

## 1. Datensicherheit (Data safety)

### Vorfragen

| Frage | Antwort | Begründung |
|---|---|---|
| Erhebt oder teilt deine App die geforderten Nutzerdatentypen? | **Ja** | Namen, Fahrten, Feedback, Fehlerberichte, Push-Token |
| Werden alle Daten bei der Übertragung verschlüsselt? | **Ja** | Alle Endpunkte sind HTTPS: Supabase, `github.com`, `api.github.com`, `macbuchi.github.io`. Kein `http://` im Code. Auth-Mails verschickt Supabase serverseitig über Brevo — die App spricht nie mit dem Mail-Anbieter |
| Können Nutzer die Löschung ihrer Daten beantragen? | **Ja, aber URL fehlt** | Verwalter löschen ihre Gruppe über `admin_delete_group` in der Konsole (Kaskade über den Auth-User). Eine **öffentliche URL ohne installierte App** verlangt Play zusätzlich — siehe Blocker 4 |
| Unabhängige Sicherheitsüberprüfung? | **Nein** | |
| Enthält die App Werbung? | **Nein** | Keine Werbe- oder Analyse-SDKs in `pubspec.yaml` |

### Datentypen

| Datentyp | Erhoben | Geteilt | Pflicht? | Zweck | Woher |
|---|---|---|---|---|---|
| **Persönliche Infos → Name** | Ja | Nein | Erforderlich | App-Funktionalität | `persons.name` — die Mitglieder einer Fahrgemeinschaft, eingetragen von der Gruppe selbst |
| **Persönliche Infos → E-Mail-Adresse** | Ja | Nein¹ | Erforderlich | Kontoverwaltung | Nur **Verwalter-Konten** haben eine echte Adresse. Der Gruppen-Login ist `handle@grp.fahrgemeinschaft.app` — eine synthetische Adresse, kein Postfach |
| **App-Aktivität → Andere nutzergenerierte Inhalte** | Ja | **Ja²** | Optional | App-Funktionalität, Entwicklerkommunikation | Anmerkungen am Plantag (`plan_notes`) und Feedback-Text (`feedback`) |
| **App-Info und -Leistung → Absturzprotokolle** | Ja | Nein | Erforderlich | App-Funktionalität | `error_reports` |
| **Geräte- oder andere IDs** | Ja³ | **Ja³** | Optional | App-Funktionalität | `push_devices.token` — die FCM-Gerätekennung, sobald jemand Benachrichtigungen einschaltet |

**Ausdrücklich NICHT erhoben** — im Formular alles andere leer lassen:
**Standort in keiner Form** (die App deklariert keine Standort-Berechtigung
und hat keinen Kartencode), Fotos/Videos, Audio, Kontakte, Kalender,
Finanzdaten, Gesundheits-/Fitnessdaten, SMS/E-Mail-Inhalte,
Web-Browsing-Verlauf, installierte Apps. **Keine Advertising-ID.**

Die Fahrtdaten (`trips`, `trip_participations`) sind bewusst **keine**
Standortdaten: Gespeichert wird das Datum, wer mitgefahren ist und die
Kilometerzahl des Arbeitswegs als Parameter — nie eine Koordinate, nie eine
Route. Die Spritpreise (`price_week`) sind Wochenwerte einer Region, kein
Bewegungsprofil.

**Kurzzeitige Verarbeitung („processed ephemerally"):** bei allen Typen
**nein** — alles wird in PostgreSQL gespeichert.

### Die drei Ermessensfragen

**¹ Die Verwalter-Adresse.** Nicht *geteilt*: Sie liegt in Supabase Auth, und
Brevo stellt als Auftragsverarbeiter die Bestätigungs- und Reset-Mails zu,
die der Nutzer selbst angestoßen hat. Google nimmt Dienstanbieter, die nur im
Auftrag und für diesen Zweck verarbeiten, ausdrücklich von *geteilt* aus. Das
setzt voraus, dass Brevo in der Datenschutzerklärung als Auftragsverarbeiter
benannt ist — die gibt es noch nicht, siehe Blocker 3.

**² Feedback landet öffentlich auf GitHub — *geteilt*.** Der Feedback-Bot
(`tool/feedback_bot.py`) macht daraus öffentliche Issues, außerhalb der
Kontrolle des Nutzers und unwiderruflich. Das ist eine Weitergabe an einen
Dritten, auch wenn der Nutzer sie auslöst. **Verschärfend:** Der Dialog kann
auf Wunsch die letzten 50 Log-Zeilen anhängen (`logRing`) — deshalb steht in
CLAUDE.md die Regel, dass niemals Personennamen, Handles oder Fahrtdaten ins
Log gehören. Der Anhang ist standardmäßig abgewählt und wird vor dem Senden
im Klartext angezeigt. Untertreiben ist hier das teurere Risiko: **ja, als
geteilt deklarieren.**

**³ Das FCM-Token — erhoben UND geteilt.** Ein FCM-Token ist eine
Gerätekennung, es entsteht bei Google, und ohne Weitergabe an Google kann
keine Meldung zugestellt werden — das ist der Zweck, kein Nebeneffekt. Die
Auftragsverarbeiter-Ausnahme trägt hier nicht, weil Google die Kennung selbst
erzeugt. Was die Einordnung trägt: **Optional** (Benachrichtigungen sind ab
Werk aus, ein Schalter im Screen, Ausschalten löscht die Zeile in
`push_devices`).

**Achtung, anders als bei PilzBuddy:** Der Push-Text nennt **Personennamen**
(„Morgen fährt Anna"). Er ist damit inhaltlich sensibler als PilzBuddys
Meldungen, die bewusst nie Koordinaten oder Spot-Namen tragen. Das gehört in
die Datenschutzerklärung, wenn sie geschrieben wird.

### Berechtigungen im Build

| Berechtigung | Wofür | Woher |
|---|---|---|
| `INTERNET` | Supabase, Update-Check | Manifest |
| `POST_NOTIFICATIONS` | Abend-Blick und Abfahrts-Erinnerung | Manifest |
| `REQUEST_INSTALL_PACKAGES` | In-App-Update aus dem GitHub-Release | Manifest — **darf nicht ins AAB**, siehe Blocker 1 |
| `INSTALL_PACKAGES` | — | **`ota_update`**, siehe Blocker 1 |
| `READ_EXTERNAL_STORAGE` | — | **`ota_update`** |
| `WRITE_EXTERNAL_STORAGE` | — | **`ota_update`** |
| `RECEIVE_BOOT_COMPLETED` | — | **`ota_update`** |
| `com.google.android.c2dm.permission.RECEIVE` | Push entgegennehmen | `firebase_messaging` |

---

## 2. Offene Blocker — in dieser Reihenfolge

### Blocker 1: `ota_update` vergiftet das Manifest

**Das ist der große, und er ist nicht mit einem Flavor allein zu lösen.**

Play verbietet Selbst-Updates („Device and Network Abuse"). PilzBuddy hat
genau dieses Problem bereits durchgearbeitet und kam zu einem eindeutigen
Befund (dort #88/#161, in dessen CLAUDE.md festgehalten): Das Plugin-Manifest
von `ota_update` zieht **`INSTALL_PACKAGES`**, `READ/WRITE_EXTERNAL_STORAGE`
und `RECEIVE_BOOT_COMPLETED` in **jeden** Build — 14 Berechtigungen statt 8.

`INSTALL_PACKAGES` ist eine **Signatur-Berechtigung**, die eine normale App
nie bekommen kann. Sie im Manifest zu führen ist in jeder Review ein roter
Punkt, und zwar unabhängig davon, ob die App sie benutzt.

Zwei Wege:

- **PilzBuddys Weg (empfohlen):** `ota_update` fliegt raus, der Updater wird
  von Hand nachgebaut — APK laden, an Androids System-Installer übergeben
  (`FileProvider`, MethodChannel). Kostet **genau eine** Berechtigung:
  `REQUEST_INSTALL_PACKAGES`. Der Code dafür existiert in PilzBuddy
  (`lib/features/update/update_installer.dart` + `MainActivity.kt`) und ist
  portierbar. Danach greift dieselbe Flavor-Trennung wie dort.
- **Der schnelle Weg:** alle vier Berechtigungen im `play`-Flavor per
  `tools:node="remove"` entfernen. Das geht, ist aber brüchig — der
  Plugin-Code läuft dann ohne die Berechtigungen, die er deklariert hat, und
  ein Plugin-Update kann jederzeit neue nachschieben, ohne dass es auffällt.

### Blocker 2: Kein Schalter, der den Update-Weg abschaltet

PilzBuddy hat `AppDistribution.showsUpdateHints`
(`--dart-define=PLAY_BUILD=true`): Im Play-Build kein Update-Check, kein
Banner, kein Dialog. MitFahrBar hat **nichts dergleichen** — der Updater
hängt direkt in `lib/features/banners/app_banners.dart`.

Ohne diesen Schalter zeigte der Store-Build Nutzern einen Hinweis auf einen
APK-Download, und das ist in Play unzulässig. Der Schalter gehört in den
Provider und nicht nur in die Oberfläche, sonst lässt er sich im Play-Build
umlegen (dieselbe Lehre wie beim Vorabversionen-Schalter, #225).

### Blocker 3: Keine Datenschutzerklärung

`web/` enthält nur das PWA-Gerüst (`index.html`, Service Worker, Icons) —
keine Inhaltsseiten. Eine Datenschutzerklärung unter einer öffentlich
erreichbaren URL ist für **jede** App in Play Pflicht — sie muss
mindestens benennen: Supabase als Hoster, Brevo als Mail-Auftragsverarbeiter,
Google/FCM als Empfänger der Gerätekennung und GitHub als Ziel des Feedbacks
(öffentlich!). PilzBuddys `web/datenschutz.html` ist die Vorlage.

### Blocker 4: Keine Konto-Löschseite

Play verlangt bei Apps mit Kontoanlage eine **URL ohne installierte App**,
über die sich die Löschung anstoßen lässt. `admin_delete_group` existiert und
löscht sauber über die Kaskade am Auth-User — es fehlt nur die öffentliche
Seite. PilzBuddys `web/konto-loeschen.html` ist die Vorlage.

### Blocker 5: Kein AAB-Build, keine Flavors

`release.yml` baut nur eine APK (`flutter build apk --release`). Es fehlt der
`appbundle`-Schritt samt Flavor-Trennung. **Bewusst noch nicht gebaut:** Ein
AAB, das die Berechtigungen aus Blocker 1 trägt, ist nicht einreichbar — der
Job entstünde also nur, um ein Artefakt zu erzeugen, das niemand hochladen
darf. Er gehört in denselben PR wie Blocker 1.

Wenn er kommt, gilt PilzBuddys Muster (dort seit 1.87.1): Flavors `github`
und `play` mit **identischer `applicationId`** (kein `applicationIdSuffix` —
sonst sieht Android zwei Apps), `--flavor` an jedem Build-Aufruf, und die
Ausgabepfade tragen den Flavor-Namen. Ein `cp` auf den alten, flavorlosen
Namen bricht erst **nach** dem Taggen ab; MitFahrBar kennt diesen Ausfall
schon (v0.34.1, Tag ohne Release, nur von Hand heilbar). Ein
Regressionstest nach dem Muster von `test/release_workflow_test.dart` hält
Aufruf und Pfad zusammen.

### Blocker 6: Keine Store-Grafiken

Es gibt kein `store/`-Verzeichnis. Play verlangt: App-Icon 512×512 (32 Bit
PNG), Feature-Grafik 1024×500, mindestens zwei Screenshots. Die
README-Screenshots aus `doc/screenshots/` entstehen im 430×900-Viewport und
haben nicht das geforderte Format — sie sind kein Ersatz, aber
`tool/screenshots.sh` ist der Weg, passende zu erzeugen.

---

## 3. Play App Signing

Beim ersten AAB-Upload wird der Keystore aus den Actions-Secrets zum
*Upload-Key*, signiert wird danach von Google. Der Play-Build hat damit eine
**andere Signatur** als die GitHub-APK: Wer die APK installiert hat, muss zum
Wechsel einmal deinstallieren, sonst scheitert die Installation wortlos mit
„App nicht installiert". Das gehört in die Tester-Einladung.

Verloren geht dabei nichts Wichtiges — Gruppendaten liegen in Supabase. Weg
sind die gerätelokalen Einstellungen (die Zuordnung „Ich bin" aus #121 und
der Vorabversionen-Schalter aus #225); die Backup-Regeln schließen
`FlutterSharedPreferences.xml` ohnehin als ganze Datei aus.

Fingerprint des **Upload-Keys** (aus jeder veröffentlichten APK ablesbar,
also kein Geheimnis):

```
SHA-1    BE:56:07:4D:2E:D9:E8:E0:D1:11:37:FF:CF:2B:F1:3C:1B:6D:71:7C
SHA-256  CA:01:75:84:F3:87:8F:A2:CA:A0:AC:00:7F:AB:3C:D9:8E:D5:76:F5:D7:F8:EE:24:EE:F5:EE:02:03:15:EF:50
```

**Nicht** der Wert, der nach dem Upload in Firebase gehört: Die ausgelieferte
App trägt Googles App-Signing-Key, dessen Fingerprint erst die Konsole zeigt
(*Test und Veröffentlichung → Einrichtung → App-Signatur*). Für FCM ist
ohnehin keiner nötig — Push authentifiziert über API-Key und Paketnamen, ein
SHA bräuchte erst Google Sign-In, Maps SDK, Dynamic Links oder App Check.

Nachrechnen ohne Keystore: `keytool -printcert -jarfile` scheitert, weil
Flutter nur v2/v3 signiert (kein JAR-Signaturblock). Es braucht
`apksigner verify --print-certs <apk>` oder den APK-Signing-Block direkt.
Mit Keystore: `keytool -list -v -keystore <datei>`.

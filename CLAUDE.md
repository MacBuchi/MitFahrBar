# RideBuddy (Repo: Fahrgemeinschaft) — Arbeitsregeln

Flutter-Web-App (PWA) + Android-APK zur Verwaltung einer Fahrgemeinschaft:
Fahrtenprotokoll, Punkte-/Fairness-System („wer ist dran"), Statistik,
Dashboard-Charts. Supabase-Backend (multi-tenant, RLS in
`supabase/schema.sql`), Riverpod 2 ohne Codegen, go_router, deutsche
UI-Strings direkt im Code. Fachkonzept: `KONZEPT.md`.

Produktname ist **RideBuddy** (seit v0.6.0); Repo- und Package-Name bleiben
`fahrgemeinschaft`.

Projektübergreifende Guidelines (Architektur, State, Testing, CI, Signing,
In-App-Update/-Feedback) liegen im DocuHub unter
`/Volumes/MacStore/Programming/ProgrammingGuidelineDocuHub/`. Diese Datei
beschreibt, was für RideBuddy davon abweicht oder zusätzlich gilt.

## Bekannte Abweichungen Konzept ↔ Implementierung

`KONZEPT.md` ist an diesen Stellen überholt — bei Widersprüchen gilt der Code:

- Name „FairFahrt" (§9.1) → das Produkt heißt RideBuddy.
- `tool/import_xlsx.dart` (Dart-CLI) → umgesetzt wurde `tool/import_seed.py`.
- Postgres-View `person_stats` (§4) → nie gebaut; alle Kennzahlen entstehen
  clientseitig in `lib/core/fairness.dart`.
- Preis-Historisierung mit „Gültig-ab" (§3.4) → `settings` ist nur
  `(group_id, key) → value`, ohne `valid_from`.
- Offen aus §5.5: Personen und Fahrzeuge pflegt seit v0.10.0
  `features/persons/persons_screen.dart` (`/persons`), ein Screen für die
  **Parameter** (`settings`) fehlt weiterhin — `saveSettings` hat bis heute
  keinen Aufrufer in `lib/`. `admin_screen.dart` ist nur die
  Gruppen-Freigabe, nicht die Datenpflege.

## Architektur-Leitplanken (nicht verhandelbar)

- 3 Schichten: `core/` (router, theme, tokens, fairness, log) · `data/`
  (Repositories + `providers.dart`-Registry) · `models/` · `features/<name>/`.
- Die Fairness-/Punktelogik lebt NUR in `lib/core/fairness.dart` und ist durch
  `test/fairness_test.dart` inkl. Excel-Backtest abgesichert. Änderungen an der
  Formel brauchen angepasste Tests UND einen Abgleich mit `KONZEPT.md` 3.2.
- **Die Reihenfolge entscheiden seit 2026-07-21 allein die Punkte**
  (`points_weight = 1.0`, Issue #38). Der kombinierte Rang aus Punkten und
  Fahranteil steckt weiter in `rankPresent` — nur das Gewicht ist gesetzt.
  Das ist bewusst so gebaut: Zurückdrehen heißt, den Parameter zu ändern,
  nicht die Formel. Wer den Fahranteil-Term „aufräumt", nimmt der Gruppe
  diese Rückfahrkarte; `test/fairness_test.dart` nagelt beide Gewichte fest.
  Der Parameter lebt **pro Gruppe in der DB** — eine Änderung der Dart-
  Vorgabe allein erreicht keine bestehende Gruppe, dafür braucht es eine
  Migration (siehe `20260721090000_points_only_ranking.sql`).
- Kennzahlen (Punkte, Quote, km, Ersparnis) werden immer berechnet, nie
  gespeichert.
- **Personen werden nie gelöscht, nur inaktiv gesetzt.** `person_id` in
  `trip_participations` hängt an `ON DELETE CASCADE` — ein Löschen entfernt
  also stillschweigend alle Teilnahmen dieser Person und verändert damit
  rückwirkend die Punkte *aller anderen*. Deshalb gibt es bewusst kein
  `deletePerson` im Repository. `active: false` ist der Ersatz und wird von
  `activeRankingProvider` und dem Fahrten-Editor respektiert.
- In Screens keine rohen Farb-/Pixelwerte — `core/tokens.dart` bzw.
  `Theme.of(context)` verwenden.
- Sicherheit serverseitig (RLS), Auth-Guard im Router (`redirect` +
  `refreshListenable`), nicht nur in der UI.
- **Multi-Tenant:** Eine Gruppe = ein Login (`group_id = auth.uid()`). Alle
  Datentabellen tragen `group_id` (Default `auth.uid()`), RLS erzwingt
  `group_id = auth.uid() AND my_group_active()`. Neue Gruppen sind `pending`
  bis eine Admin-Gruppe sie freigibt. Login = Handle → `handle@grp.local`
  (`core/group_login.dart`). Neue Datentabellen brauchen zwingend `group_id`
  plus dieselbe RLS-Policy, sonst lecken Daten zwischen Gruppen.
- **Eine Gruppe = ein Login bleibt, auch für den Wochenplaner** (entschieden
  2026-07-20). Es gibt bewusst **keine Identität pro Person**: Der Planer ist
  ein Raster Person × Wochentag, in dem jeder für jeden eintragen darf — das
  ist ehrlich zu dem, was ein geteilter Zugang ohnehin bedeutet. Echte Logins
  pro Person würden `group_id = auth.uid()` und damit jede RLS-Policy
  umkrempeln; das ist ein eigenes Projekt, kein Nebeneffekt eines Features.
- **Geplantes darf die Punkte nie berühren.** `plan_availability` und
  `plan_overrides` speichern nur, was Menschen entschieden haben. Der
  vorgeschlagene Fahrer wird **nicht** gespeichert (berechnete Kennzahl, wie
  Punkte und Quote), und es gibt **kein „bestätigt"-Kennzeichen**: Die
  Bestätigung erzeugt eine Zeile in `trips`, deren Existenz am Tag *ist* die
  Bestätigung. Dadurch sieht `computeStats` ausschließlich gefahrene Fahrten.
  Wer hier ein Statusfeld ergänzt, baut sich zwei Wahrheiten.
- **Der Wochenvorschlag simuliert vorwärts** (`planWeek` in
  `core/fairness.dart`): Jeder Tag wird gegen die Statistik *inklusive* der
  bereits vorgeschlagenen Vortage gerechnet. Ohne das ändert sich nichts, bis
  eine Fahrt eingetragen ist — und alle fünf Tage schlagen dieselbe Person
  vor. Tage mit echter Fahrt werden nicht zusätzlich simuliert, sonst zählen
  sie doppelt. Beides ist in `test/plan_test.dart` festgenagelt.
- Kein `print` in `lib/` — zentraler Logger `core/log.dart`.
- **Was geloggt wird, kann öffentlich werden.** `core/log.dart` hält die
  letzten 50 Zeilen in `logRing` (nur im Speicher, nie auf Platte), und die
  Nutzerin kann sie einer Rückmeldung anhängen — die der Feedback-Bot in ein
  **öffentliches** GitHub-Issue verwandelt. Deshalb gehören in `log`-Aufrufe
  niemals Personennamen, Handles oder Fahrtdaten. Der Anhang ist bewusst
  standardmäßig abgewählt und wird vor dem Senden im Klartext angezeigt.
  Absichtlich kein Sentry: eine Gruppe von wenigen Leuten, die den Betreiber
  kennt, braucht keine Fremd-Pipeline (Issue #18).
- Nach jedem `await` in Widgets `mounted`/`context.mounted` prüfen.
- Server-/App-State in Riverpod-Providern, Formular-State in StatefulWidgets.
- **Riverpod 2 (kein Codegen)** — bewusst gepinnt. Unter 3.x pausiert/resumed
  Riverpod Subscriptions beim Seitenwechsel und stößt dabei Provider-
  Invalidierungen mitten in der Build-Phase an („setState during build").
- **Daten-Provider hängen an `currentUserIdProvider`**, nie direkt am
  Auth-Event-Stream: Sonst lädt bei jedem Ereignis (auch Token-Refresh)
  alles neu und invalidiert im schlechtesten Moment.
- Tests: `test/fakes/` enthält ein In-Memory-Backend, das die Mandanten-
  trennung nachbildet; `pumpApp` startet die echte App dagegen. Neue Abläufe
  bekommen einen Flow-Test in `test/flows/`. Netzzugriffe (Update-Check) in
  Tests immer per Override stilllegen.
- **Release-only-Fallen bekommen einen Konfigurations-Regressionstest.**
  `test/android_manifest_test.dart` prüft INTERNET-Permission,
  `REQUEST_INSTALL_PACKAGES`, die `<queries>`-Sichtbarkeit, die exakte
  FileProvider-Authority, `filepaths.xml` und die Desugaring-Flags. Solche
  Fehler kompilieren sauber und fallen sonst erst auf dem Gerät des Nutzers
  auf. Jede neue Manifest-/Gradle-Voraussetzung kommt dort mit einer
  `reason:` dazu, die den echten Ausfall beschreibt.
- Charts sind **bewusst selbst gebaut** (`core/chart_data.dart` = reine
  Aggregationsfunktionen, `core/widgets/charts.dart` = CustomPainter) —
  keine Chart-Library als Dependency. Aggregation bleibt testbar getrennt
  vom Zeichnen (`test/chart_data_test.dart`).

## Workflow

- **Kein direkter Push auf `main`** (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge.
- **Wer mergen darf, entscheidet der Versions-Bump** — denn der Merge ist die
  Veröffentlichung:
  - **Ohne Bump** (nur `*.md`, `.github/`, `test/`, `tool/`, `LICENSE`):
    Claude darf nach grüner CI selbst squash-mergen. Es entsteht kein Release,
    die Gruppen bekommen nichts davon mit.
  - **Mit Bump**: **Der Merge gehört dem Menschen.** Er löst Tag, Release,
    APK und Pages-Deploy aus — das veröffentlicht Marcus selbst.
- Commit-/PR-Titel: Conventional Commits. GitHub-Kommunikation Englisch,
  UI-Strings und Nutzer-Doku Deutsch.
- Release = Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen,
  z. B. `0.2.0+3`). Der Release-Workflow taggt `v<version>` und deployt Web
  auf GitHub Pages. Kein Bump = kein Release.
- Version Guard in CI: Code-Änderung ohne Versions-Bump blockiert den Merge.
  Ausgenommen sind `*.md`, `.github/`, `test/`, `tool/` und `LICENSE` — reine
  Doku-, CI-, Test- oder Tooling-Arbeit soll kein Release auslösen.
- **Zu jedem Versions-Bump gehört ein `CHANGELOG.md`-Eintrag** (Nutzersicht,
  Deutsch: was ändert sich für die Gruppen — nicht die Commit-Liste).
- Flutter-Version in CI gepinnt (3.41.2) — bei lokalem Upgrade auch
  `.github/workflows/*.yml` anpassen. Lokales SDK:
  `/Volumes/MacStore/Programming/Flutter/SDK/flutter`.
- **Vor jedem Push `dart format .` laufen lassen.** Die CI prüft mit
  `--set-exit-if-changed` und wird sonst rot — der häufigste vermeidbare
  Fehlschlag. Danach `flutter analyze` und `flutter test`.
- **Die Required Checks hängen an den `name:`-Feldern der CI-Jobs**
  („Analyze & Test", „Build Web", „Build Android APK", „Version Guard").
  Wird ein Job umbenannt, greift die Branch Protection stillschweigend nicht
  mehr — Umbenennung immer zusammen mit den Repo-Einstellungen.

## Technik-Notizen

- Supabase-Zugang: `lib/core/supabase_config.dart`. Solange dort Platzhalter
  stehen, läuft die App im Demo-Modus (In-Memory-Daten, kein Login). Der
  Publishable-Key ist bewusst öffentlich; NIEMALS den service_role-Key
  einchecken.
- DB-Änderungen: Supabase ist per GitHub-Integration mit dem Repo verbunden —
  neue Migration als `supabase/migrations/<YYYYMMDDHHMMSS>_<name>.sql` anlegen,
  sie wird bei Push auf `main` automatisch eingespielt (kein manuelles
  Patchen). `supabase/schema.sql` bleibt das gepflegte Gesamtbild (Doku).
- Repo: `github.com/MacBuchi/Fahrgemeinschaft`, Default-Branch `main`.
  Web-Builds für Pages brauchen `--base-href /Fahrgemeinschaft/`
  (Groß-F, case-sensitiv!) und eine `404.html` (Kopie von `index.html`)
  als SPA-Fallback. Live-URL: `https://macbuchi.github.io/Fahrgemeinschaft/`
- Echte Namen/Daten der Gruppe liegen NUR in `.donotsync/` (gitignored):
  `Fahrgemeinschaft.xlsx` (Original) und `seed/seed.json` (extrahiert).
  Einmal-Import in eine leere DB: `tool/import_seed.py`. Der Excel-Backtest
  in `test/fairness_test.dart` überspringt sich selbst, wenn `seed.json`
  fehlt (z. B. in CI).
- Status-Werte in der DB: `driver` / `passenger` / `one_way`
  (Dart-Enum `ParticipationStatus.driver/passenger/oneWay`).
- **Android:** Bundle-ID `de.macbuchi.fahrgemeinschaft`. Release-Signing kommt
  aus `android/key.properties` (gitignored, in CI aus Secrets erzeugt). Ohne
  hinterlegten Keystore erscheint das Release bewusst **ohne APK** — nie still
  debug-signieren, sonst bricht jedes Update an der Signatur. Nötige Secrets:
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. **Keystore sichern** —
  Verlust bricht In-Place-Updates dauerhaft.
- **Update-Hinweis** (`core/update_check.dart`) pollt das neueste
  GitHub-Release (tokenlos). Jeder Fehlerpfad endet in `null` = kein Banner.
- **In-App-Update (Android)** installiert per `ota_update` aus dem
  Release-APK. Dafür müssen zusammenbleiben: `INTERNET` +
  `REQUEST_INSTALL_PACKAGES`, der FileProvider mit Authority **exakt**
  `${applicationId}.ota_update_provider`, `res/xml/filepaths.xml` mit
  `files-path ota_update/`, der `<queries>`-Eintrag VIEW/https für den
  Browser-Fallback und Core Library Desugaring in `build.gradle.kts`.
  Fehlt der FileProvider, stirbt die App direkt nach dem Download.
  Abgesichert durch `test/android_manifest_test.dart` — Änderungen daran
  zusätzlich auf einem echten Gerät verifizieren.
- **Android-Backup schließt die Sitzung aus** (`res/xml/backup_rules.xml` für
  Android ≤ 11, `res/xml/data_extraction_rules.xml` ab 12, beide am
  `<application>` verdrahtet). Grund: Eine Gruppe = ein Login, das
  Sitzungs-Token ist also das gemeinsame Zugangsmerkmal der Gruppe und darf
  nicht über das Google-Konto eines Mitglieds auf fremde Geräte wandern.
  Zwei Fallen dabei: Backup-Regeln adressieren **ganze Dateien**, nie
  einzelne Schlüssel — deshalb steht dort `FlutterSharedPreferences.xml`, was
  nur deswegen verlustfrei ist, weil `shared_preferences` ausschließlich
  transitiv über `supabase_flutter` hereinkommt. Sobald `lib/` selbst etwas
  in SharedPreferences ablegt, gehört diese Regel überdacht. Und ab
  Android 12 braucht der Ausschluss **beide** Blöcke (`cloud-backup` *und*
  `device-transfer`), sonst reist das Token beim Gerätewechsel doch mit.
- **CSV-Export** ist die einzige Sicherung, die die Gruppe selbst in der Hand
  hat — alles seit dem Erst-Import lebt nur in Supabase (Free Plan, kein
  Point-in-Time-Recovery). `core/csv_export.dart` ist reine Aufbereitung
  (testbar, `test/csv_export_test.dart`), `core/export_file.dart` die
  Plattform-Weiche: Web lädt über einen Blob-Link herunter, Android reicht die
  Datei per `share_plus` ans Teilen-Menü (`XFile.fromData`, deshalb kein
  `path_provider`). Drei Formatdetails sind nicht kosmetisch, sondern
  entscheiden, ob die Datei in deutschem Excel per Doppelklick aufgeht:
  `;` als Trenner, CRLF als Zeilenende und ein UTF-8-BOM. Der Export **ist**
  die Import-Vorlage (Issue #34) — ein zweiter Template-Generator wäre eine
  zweite Wahrheit über das Format.
- **Feedback** landet in der Tabelle `feedback`; der Bot
  (`tool/feedback_bot.py`, `.github/workflows/feedback.yml`) macht daraus
  Issues. Er ruht, solange `SUPABASE_SERVICE_ROLE_KEY` nicht gesetzt ist.
  Die Issue-Templates unter `.github/ISSUE_TEMPLATE/` und die Felder im
  Feedback-Dialog gehören zusammen — Änderungen immer paarweise.
- **Branding:** `tool/brand/mark.svg` ist die einzige Quelle der Bildmarke.
  `tool/brand/build_icons.sh` (braucht `rsvg-convert` + python3) erzeugt
  daraus Web-Icons (normal + maskable), Favicon und die Android-Mipmaps
  inklusive Adaptive-Icon-Vordergrund. Icons nie von Hand bearbeiten.
  Schrift: Space Grotesk (Display) + Manrope (Body) als Variable Fonts.
- **Lizenz:** `LICENSE` ist MIT. Die Bildmarke und die gebündelten Schriften
  hängen nicht daran — Space Grotesk und Manrope stehen unter der SIL OFL,
  die verlangt, dass ihr Lizenztext mitgeliefert wird. Neue Assets deshalb
  immer mit ihrer Lizenz zusammen einchecken.
- **Der Release-Workflow prüft selbst.** `release.yml` entscheidet erst über
  den Tag, lässt dann `flutter analyze` + `flutter test` laufen und taggt erst
  danach. Grund: Der Merge ist die Veröffentlichung, aber `enforce_admins` ist
  aus — ein direkter Push auf `main` käme sonst am Branch-Schutz vorbei
  ungeprüft bis in Tag, APK und Pages-Deploy. Das Gate darf nie hinter das
  Taggen rutschen.
- **Dependabot läuft monatlich und gebündelt** (`.github/dependabot.yml`).
  Die Bündelung über `groups:` ist kein Kosmetik-Detail: `pubspec.yaml` ist
  nicht vom Version Guard ausgenommen, jeder pub-PR verlangt also einen
  Versions-Bump und veröffentlicht ein Release. Einzeln wären das bis zu fünf
  Releases im Monat nur für Abhängigkeiten. Die Guard-Regel bleibt trotzdem
  wie sie ist — ein Dependency-Wechsel geht wirklich an die Gruppen raus.
  Riverpod-Majors sind per `ignore` ausgenommen (2.x ist bewusst gepinnt).
- **`analysis_options.yaml` trägt die Leitplanken dieser Datei**: `avoid_print`
  und `use_build_context_synchronously` auf `error` hochgestuft, dazu
  `unawaited_futures`, `prefer_const_constructors`, `prefer_final_locals` und
  `strict-casts`/`strict-raw-types`. Abgesichert durch
  `test/analysis_options_test.dart` — wird eine Regel entfernt, bleibt
  `flutter analyze` grün und die Leitplanke verschwindet lautlos.
  **`require_trailing_commas` nie eintragen**: Die Regel gibt es seit Dart 3.7
  nicht mehr, ein Eintrag erzeugt eine „undefined lint rule" und damit rote CI.

# MitFahrBar — Arbeitsregeln

Flutter-Web-App (PWA) + Android-APK zur Verwaltung einer Fahrgemeinschaft:
Fahrtenprotokoll, Punkte-/Fairness-System („wer ist dran"), Statistik,
Dashboard-Charts. Supabase-Backend (multi-tenant, RLS in
`supabase/schema.sql`), Riverpod 2 ohne Codegen, go_router, deutsche
UI-Strings direkt im Code. Fachkonzept: `KONZEPT.md`.

Produktname ist **MitFahrBar** (seit v0.34.0, davor RideBuddy ab v0.6.0).
Repo, Dart-Package und Bundle-ID tragen den Namen mit — die Umbenennung war
bewusst vollständig (Issue #87): Ein Neuinstall auf Android war der Gruppe
lieber als ein zweiter Name im System.

**Zwei Dinge blieben trotzdem stehen, und das ist kein Versehen:**

- **`grp.fahrgemeinschaft.app`** (`core/group_login.dart` + Edge Function)
  ist die Login-Adresse jeder bestehenden Gruppe — sie steht serverseitig
  als E-Mail in `auth.users`. Umbenennen hieße Migration auf den
  Zugangsdaten der aktiv genutzten Gruppe, für etwas, das nie jemand
  sieht (der Login ist Handle + Passwort).
- **Der Handle `fahrgemeinschaft`** in
  `20260720140000_multi_tenant_groups.sql` ist der echte Login der
  Live-Gruppe (bis v0.38.0 war sie zugleich die Admin-Gruppe), also Daten in
  einer bereits eingespielten Migration. Migrationen werden nie nachträglich
  umgeschrieben — auch `is_admin` steht dort noch, obwohl die Spalte seit
  v0.38.0 nicht mehr existiert. Wer eine Frischinstallation braucht, nimmt
  `supabase/schema.sql`; die Migrationskette ist Geschichte, kein Sollzustand.

Ebenso unverändert: die `CHANGELOG.md`-Einträge vor v0.34.0 — sie
beschreiben Releases, die wirklich RideBuddy hießen.

Projektübergreifende Guidelines (Architektur, State, Testing, CI, Signing,
In-App-Update/-Feedback) liegen im DocuHub unter
`/Volumes/MacStore/Programming/ProgrammingGuidelineDocuHub/`. Diese Datei
beschreibt, was für MitFahrBar davon abweicht oder zusätzlich gilt.

## Bekannte Abweichungen Konzept ↔ Implementierung

`KONZEPT.md` ist an diesen Stellen überholt — bei Widersprüchen gilt der Code:

- Name „FairFahrt" (§9.1) → das Produkt heißt MitFahrBar.
- `tool/import_xlsx.dart` (Dart-CLI) → umgesetzt wurde `tool/import_seed.py`.
- Postgres-View `person_stats` (§4) → nie gebaut; alle Kennzahlen entstehen
  clientseitig in `lib/core/fairness.dart`.
- Preis-Historisierung mit „Gültig-ab" (§3.4) → `settings` ist nur
  `(group_id, key) → value`, ohne `valid_from`.
- §5.5 ist abgearbeitet: Personen und Fahrzeuge pflegt seit v0.10.0
  `features/persons/persons_screen.dart` (`/persons`), die **Parameter**
  seit v0.33.0 `features/settings/settings_screen.dart` (`/settings`).
- Admin-Screen und Gruppen-Freigabe (§7) → seit v0.38.0 entfernt (#108),
  siehe „Der Gruppen-Lebenszyklus" unten.

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
- **Der Parameter-Screen zeigt nur die Kosten-Werte** (`features/settings/`,
  seit v0.33.0, Issue #91): Arbeitsweg und die drei Kraftstoffpreise. Sie
  gehen ausschließlich in Kilometer und Ersparnis ein. `one_way_factor` und
  `points_weight` liegen in derselben Tabelle, gehören aber **nicht** in
  dieses Formular: Sie verschieben rückwirkend die Punkte *aller* — und
  `points_weight` ist die dokumentierte Rückfahrkarte der Fairness-Regel,
  die über eine Migration gesetzt wird, nicht von einem beliebigen
  Mitglied. Weil `saveSettings` immer die ganze Tabelle schreibt, reicht
  der Screen beide Werte über `AppSettings.copyWith` unverändert durch —
  `test/flows/settings_flow_test.dart` nagelt genau das fest. Wer dort ein
  Feld ergänzt, prüft zuerst, ob es die Punkte berührt.
- **Spritpreise holt die App bewusst nicht aus dem Netz** (entschieden
  2026-07-24, Teil 3 von #91). Ein Preisdienst (Tankerkönig) braucht einen
  API-Schlüssel, der nicht in einen offenen Client darf — also eine
  weitere Edge Function samt Secret und Cache, für eine Kennzahl, die
  ausdrücklich „ganz grob" sein soll. Dieselbe Linie wie „kein Sentry"
  und „kein Captcha-Dienst". Der Screen sagt das dem Nutzer auch. Wird es
  je gebaut, ist die Function der Ort — nie der Client.
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
- **`app_config` ist die einzige Tabelle ohne `group_id`** — und muss die
  einzige bleiben. Sie hält gruppenübergreifende Konfiguration
  (`min_supported_version`, Issue #19), enthält keine Gruppendaten und ist für
  Clients **nur lesbar**: bewusst keine Insert-/Update-Policy, sonst könnte ein
  Client die Mindestversion hochsetzen und alle aussperren. `anon` darf lesen,
  damit der Sperr-Schirm schon vor dem Login greift. `test/schema_test.dart`
  nagelt fest, dass dort nur `select` steht.
- **Die Regel dazu:** Jede Migration, die etwas entfernt oder umbenennt, das
  ein veröffentlichter Client liest, hebt **im selben File** die
  `min_supported_version` auf die Version, die damit umgehen kann. Der Wert
  liegt genau deshalb in der DB und nicht im Repo: So kann er dem Schema nicht
  vorauseilen.
- **Der Sperr-Schirm darf nie zur Falle werden.** `updateRequiredProvider`
  (`data/providers.dart`) sperrt nur, wenn es ein installierbares Update gibt,
  nie bei unbekannter Mindestversion (offline) und nie bei Gleichstand. Damit
  gilt: Der neueste Client kommt immer durch. Wer eine dieser drei Bedingungen
  „aufräumt", baut eine Aussperrung, die nur ein neues Release behebt —
  `test/update_check_test.dart` und `test/flows/update_required_flow_test.dart`
  halten alle drei fest.
  **Vierte Bedingung, seit v0.38.0 und teuer gelernt: Vom Schirm muss ein Weg
  wegführen, und der muss geprüft sein — nicht nur seine Sichtbarkeit.** Der
  Schirm ERSETZT im `builder` der MaterialApp den Router-Navigator; er
  braucht deshalb einen **eigenen** `Navigator` (`app.dart`), sonst findet
  `showDialog` keinen, wirft, Flutter schluckt die Exception und der Knopf tut
  sichtbar nichts. Genau das lief bis 0.37.0 (Pixel 7, 26.07.2026): Es half
  nur Deinstallieren und Neuinstallieren. Im Normalbetrieb fällt es nie auf,
  weil das Update-**Banner** innerhalb des Router-Navigators sitzt — kaputt
  ist nur der Weg, den man ausschließlich im gesperrten Zustand sieht.
  Deshalb steht daneben `openUpdateInBrowser` als zweiter Weg **ohne
  BuildContext**: kein Dialog, kein Navigator, kein Overlay. Wer ihn an eine
  SnackBar, einen Router-Aufruf oder einen Dialog hängt, nimmt ihm den Zweck.
  Der Regressionstest **tippt** beide Knöpfe an; ein Test, der nur `find`
  benutzt, hätte den Ausfall wieder nicht gesehen.
- **Eine Mindestversion ist erst dann berechtigt, wenn der alte Client
  wirklich bricht.** Sie zu heben ist nicht der Normalfall einer Migration,
  sondern der Ausnahmefall: Sie wirft jeden veralteten Client auf den
  Sperr-Schirm, und ein Fix an diesem Schirm erreicht genau die nicht, die
  schon davorstehen — aus diesem Loch kann man sich nicht heraus-releasen.
  Vor dem Heben also prüfen, was der veröffentlichte Client mit dem neuen
  Schema tatsächlich tut. Bei #108 etwa fing `json['is_admin'] as bool? ??
  false` die entfernte Spalte sauber ab, die Selects liefen ins Leere statt in
  Fehler — dort wurde bewusst **nicht** gehoben. Gehoben wird, wenn der Client
  ohne Update falsche Daten zeigt oder in eine Exception läuft.
- **Multi-Tenant:** Eine Gruppe = ein Login (`group_id = auth.uid()`). Alle
  Datentabellen tragen `group_id` (Default `auth.uid()`), RLS erzwingt
  `group_id = auth.uid() AND my_group_active()`. Neue Gruppen entstehen seit
  v0.37.0 in der Verwalter-Konsole und sind sofort `active`; `pending` gibt es
  nur noch als Ruhezustand für Fremd-Signups gegen die Gruppen-Domain (siehe
  Lebenszyklus unten). Login = Handle → `handle@grp.fahrgemeinschaft.app`
  (`core/group_login.dart`). Neue Datentabellen brauchen zwingend `group_id`
  plus dieselbe RLS-Policy, sonst lecken Daten zwischen Gruppen.
- **Der Gruppen-Lebenszyklus trägt drei Invarianten** (#106, seit v0.37.0).
  Sie sind der Grund, warum das Stilllegen ungenutzter Gruppen später ein Job
  von wenigen Zeilen ist und kein Umbau:
  - **Eine aktive Gruppe hat genau einen Verwalter.** Jede Gruppe entsteht
    verknüpft (Function schreibt `status='active'` UND die
    `group_admins`-Zeile; scheitert der zweite Schritt, wird der Auth-User
    zurückgenommen). Der einzige legitime Ausnahmezustand ist das
    Übergabefenster nach `admin_release_group` — und der ist **markiert**:
    `groups.released_at` wird von einem Trigger auf `group_admins` gesetzt,
    der auch die Kaskade eines gelöschten Verwalter-Kontos fängt. Ohne diesen
    Trigger wäre eine stille Waise von einer laufenden Übergabe nicht zu
    unterscheiden.
  - **Ein unbekannter Status gilt niemals als aktiv.** `Group.statusFrom`
    parst tolerant (`unbekannt → archived`) statt mit `byName`, das **wirft**.
    Wer das zurückdreht, macht jede künftige Statusänderung zu einem
    Release-Zwang: Der Fehler landete in `myGroupProvider`, die Nutzerin sähe
    „Fehler: Invalid argument", und der Sperr-Schirm greift bewusst nie ohne
    installierbares Update. `test/group_status_test.dart` wacht über den
    Parser, `test/flows/auth_flow_test.dart` über die andere Hälfte: dass der
    `archived`-Zweig im `PendingScreen` wirklich **erklärt** statt zu
    scheitern. Ohne diesen Zweig wäre der tolerante Parser wertlos.
  - **Archivieren ist ein Statuswechsel, keine Löschung.**
    `my_group_active()` prüft auf `'active'` — `status='archived'` macht eine
    Gruppe über alle Policies hinweg still, verlustfrei und umkehrbar. Der
    Wert steht deshalb schon im Check-Constraint, obwohl ihn heute nichts
    setzt.
  Vorgesehen, aber **nicht gebaut**: ein Aufräum-Job neben `tool/notify.dart`
  (GitHub Actions, Service-Role-Key, nur Zahlen ins Log). Verwaist = `groups`
  ohne `group_admins`-Zeile (Join, kein Feld nötig), ungenutzt = `trips` /
  `plan_availability` / `auth.users.last_sign_in_at`, das GoTrue von selbst
  pflegt. Bewusst **kein** `last_active_at`: Es müsste vom Client kommen, und
  `groups` hat keine Update-Policy. Ebenfalls benannt und nicht gebaut: Wer
  Postfach UND Passwort verliert, kommt an seine Gruppen nicht mehr heran —
  vorgesehen dafür ist eine **Übernahme mit Widerspruchsfrist**, nicht ein
  zweiter Schlüssel (jedes Mitglied kennt das Gruppenpasswort). Diese Lücke
  darf nicht verschlimmert werden; deshalb überlebt das Verwalter-Konto das
  Löschen einer Gruppe.
- **Es gibt keine Admin-Gruppe und keine Freigabe mehr** (#108, seit v0.38.0).
  Weg sind `groups.is_admin`, `is_group_admin()`, die Update-Policy
  `groups_admin_update`, `features/admin/`, die Route `/admin` und
  `GroupRepository.pendingGroups`/`setStatus`. Der Grund ist kein Aufräumen:
  Die administrative Macht saß auf einem **geteilten** Gruppen-Login ohne
  „Passwort vergessen", und es gab keinen Code-Weg, das Flag zu setzen. Am
  26.07.2026 war eine Freigabe deshalb unmöglich und brauchte Betreiber-SQL.
  Verwaltet wird über das Verwalter-Konto mit echter E-Mail, wo der
  Reset-Weg (#102) funktioniert.
  - **Die Update-Policy auf `groups` kommt nie zurück.** Mit ihr könnte ein
    Client seinen eigenen `status` schreiben, sich also selbst freischalten
    und eine Archivierung zurückdrehen — damit wären **alle** Statuswerte als
    Riegel wertlos, auch der künftige `archived`, und der Aufräum-Job hätte
    keine Wirkung, die hält. Gruppen ändern sich ausschließlich über die
    SECURITY-DEFINER-Funktionen der Konsole und den Service-Role-Key.
    `test/schema_test.dart` prüft die Abwesenheit der Policy,
    `test/e2e/rls_e2e_test.dart` beweist sie am echten Postgres (eine
    pending-Gruppe kann sich nicht selbst aktivieren).
  - **`pending` heißt ab hier „nie in Gebrauch genommen"**, nicht „wartet" —
    es gibt niemanden mehr, der freigibt. Der Zustand entsteht nur noch durch
    ein Fremd-`signUp` gegen die Gruppen-Domain (nicht abstellbar, solange die
    Verwalter-Registrierung offen ist) und bleibt inert. `pending_screen.dart`
    trägt Texte für genau die drei Zustände, die es gibt.
  - **Die Migration ist der Musterfall für Reihenfolge.**
    `handle_new_group()` wird neu geschrieben **vor** dem `drop column` — die
    alte Fassung führt `is_admin` in ihrer Insert-Spaltenliste, fiele die
    Spalte zuerst, scheiterte in diesem Moment **jeder** Signup, auch der
    eines Verwalter-Kontos. Und die Policies fallen vor der Funktion, die sie
    aufrufen, sonst verweigert Postgres das `drop function`. Beides nagelt
    `test/schema_test.dart` als Positionsvergleich fest.
  - Weil eine Migration ihre eigene Entfernung begründet, prüfen solche
    „kommt nicht mehr vor"-Tests den SQL-Code **ohne Kommentare**
    (`sqlOnly` in `test/schema_test.dart`) — sonst scheitern sie an der
    Begründung im File selbst.
- **Gruppen-Konten entstehen nur serverseitig** (seit v0.27.0, Edge Function
  `supabase/functions/request-group/`). Grund: In Production ist die
  Mail-Bestätigung Pflicht (`mailer_autoconfirm` aus — nötig, damit
  Verwalter-Konten ihr Postfach beweisen und „Passwort vergessen"
  funktioniert). Ein Client-`signUp` für eine Gruppe schickte damit eine
  Bestätigungsmail an die unzustellbare Fake-Adresse (Bounce bei Brevo) und
  das Konto bliebe für immer gesperrt. Die Function legt es per Admin-API
  mit `email_confirm: true` an — mail-frei. Drei Fallen: Das Handle-Mapping
  existiert doppelt (Dart in `core/group_login.dart`, TypeScript in der
  Function) und muss synchron bleiben; wer `mailer_autoconfirm` wieder
  einschaltet, nimmt den Verwalter-Konten die Postfach-Verifizierung; und der
  Teststack läuft bewusst mit `enable_confirmations = true` (config.toml),
  damit die E2E-Suite (`test/e2e/auth_mail_e2e_test.dart`) genau diese
  Prod-Wahrheit prüft — genau dieser Config-Drift hat den Fehler ursprünglich
  versteckt.
  Nach jedem Merge, der `supabase/functions/` ändert: prüfen, ob die
  GitHub-Integration die Function deployt hat (sie deployt die in
  config.toml deklarierten), sonst manuell
  `supabase functions deploy request-group`. **Bei diesem Umbau ist das
  release-blockierend:** Neue App plus alte Function heißt, die Anlage läuft
  anonym durch, die Gruppe bleibt `pending` und unverknüpft — eine tote Gruppe.
  **Seit v0.37.0 ruft die Konsole diese Function, authentifiziert** (#106): Der
  Rumpf prüft mit `getUser`, dass ein Verwalter-Konto mit bestätigtem Postfach
  ruft (401 ohne Nutzer, 403 sonst). `verify_jwt = true` allein genügt dafür
  **nicht** — der anon-Key ist selbst ein gültiges JWT; ohne die Prüfung wäre
  der Endpunkt eine offene Gruppenfabrik. Der Deckel liegt bei 5 Gruppen je
  Konto und gilt zweifach: hier als klare Meldung (429) und als Wahrheit im
  Trigger `group_admins_cap`. Damit sind `SIGNUP_HOURLY_CAP` (#69) und die
  vorgemerkte **Cloudflare-Turnstile**-Idee erledigt und ausgebaut — der
  öffentliche Weg, den sie schützen sollten, existiert nicht mehr.
  Der Deckel ist bewusst ein **Trigger** und keine aufrufbare Funktion:
  `alter default privileges` gibt `authenticated` execute auf jede Funktion,
  eine „verknüpfe mich"-Funktion wäre also die Übernahme-Lücke.
- **`group_id` gehört auch in fachliche Primärschlüssel.** Wo der Schlüssel
  keine generierte UUID ist, sondern aus Fachdaten besteht (`plan_date`,
  `person_id`, …), muss `group_id` darin stehen — sonst ist er über alle
  Gruppen eindeutig, und die zweite Gruppe läuft beim Speichern in eine
  Unique-Verletzung auf einer Zeile, die die RLS ihr nicht einmal zeigt.
  Genau so lag `plan_overrides` bis v0.15.0 im Schema. Das Konfliktziel des
  `upsert` im Repository muss denselben Schlüssel nennen; driften beide
  auseinander, meldet Postgres „no unique or exclusion constraint matching
  the ON CONFLICT specification". Beides prüft `test/schema_test.dart`.
- **Eine Gruppe = ein Login bleibt, auch für den Wochenplaner** (entschieden
  2026-07-20). Es gibt bewusst **keine Identität pro Person**: Der Planer ist
  ein Raster Person × Wochentag, in dem jeder für jeden eintragen darf — das
  ist ehrlich zu dem, was ein geteilter Zugang ohnehin bedeutet. Echte Logins
  pro Person würden `group_id = auth.uid()` und damit jede RLS-Policy
  umkrempeln; das ist ein eigenes Projekt, kein Nebeneffekt eines Features.
- **Daneben: höchstens EIN Verwalter-Konto je Gruppe** (Issue #55, v0.23.0) —
  echte E-Mail, `account_type: 'admin'` in den Auth-Metadata. Es sieht
  **keine** Gruppendaten (anderer uid, RLS blockt) und kann ausschließlich
  über SECURITY-DEFINER-Funktionen: Gruppenpasswort neu setzen und Gruppe
  löschen (`admin_delete_group` löscht den Gruppen-**Auth-User** — die
  Kaskade nimmt alles mit; nie einzelne Tabellen löschen).
  **Umgekehrt trägt ein Konto seit v0.37.0 bis zu 5 Gruppen** (#106): PK ist
  `(user_id, group_id)`, `group_id unique` bleibt. Jede Aktion nennt deshalb
  ihre `target_group` und prüft das Eigentum — und `admin_delete_group`
  entfernt **genau eine** Zeile in `auth.users`, die der Zielgruppe. Das
  Verwalter-Konto überlebt: Bei mehreren Gruppen wäre ein Selbst-Löschen
  Datenverlust an den übrigen. Die Signaturen wurden dabei **gedroppt und neu
  angelegt**, nicht ersetzt — `create or replace` kann keine Signatur ändern,
  ein Overload hätte bei einem alten Client still die *erste* Gruppe getroffen
  und damit die falsche gelöscht.
  `group_admins` hat bewusst **null Policies**; der Signup-Trigger überspringt
  Admin-Konten, sonst entstehen Geister-„pending"-Gruppen; die
  Erst-Verknüpfung beweist sich mit dem Gruppen-Login und **rastet ein**
  (bis dahin gewinnt das erste Postfach — der Verwalter verknüpft direkt
  nach dem Release). Das Einrasten hat seit v0.29.0 genau EINEN gewollten
  Ausgang: Der aktuelle Verwalter löst die Verknüpfung selbst
  (`admin_release_group`, Sudo-Muster) — danach rastet das nächste Konto
  über den normalen claim-Weg ein; die E-Mail-Adresse wechselt über
  Supabase-Standard (Links an alte UND neue Adresse). Bewusste Grenze:
  Postfach UND Passwort zugleich verloren heißt Betreiber-SQL — jeder
  Selbstbedienungs-Weg daran vorbei wäre die Übernahme-Lücke, die das
  Einrasten verhindert (jedes Mitglied kennt das Gruppenpasswort!). „Passwort ändern" gibt es
  im Gruppen-Menü nicht mehr — nur die Konsole setzt es neu, damit kein
  Mitglied alle aussperrt und der Verwalter jeden Schaden selbst heilt
  (kein Betreiber-Eingriff). Auth-Mails (Reset, Bestätigung) brauchen
  **eigenes SMTP** in Supabase (Brevo Free) — Supabases Standardversand
  liefert nur an Projekt-Teammitglieder. `test/schema_test.dart` nagelt
  alle vier Annahmen fest.
- **Die Konsolen-Mails tragen einen Code, keinen Link** (Issue #102, seit
  v0.35.0) — betrifft „Passwort vergessen" und die Registrierungs-
  Bestätigung. Grund ist kein Geschmack: `resetPasswordForEmail` legt im
  PKCE-Standardflow einen Code-Verifier im Speicher des **anfordernden**
  Geräts ab (`gotrue_client.dart`, `_generatePKCECodeChallenge`) und
  verlangt ihn beim Einlösen wieder. Wer in der Android-App anfordert und
  die Mail im Handy-Browser öffnet — der Normalfall —, hat ihn dort nicht:
  Der Link stirbt still mit „Code verifier could not be found in local
  storage.", und weil das `passwordRecovery`-Ereignis am selben Eintrag
  hängt, erscheint auch kein Dialog. Keine Landeseite kann das heilen.
  `verifyOTP(type: recovery)` ist gerätefrei, braucht weder `redirectTo`
  noch einen `uri_allow_list`-Eintrag. Drei Dinge hängen zusammen und
  dürfen nicht einzeln „aufgeräumt" werden:
  - **Verify und `updateUser` sind EIN Repository-Aufruf**
    (`resetAdminPasswordWithCode`). `verifyOTP` erzeugt eine gültige
    Sitzung, *bevor* das neue Passwort existiert — bliebe es dazwischen
    stehen, wäre jemand angemeldet, ohne sein Passwort zu kennen.
    Scheitert das Ändern, meldet der Screen die Recovery-Sitzung ab.
  - **Der Router filtert `passwordRecovery` aus dem Refresh-Stream**
    (`core/router.dart` + `isPasswordRecovery`). Ohne den Filter risse der
    Redirect „Admin-Sitzung → /console" den Konsolen-Login mitten im
    Zurücksetzen weg. Erst das Ereignis aus `updateUser` lässt herein.
    `test/flows/console_reset_flow_test.dart` wird ohne den Filter rot.
  - **Die Mail-Vorlagen zeigen `{{ .Token }}` und KEINEN
    `{{ .ConfirmationURL }}`.** Bleibt der Link stehen, ist der kaputte Weg
    weiter erreichbar. Wirksam sind die Vorlagen im **Dashboard**
    (Authentication → Emails → Templates → Reset Password / Confirm sign
    up); `supabase/templates/*.html` ist die versionierte Kopie, die
    zugleich den lokalen Teststack versorgt (`config.toml`). **Änderungen
    immer an beiden Stellen.** Weil CI das Dashboard nie sieht, prüft
    `tool/config_drift.sh` beide Prod-Vorlagen täglich — auch darauf, dass
    dort nicht mehr „RideBuddy" steht (bei der Umbenennung übersehen, weil
    Dashboard-Texte in keinem Diff auftauchen).
  Der **E-Mail-Wechsel** bleibt bewusst beim Link: `updateUser` erzeugt
  keinen Verifier, die Bestätigung passiert serverseitig — er ist nicht
  betroffen. Deshalb bleiben `site_url`/`uri_allow_list` nötig.
  Der Rundlauf gegen echtes GoTrue steht in `test/e2e/auth_mail_e2e_test.dart`
  (auch: falscher Code → `otp_expired`); dass die Vorlage keinen Link führt,
  bewacht `firstCode` in `test/e2e/e2e_env.dart` und `mailCode` im
  Browser-E2E. Dasselbe Muster fährt PilzBuddy (pilzbuddy#128).
- **Mehrere Autos je Tag plant der Planer nur, wenn eines nicht reicht**
  (Issue #62). Die Invarianten, in dieser Reihenfolge: `planWeek` bestimmt
  zuerst die **minimale** Autozahl k (die k größten Autos müssen alle
  fassen — ein 7-Sitzer schlägt zwei Kleine), dann entscheiden exakt die
  Punkte, **wer** die k Autos stellt (slotweise die fairness-erste noch
  machbare Teilmenge). Reicht selbst alles zusammen nicht, fahren alle
  Kandidaten — ein Tag ohne Fahrer wäre schlechter als einer mit zu wenig
  Plätzen; diese Rückfalllinie darf nicht wegoptimiert werden. Der
  Fahrer-**Vorschlag** wird nie gespeichert; `plan_overrides` hält eine
  Zeile je von Hand gesetztem Fahrer (PK `group_id, plan_date, driver_id`).
  Die Simulation bucht eine Pseudo-Fahrt **je Auto** — ein Auto ohne
  Mitfahrer ist eine Solo-Fahrt und zählt nichts (#61), genau wie beim
  echten Eintrag. „Eintragen" öffnet den Fahrten-Editor je Auto, fertig
  vorbelegt — gebucht wird erst mit jedem Speichern, nie still; ein
  Abbruch lässt die restlichen Autos ehrlich ungebucht (von Hand
  nachtragen). Sitzplätze speichert `persons.seats` **inklusive Fahrer**
  (Fahrzeugschein), Vorgabe `defaultSeats` = 5 (`not null` in der DB):
  So wirkt die Prüfung ohne Pflegeaufwand; Mitfahrer-Plätze zu speichern
  erzeugte Off-by-one-Fehler, die später niemand mehr erklären kann.
  Festgenagelt in `test/plan_test.dart` und
  `test/flows/plan_flow_test.dart`. Langzeitverhalten (2000-Tage-
  Simulation, `test/plan_soak_test.dart`, Designentscheidung in
  `doc/entscheidung-mitfahrer-verteilung.md`): Punkte konvergieren nur
  **innerhalb** vergleichbarer Autogrößen; bei dauerhaftem Kapazitäts-
  Gefälle driften sie ehrlich, aber unbegrenzt — dokumentierte Grenze,
  keine zu „reparierende" Formel. Auf der realen Zielflotte
  (DaciaRacing-Empirie: 1×4/6×5/1×7 Sitze, große Tage die Ausnahme)
  erfüllt die Automatik Punkte ±2 und Fahrraten im Mittel ±2 pp; der
  Worst-Case ±2,2 pp ist der **Anwesenheits-Boden** (selten Anwesende
  sind eher an großen Tagen dabei und fahren voller), den keine Fahrerwahl
  unterschreiten kann — Zerlegung und Mechanismen-Vergleich im Report. Die Mitfahrer-Verteilung (meiste freie
  Plätze, Gleichstand → bedürftigster Fahrer) bleibt bewusst: Ein
  Anti-Solo-Tie-Break bewegte im A/B-Vergleich eine Fahrt in acht Jahren.
- **1-way im Planer schließt das Fahren aus.** `plan_availability.one_way`
  (Boolean, kein Status-Enum — der Fahrer wird im Plan nie gespeichert) macht
  aus der Verfügbarkeit einen Dreizustand. `planWeek` nimmt 1-way-Personen aus
  den Fahrer-Kandidaten, lässt ein Übersteuern auf sie verfallen und bucht sie
  in der Simulation als `oneWay` — als volle Mitfahrt gebucht rechnete der
  Vorschlag der Folgetage mit doppelten Punkten. Festgenagelt in
  `test/plan_test.dart`.
- **Nichts wird in der Zukunft eingetragen** (entschieden 2026-07-21). Der
  Datumswähler im Fahrten-Editor endet bei heute, der Schnellwahl-Chip heißt
  „Gestern" statt „Morgen", und `_save` bricht bei einem künftigen Datum ab —
  eine ältere Fahrt kann eines tragen. Ein Eintrag im Voraus verschiebt die
  Punkte aller anderen für etwas, das nicht passiert ist; dafür gibt es den
  Wochenplaner. `KONZEPT.md` 5.2 ist an der Stelle überholt und trägt einen
  Korrekturhinweis.
- **Eine eingetragene Fahrt ist im Planer gesperrt** (blass, nicht antippbar)
  und trägt statt „Eintragen" einen andersfarbigen „Bearbeiten"-Knopf, der
  über `PlannedDay.tripId` direkt in den Fahrten-Editor springt. Das Ändern
  einer bestehenden Fahrt fragt nach — es verschiebt die Punkte aller
  Beteiligten rückwirkend.
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
- **Der Planer trimmt die Fahrrate — begrenzt auf ±6 Punkte** (Muster
  entschieden 2026-07-22 mit Deckel 2; auf 6 gehoben 2026-07-24 nach dem
  Zielflotten-Soak, `suggestPlanDriver`): Wer selten fährt, bekommt bei
  fast gleichem Punktestand eher die kleinen Tage, Vielfahrer die vollen —
  so gleichen sich die Fahranteile an. Das ist eine Kaskadenregelung mit
  begrenzter Autorität: reiner P-Regler auf der Raten-Abweichung
  (bewusst **kein** I-Anteil — die Rate ist selbst ein integrierender
  Zustand, ein Integrator darauf schwänge), Verstärkung `kRateBalance = 6`
  ist zugleich der harte Deckel; praktisch bewegt der Trim ~0,2 Punkte,
  weil reale Δ-Raten klein sind. Jenseits des Bandes entscheiden exakt die
  Punkte; Dashboard/„Wer ist dran?" (`rankPresent`) bleiben unberührt.
  Wer den Trim „vereinfacht" (Deckel raus, I-Anteil rein, auch fürs
  Dashboard), bricht den Punkte-Vorrang oder baut Schwingen ein —
  `test/plan_test.dart` nagelt Deckel und Zuordnung fest.
- **Der Wochenplan schreibt optimistisch** (`WeekPlanNotifier` in
  `data/providers.dart`): Ein Tap wird lokal eingerechnet und sofort
  gezeigt, der Netz-Schreib läuft hinterher; scheitert er, holt
  `invalidateSelf` die Server-Wahrheit zurück und der Screen meldet es.
  Wer hier wieder „erst speichern, dann neu laden" einbaut, macht aus
  jedem Tap zwei serielle Roundtrips — genau die Trägheit, die 2026-07-22
  behoben wurde.
- **Push-Benachrichtigungen (Issue #101, seit v0.36.0) — vier Dinge, die
  zusammengehören.** Der Versand entscheidet `tool/notify.dart` auf GitHub
  Actions, nicht eine Edge Function: Der Text nennt, **wer morgen fährt**,
  und das ist eine berechnete Kennzahl. `fairness.dart` und `models/` sind
  reines Dart ohne Flutter-Import, der Job importiert also den echten
  `planWeek`. Wer den Entscheider nach TypeScript verschiebt, baut die
  zweite Wahrheit über die Fairness-Regel — und merkt es nicht, solange
  beide zufällig gleich rechnen. Verschickt wird über
  `supabase/functions/send-push/`, damit das FCM-Dienstkonto bei den
  übrigen Server-Geheimnissen bleibt.
  - **`push_log` speichert einen Hash, keinen Plan.** Es ist ein
    Versand-Gedächtnis, keine zweite Wahrheit über den Tag; der
    vorgeschlagene Fahrer bleibt ungespeichert wie bisher. Der feste Wert
    `removedDigest` ist der Trick am Austrag: Wer raus ist, bekommt genau
    **eine** Nachricht, egal wie oft die anderen den Tag noch umbauen.
    Der Digest hängt bewusst **nicht** an den Punkten — sonst löste jede
    eingetragene Fahrt eines Vortages eine Meldung aus.
  - **Die Personen-Zuordnung eines Geräts ist kein Login.** Jeder kann
    jeden wählen, wie im Planer jeder für jeden einträgt. Sie ist eine
    Zustelladresse; `group_id = auth.uid()` bleibt unangetastet. Das Token
    kommt bei jedem Start frisch von FCM und wird serverseitig
    nachgeschlagen — deshalb schreibt `lib/` weiterhin **nichts** in
    SharedPreferences, und die Begründung der Backup-Regeln bleibt gültig.
  - **`push_devices` hat den Token als Primärschlüssel**, nicht
    `(group_id, token)`. Bewusste Ausnahme von der group_id-Regel: FCM-Token
    sind global eindeutig, und ein Gerät gehört zu genau einer Gruppe —
    beim Wechsel muss die alte Zeile weichen, nicht danebenstehen. Deshalb
    läuft die Registrierung über `register_push_device` (SECURITY DEFINER):
    Die alte Zeile liegt unter fremder `group_id`, die RLS zeigt sie nicht,
    ein blanker Upsert liefe in eine Unique-Verletzung auf einer
    unsichtbaren Zeile. `push_log` hat wie `group_admins` **null Policies**.
  - **Gepollt, nicht getriggert** (entschieden 2026-07-26). Ein Database
    Webhook auf `plan_availability` wäre schneller, feuerte aber mitten in
    der Bearbeitung — fünf Taps sind fünf Aufrufe, und Entprellen heißt
    warten und später nachsehen, also genau das, was der 10-Minuten-Takt
    ohnehin tut. Zudem müsste die Function `planWeek` rechnen. Trigger →
    `pg_net` → GitHub `repository_dispatch` legte ein Repo-Token in die
    Datenbank: **nicht bauen.**
  Push-Texte gehören nie ins Log (sie enthalten Personennamen), und der Job
  loggt nur Zahlen. Festgenagelt in `test/push_digest_test.dart`,
  `test/notify_workflow_test.dart`, `test/schema_test.dart` und
  `test/flows/notifications_flow_test.dart`.
- Kein `print` in `lib/` — zentraler Logger `core/log.dart`.
- **Der Einladungstext darf nie ins Log.** „Jemanden einladen"
  (`features/invite/`) kann auf Wunsch das **Gruppenpasswort** enthalten —
  bewusste Entscheidung, damit eine Einladung ein Schritt bleibt. Deshalb:
  nicht speichern, nicht loggen, und im Fehlerfall **ohne** den Fehlertext
  melden (der trägt sonst die Nachricht mit). Käme der Text in `logRing`,
  stünde der Gruppenzugang im nächsten öffentlichen Feedback-Issue.
  `test/flows/invite_flow_test.dart` prüft genau das am Fehlerpfad.
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
  `test/release_workflow_test.dart` gehört zur selben Klasse: Er hält die
  APK-Namen in `release.yml` zusammen (cp-Ziel, upload-Pfad,
  Release-Dateiliste). Genau daran riss der v0.34.1-Lauf NACH dem Taggen
  ab — übrig blieb ein Tag ohne Release, den die Tag-Entscheidung fortan
  als „schon veröffentlicht" wertete; heilbar nur von Hand (Tag löschen,
  Fix mergen, der Push released neu). Grün in jeder PR-CI heißt bei
  release.yml nichts: Der APK-Pfad läuft nur im echten Release.
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
- **Zum Ausprobieren in der echten App:** `.claude/skills/run-web/SKILL.md`
  (Demo-Build → lokal ausliefern → Playwright). Flutter-Web zeichnet auf
  Canvas, es gibt also keinen DOM-Text — geprüft wird über Screenshots, die
  man sich ansieht. Hat mehrfach Fehler gefunden, die alle Tests durchgelassen
  hatten: den globalen Schlüssel in `plan_overrides`, „Noch niemand verfügbar"
  trotz eingetragener 1-way-Person und einen Datei-Dialog, der an einem alten
  Plugin-Registrant scheiterte. Automatisiert existiert derselbe Ansatz als
  Browser-E2E der Konsole (`tool/browser_e2e.sh`, CI-Job „Browser E2E
  (Konsole)", Details in `doc/testbackend.md`).
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
- Repo: `github.com/MacBuchi/MitFahrBar`, Default-Branch `main`.
  Web-Builds für Pages brauchen `--base-href /MitFahrBar/`
  (Groß-F, case-sensitiv!) und eine `404.html` (Kopie von `index.html`)
  als SPA-Fallback. Live-URL: `https://macbuchi.github.io/MitFahrBar/`
- Echte Namen/Daten der Gruppe liegen NUR in `.donotsync/` (gitignored):
  `Fahrgemeinschaft.xlsx` (Original) und `seed/seed.json` (extrahiert).
  Einmal-Import in eine leere DB: `tool/import_seed.py`. Der Excel-Backtest
  in `test/fairness_test.dart` überspringt sich selbst, wenn `seed.json`
  fehlt (z. B. in CI).
- Status-Werte in der DB: `driver` / `passenger` / `one_way`
  (Dart-Enum `ParticipationStatus.driver/passenger/oneWay`).
- **Android:** Bundle-ID `de.macbuchi.mitfahrbar` — mit v0.34.0 von
  `de.macbuchi.fahrgemeinschaft` umgezogen (Issue #87). Android sieht darin
  eine **andere App**: Die alte bleibt installiert und bekommt nie wieder
  ein Update, jeder installiert einmal neu. Das war die bewusste
  Entscheidung; wer die ID künftig anfasst, löst dasselbe wieder aus.
  Release-Signing kommt
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
- **CSV-Import** (`core/csv_import.dart` = reines Parsen,
  `features/import/import_screen.dart` = Ablauf) liest genau das Format, das
  der Export schreibt; `test/csv_import_test.dart` prüft den **Rundlauf**
  Export → Import. Zwei Regeln sind der eigentliche Inhalt, nicht Komfort:
  Der Import legt **nie** still Personen an — `persons.name` hat keine
  Eindeutigkeit, aus „Bernd"/„Bernnd" würden zwei Personen und das verschiebt
  rückwirkend die Punkte *aller anderen* (Issue #34). Und eine Fahrt, an der
  eine weggelassene Person beteiligt war, wird **ganz** übersprungen statt
  ohne sie angelegt; sonst änderten sich still die Punkte der übrigen an dem
  Tag. Tage mit vorhandener Fahrt bleiben unberührt.
- **Dateiauswahl: `file_selector`, nicht `file_picker`.** Letzteres verlangt
  ab 8.3.3 `win32 ^5.9`, `package_info_plus` aber `win32 ^6` — auflösbar wäre
  nur eine file_picker-Version von 2021. `file_selector` kommt von der
  Flutter-Foundation und deckt Web und Android mit einem Aufruf ab.
- **Die Bedienungsanleitung ist ein Screen** (`features/help/help_screen.dart`,
  Route `/help`, Menüpunkt „So funktioniert MitFahrBar"). Bewusst in Flutter
  statt als externe Seite: Sie erbt Theme und Schriften und zeigt die echten
  Widgets (`MoodFace`, `MitFahrBarMark`) — sie kann nicht wegdriften. Dafür
  gilt die Paar-Regel: **Wer die Bedienung ändert, pflegt die Anleitung mit.**
  `test/flows/help_flow_test.dart` nagelt die Kernaussagen fest, nicht den
  Wortlaut.
- **Feedback** landet in der Tabelle `feedback`; der Bot
  (`tool/feedback_bot.py`, `.github/workflows/feedback.yml`) macht daraus
  Issues. Er ruht, solange `SUPABASE_SERVICE_ROLE_KEY` nicht gesetzt ist.
  Die Issue-Templates unter `.github/ISSUE_TEMPLATE/` und die Felder im
  Feedback-Dialog gehören zusammen — Änderungen immer paarweise.
- **Stimmungs-Gesichter** kommen aus dem Design-Set „MitFahrBar Smiley Set"
  (Claude-Design-Projekt `ae532219-705e-4cdb-becd-cf734e17215a`). Sie sind
  **gezeichnet, nicht eingebunden** (`core/widgets/mood_face.dart`,
  CustomPainter) — dieselbe Linie wie bei den Charts, ein SVG-Renderer nur
  für acht Gesichter wäre eine Dependency zu viel. Die Geometrie steht 1:1
  im Koordinatensystem der Vorlage (viewBox 100×100) und wird erst beim
  Zeichnen skaliert, damit sie mit dem Design vergleichbar bleibt. Die
  Farben in `AppFace` sind aus **oklch** umgerechnet (Flutter kennt oklch
  nicht) — bei einer Änderung im Design-Set neu umrechnen, **nie von Hand
  nachjustieren**, sonst driftet die Skala auseinander. `Mood.celebrating`
  steht bewusst außerhalb der Bewertungsskala und kann von `driveMoodOf`
  nicht zurückgegeben werden; es zeichnet einen Erfolg aus, keine Stufe.
  Seit dem Design-Stand „Animated versions" (2026-07-22) sind die Gesichter
  **animiert**: Die CSS-Keyframes stehen 1:1 als Stützstellen in
  `mood_face.dart` — bei Änderungen im Design-Set neu übernehmen, nicht
  nachempfinden. Bei `disableAnimations` (Systemeinstellung „Bewegung
  reduzieren") ruhen sie; `pumpApp` setzt genau diese Flagge, sonst käme
  kein `pumpAndSettle` je zur Ruhe — wer sie dort entfernt, hängt jeden
  Flow-Test auf.
- **Branding:** `tool/brand/mark.svg` ist die einzige Quelle der Bildmarke.
  `tool/brand/build_icons.sh` (braucht `rsvg-convert` + python3) erzeugt
  daraus Web-Icons (normal + maskable), Favicon und die Android-Mipmaps
  inklusive Adaptive-Icon-Vordergrund. Icons nie von Hand bearbeiten.
  Schrift: Space Grotesk (Display) + Manrope (Body) als Variable Fonts.
- **Die README-Screenshots sind Erzeugnisse, keine Bilder.**
  `tool/screenshots.sh` baut die App im Demo-Modus, fährt sie mit Playwright
  durch und schreibt `doc/screenshots/*.png` — nie von Hand nachbauen oder
  zuschneiden, dieselbe Linie wie bei den Icons. Der Workflow
  „Screenshots" (`.github/workflows/screenshots.yml`) macht das bei jedem
  PR, der `lib/`, `assets/` oder `web/` anfasst, selbst und committet das
  Ergebnis in den Branch. Zwei Dinge daran sind nicht verhandelbar: Der
  Job überspringt sich, wenn die Branch-Spitze schon sein eigener Commit
  ist (`docs: refresh README screenshots`) — der Pfadfilter allein
  genügt dafür **nicht**, weil bei `pull_request` der ganze PR-Diff zählt
  und nicht der neue Commit; ohne den Riegel liefe es im Kreis, sobald
  zwei Läufe verschiedene Bilder erzeugen (im Screenshot steht ein
  Datum). Und nach dem Push muss die CI per `workflow_dispatch`
  angestoßen werden — ein Push mit dem `GITHUB_TOKEN` erzeugt bewusst
  keine Ereignisse, der PR hinge sonst ohne Required Checks fest. Weil die
  Bilder in `doc/` liegen, nimmt der Version Guard `doc/` ausdrücklich aus:
  Ein neuer Screenshot ist kein Release.
  **Der Dispatch-Lauf allein macht den PR aber nicht mergebar** (beobachtet
  am 26.07.2026, PR #103): Der Bot-Push erzeugt zusätzlich `pull_request`-
  Läufe, die auf `action_required` stehen bleiben und nie starten. Deren
  Namen sind die Required Checks, also bleibt der PR `BLOCKED` — obwohl
  `.../commits/<sha>/check-runs` alle sechs grün zeigt, denn das sind die
  des Dispatch-Laufs, und die zählt die Branch Protection nicht.
  Auflösung: die hängenden Läufe freigeben
  (`gh api -X POST repos/<owner>/<repo>/actions/runs/<id>/approve`,
  Kandidaten über `gh run list --branch <branch>` an
  `action_required` erkennbar) — danach laufen sie normal durch und der PR
  wird grün. Ein eigener Push (nicht vom Bot) hat das Problem nicht.
  **Zwei Läufe sind nie bitgleich** — die Stimmungs-Gesichter animieren,
  und jeder Lauf erwischt eine andere Phase (gemessen 5–281 abweichende
  Pixel, die Bounding-Box jedes Mal exakt auf einem Smiley).
  `reducedMotion` im Browser hilft nicht: Flutter-Web reicht
  `prefers-reduced-motion` nicht bis `disableAnimations` durch — der
  Hebel, den `pumpApp` in Tests benutzt, existiert dort nicht. Deshalb
  entscheidet `tool/screenshot_changed.mjs` über einen Pixel-Schwellwert,
  ob der neue Stand überhaupt übernommen wird; ohne ihn committete die CI
  bei jedem Lauf. Wer den Schwellwert anfasst, misst nach (zweimal
  `tool/screenshots.sh` laufen lassen), statt zu schätzen.
  **Der Workflow committet über die Contents-API, nicht mit `git commit`.**
  `main` verlangt signierte Commits (`required_signatures`), und ein
  Commit aus dem Runner trägt keine Signatur — er blockiert den PR mit
  „base branch policy prohibits the merge", obwohl jeder Check grün ist.
  Über die API committet GitHub selbst und signiert dabei. Das kostet
  einen Commit je Datei; beim Squash-Merge bleibt ohnehin einer übrig.
  Dieselbe Falle trifft jeden künftigen Workflow, der etwas ins Repo
  zurückschreibt. Und der Payload geht per `--input` über stdin, **nie
  als Argument**: Linux deckelt ein einzelnes Argument bei 128 KB —
  das Base64 einer PNG über ~96 KB riss den Lauf mitten in der Schleife
  ab (25.07.2026), zurück blieben ein halb committeter Bildersatz und
  ein PR ohne Checks auf dem neuen Head, weil auch der CI-Dispatch
  danach nie lief.
  Die Bildinhalte hängen an Koordinaten im 430×900-Viewport — verschiebt
  sich das Layout, zeigen die Bilder im PR sofort das Falsche.
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
- **Der Release-Body ist der CHANGELOG-Auszug der Version** (seit v0.21.0).
  Die App zeigt ihn wortwörtlich unter „Was ist neu" im Update-Dialog —
  auto-generierte englische PR-Titel standen sonst roh vor der Gruppe.
  Fehlt der Abschnitt, setzt der Workflow einen Link statt Leere; die
  Anzeige glättet Markdown-Reste über `core/release_notes.dart`
  (`test/release_notes_test.dart`). Keine zweite Notes-Quelle einführen.
- **Der Start-Splash** (`features/splash/splash_overlay.dart`) liegt im
  `builder` der MaterialApp über allem und zeichnet die Bildmarke über
  `paintMitFahrBarMark` + `MitFahrBarPose` — Geometrie nur in
  `core/widgets/mitfahrbar_mark.dart`, die Animation ist reine
  Choreografie. Tipp überspringt, `disableAnimations` unterbindet ihn,
  und in Tests ist er über `splashEnabledProvider` standardmäßig aus
  (`pumpApp(splash: …)`) — sonst wartete jeder Flow-Test 3 Sekunden.
- **Config-Drift-Wache** (`.github/workflows/config-drift.yml` +
  `tool/config_drift.sh`, Issue #70): prüft täglich die Prod-Auth-Config
  über die Management-API gegen die Erwartungen des Codes (Bestätigungs-
  pflicht, Brevo-SMTP, Signup offen). Grund: Dashboard-Klicks sind für
  Repo und Teststack unsichtbar — genau so brach am 23.07.2026 die
  Gruppen-Registrierung. Bewusst NUR lesend: nie `supabase config push`
  einbauen, der könnte die Brevo-SMTP-Zugangsdaten im Dashboard
  überschreiben. Braucht das Repo-Secret `SUPABASE_ACCESS_TOKEN`
  (PAT, läuft jährlich ab — roter Lauf heißt auch: Token erneuern).
  Ändert sich eine Einstellung ABSICHTLICH, gehören Skript-Erwartung
  und Code-Abhängigkeiten im selben PR nachgezogen.
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

# Fahrgemeinschaft — Arbeitsregeln

Flutter-Web-App (PWA) zur Verwaltung einer Fahrgemeinschaft: Fahrtenprotokoll,
Punkte-/Fairness-System („wer ist dran"), Statistik. Supabase-Backend
(ein Gruppenlogin, RLS in `supabase/schema.sql`), Riverpod ohne Codegen,
go_router, deutsche UI-Strings direkt im Code. Fachkonzept: `KONZEPT.md`.

## Architektur-Leitplanken (nicht verhandelbar)

- 3 Schichten: `core/` (router, theme, tokens, fairness, log) · `data/`
  (Repositories + `providers.dart`-Registry) · `models/` · `features/<name>/`.
- Die Fairness-/Punktelogik lebt NUR in `lib/core/fairness.dart` und ist durch
  `test/fairness_test.dart` inkl. Excel-Backtest abgesichert. Änderungen an der
  Formel brauchen angepasste Tests UND einen Abgleich mit `KONZEPT.md` 3.2.
- Kennzahlen (Punkte, Quote, km, Ersparnis) werden immer berechnet, nie
  gespeichert.
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
- Kein `print` in `lib/` — zentraler Logger `core/log.dart`.
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

## Workflow

- **Kein direkter Push auf `main`** (Branch ist geschützt): Feature-Branch
  (`feat/<thema>` / `fix/<thema>`) → PR → CI grün → Squash-Merge. **Der Merge
  gehört dem Menschen** — er veröffentlicht (Auto-Release).
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
- **Feedback** landet in der Tabelle `feedback`; der Bot
  (`tool/feedback_bot.py`, `.github/workflows/feedback.yml`) macht daraus
  Issues. Er ruht, solange `SUPABASE_SERVICE_ROLE_KEY` nicht gesetzt ist.

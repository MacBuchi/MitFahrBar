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
- Kein `print` in `lib/` — zentraler Logger `core/log.dart`.
- Nach jedem `await` in Widgets `mounted`/`context.mounted` prüfen.
- Server-/App-State in Riverpod-Providern, Formular-State in StatefulWidgets.

## Workflow

- Kein direkter Push auf `main`: Feature-Branch (`feat/<thema>` /
  `fix/<thema>`) → PR → CI grün → Squash-Merge.
- Commit-/PR-Titel: Conventional Commits. GitHub-Kommunikation Englisch,
  UI-Strings und Nutzer-Doku Deutsch.
- Release = Versions-Bump in `pubspec.yaml` auf `main` (beide Teile erhöhen,
  z. B. `0.2.0+3`). Der Release-Workflow taggt `v<version>` und deployt Web
  auf GitHub Pages. Kein Bump = kein Release.
- Version Guard in CI: Code-Änderung ohne Versions-Bump blockiert den Merge
  (nur `*.md` und `.github/` sind ausgenommen).
- Flutter-Version in CI gepinnt (3.41.2) — bei lokalem Upgrade auch
  `.github/workflows/*.yml` anpassen. Lokales SDK:
  `/Volumes/MacStore/Programming/Flutter/SDK/flutter`.

## Technik-Notizen

- Supabase-Zugang: `lib/core/supabase_config.dart`. Solange dort Platzhalter
  stehen, läuft die App im Demo-Modus (In-Memory-Daten, kein Login). Der
  Publishable-Key ist bewusst öffentlich; NIEMALS den service_role-Key
  einchecken.
- DB-Änderungen: `supabase/schema.sql` aktuell halten (Frischinstallation)
  UND als nummeriertes `supabase/patch_NNN_*.sql` ablegen.
- Web-Builds für Pages brauchen `--base-href /<repo-name>/` und eine
  `404.html` (Kopie von `index.html`) als SPA-Fallback.
- Echte Namen/Daten der Gruppe liegen NUR in `.donotsync/` (gitignored):
  `Fahrgemeinschaft.xlsx` (Original) und `seed/seed.json` (extrahiert).
  Einmal-Import in eine leere DB: `tool/import_seed.py`. Der Excel-Backtest
  in `test/fairness_test.dart` überspringt sich selbst, wenn `seed.json`
  fehlt (z. B. in CI).
- Status-Werte in der DB: `driver` / `passenger` / `one_way`
  (Dart-Enum `ParticipationStatus.driver/passenger/oneWay`).

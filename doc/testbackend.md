# Testbackend: echter Supabase-Stack für automatisierte E2E-Tests

Production ist das einzige Cloud-Projekt — getestet wird deshalb gegen den
**lokalen Supabase-CLI-Stack** (Docker): echtes Postgres mit echter RLS,
echtes GoTrue mit echten Auth-Mails. Mailpit fängt jede Mail ab, die der
Stack verschickt — Passwort-Workflows sind damit komplett ohne Brevo
automatisiert prüfbar.

Drei Betriebsarten, ein und dieselbe Suite (`test/e2e/`):

| Wo | Wozu | Start |
| --- | --- | --- |
| Mac (lokal) | Entwicklung, schnelle Iteration | `tool/e2e.sh` |
| CI (GitHub Actions) | jeder PR, automatisch | Job „E2E (Supabase-Stack)" |
| Proxmox-VM `ridebuddy-test` | auf Abruf (Default: gestoppt), Handy-Browser-Tests | `tool/e2e_vm.sh` |

## Die E2E-Suite (`test/e2e/`)

Ohne gesetzte `E2E_*`-Variablen **überspringen sich alle E2E-Tests selbst**
(gleiches Muster wie der Excel-Backtest) — `flutter test` bleibt ohne
Docker grün, auch im CI-Job „Analyze & Test".

Abgedeckt ist, was die In-Memory-Fakes nur nachbilden können:

- **Mandantentrennung** (`rls_e2e_test.dart`): Signup-Trigger inkl.
  Default-Settings (`points_weight = 1.0`), pending-Sperre, Isolation
  zweier Gruppen, nur-lesbare `app_config`, `group_id` in den
  Planer-Schlüsseln (v0.15.0-Fix) — alles gegen echte Policies. Seit #108
  auch: eine pending-Gruppe kann sich **nicht selbst freischalten**
  (`groups` hat keine Update-Policy mehr) — sonst wäre jeder Fremd-Signup
  gegen die Gruppen-Domain eine Gruppe, die sich selbst aktiviert, und die
  Statuswerte als Riegel wertlos.
- **Verwalter-Konsole** (`admin_console_e2e_test.dart`): kein
  Geister-pending beim Admin-Signup; Anlegen nur als bestätigtes
  Verwalter-Konto (anonym → 401, Gruppen-Login → 403) und dann **aktiv und
  verknüpft in einem Zug**; der Deckel von fünf Gruppen (die sechste → 429,
  ohne den Handle zu verbrennen); Übernehmen nur mit Gruppen-Login und
  Einrasten; eine fremde `target_group` prallt mit `not linked` ab;
  Gruppenpasswort-Reset wirkt; `released_at` wird beim Lösen gesetzt und beim
  Übernehmen geleert; Löschen reißt die Gruppe über die Auth-Kaskade mit —
  aber nie das Verwalter-Konto. Am Ende der Suite steht die Messung von
  **Invariante 1**: Jede aktive Gruppe hat einen Verwalter **oder** ein
  markiertes Übergabefenster (`released_at`). Bewusst nicht „ist verknüpft" —
  nach `admin_release_group` ist eine Gruppe legitim ohne Verwalter, und der
  Zeitstempel ist genau der Unterschied zur echten Waise.
- **Push-Registrierung** (`push_e2e_test.dart`): `register_push_device`
  ordnet nur eigene Personen zu, ein Gerät gehört immer genau **einer**
  Gruppe (die alte Zeile weicht — im Fake per Konstruktion unsichtbar),
  fremde Gruppen sehen weder Geräte noch Einstellungen, das Konfliktziel
  der `notification_prefs` passt zum Schlüssel, `push_log` ist für Clients
  unerreichbar, und eine Gruppe, die nicht `active` ist, registriert gar
  nichts.
- **Auth-Workflows mit echten Mails** (`auth_mail_e2e_test.dart`): Der
  Stack läuft wie Production mit **Bestätigungspflicht**
  (`enable_confirmations = true` in config.toml). Festgenagelt sind:
  Gruppen-Anlage über die Edge Function `request-group` (keine Mail an die
  Fake-Adresse, sofort anmeldbar, Gruppe aktiv), Admin-Signup verlangt den
  Mail-Code wirklich, Recovery-Mail kommt an und der Code ist einlösbar. Der lokale Stack serviert die Functions aus
  `supabase/functions/` automatisch mit.

Der Service-Role-Key dient in der Suite nur zum Arrangieren/Prüfen
(Gruppe freischalten, Kaskade nachsehen) — nie, um App-Verhalten
nachzustellen.

## Lokal auf dem Mac

Voraussetzungen: Docker (Desktop) und die Supabase-CLI
(`brew install supabase/tap/supabase`; Version passend zur CI-gepinnten,
siehe `.github/workflows/ci.yml`).

```bash
tool/e2e.sh                      # Stack starten, DB frisch, Suite fahren
tool/e2e.sh --name "claim"       # Argumente gehen an flutter test durch
```

Der Stack nutzt bewusst die Ports **5532x** (statt 5432x), damit er neben
dem Stack einer anderen App laufen kann:

- API `http://127.0.0.1:55321` · Studio `http://127.0.0.1:55323`
- Mailpit (alle Auth-Mails) `http://127.0.0.1:55324`

Manuell erkunden: Demo-Build und Testbackend-Build gehen ohne Patchen der
Quellen über `--dart-define` (siehe `.claude/skills/run-web/SKILL.md`):

```bash
flutter build web \
  --dart-define=SUPABASE_URL=http://127.0.0.1:55321 \
  --dart-define=SUPABASE_KEY=<ANON_KEY aus `supabase status`>
```

Aufräumen: `supabase stop` (Daten bleiben), nächster `tool/e2e.sh` setzt
ohnehin frisch auf.

## CI

Der Job **„E2E (Supabase-Stack)"** in `ci.yml` startet den Stack im Runner
(Docker ist vorinstalliert), spielt alle Migrationen ein und fährt die
Suite — bei jedem PR. Die CLI-Version ist dort **gepinnt** wie Flutter:
Ein CLI-Upgrade ändert den lokalen Stack (Ports/Sektionen in
`supabase/config.toml`) und wird zusammen mit einem lokalen Upgrade
getestet, nie nebenbei.

## Proxmox-VM `ridebuddy-test` (VM 120) — auf Abruf

Testbackend im LAN für Tests vom Handy-Browser aus und Suite-Läufe ohne
lokalen Docker. **Die VM ist standardmäßig gestoppt** (der Host ist
RAM-knapp — eine dauerlaufende VM wurde vom Ballooning erdrückt, siehe
Fundstücke): Sie fährt nur für einen Testlauf hoch, holt sich davor den
aktuellen Git-Stand und eine frische Datenbank und fährt danach wieder
herunter. IP/Zugang stehen bewusst nicht hier (öffentliches Repo),
sondern in der lokalen Secrets-Ablage.

Der ganze Zyklus ist ein Befehl (Umgebungsvariablen: siehe Skript-Kopf
bzw. Secrets-Ablage):

```bash
tool/e2e_vm.sh                  # VM hoch → pull + db reset → Suite → VM aus
RIDEBUDDY_VM_KEEP=1 tool/e2e_vm.sh   # VM anlassen, z. B. für Handy-Tests
```

Aufbau (einmalig, so wurde sie erstellt): Ubuntu 24.04 Cloud-Image,
2,5 GB RAM (Ballooning bewusst aus) + 2 GB Swap, Docker + Supabase-CLI
(gleiche Version wie CI), Repo-Klon in `~/Fahrgemeinschaft`, systemd-Unit
`supabase-stack.service` zieht den Stack bei jedem VM-Start automatisch
hoch. Die Keys des Stacks sind die bekannten Demo-Keys, keine
Geheimnisse.

Web-App fürs Handy: Build wie oben mit `SUPABASE_URL=http://<vm-ip>:55321`,
per `python3 -m http.server 8731` ausliefern (Mac oder VM) und im
Handy-Browser öffnen. Läuft alles über HTTP im LAN — kein
Mixed-Content-Problem. Die **native Android-APK** kann das Testbackend
nicht erreichen (Android blockt Klartext-HTTP); dafür bräuchte es TLS,
bewusst außerhalb des Umfangs.

## Fundstücke, die das Setup schon bezahlt haben

- **Explizite Grants nötig** (`20260723090000_explicit_client_grants.sql`):
  Neuere Stacks sind „secure by default" — ohne explizite Grants haben
  `anon`/`authenticated`/`service_role` weder DML noch EXECUTE, die App
  fände auf jedem frischen Stack keine Tabelle vor. Production lief nur,
  weil das Cloud-Projekt noch die klassischen impliziten Grants trägt.
  Sicherheit liegt unverändert allein in den RLS-Policies.
- **Autoconfirm vs. Bestätigungsmail** (historisch, bis v0.26.x): Mit
  Autoconfirm verschickt Supabase **keine** Registrierungs-Bestätigung —
  auch nicht für Verwalter-Konten. Beim Brevo-Setup (23.07.2026) wurde in
  Production die Bestätigungspflicht eingeschaltet; der Teststack lief
  aber weiter mit Autoconfirm und konnte den Drift nicht sehen — so blieb
  unbemerkt, dass „Neue Gruppe anfragen" in Production an einer nie
  zustellbaren Bestätigungsmail hängen geblieben wäre. Deshalb entstehen
  Gruppen-Konten seit v0.27.0 serverseitig (`request-group`), der Stack
  läuft mit Bestätigungspflicht, und `auth_mail_e2e_test.dart` nagelt
  beides fest.
- **Auto-Ballooning erdrückt den Stack**: Auf einem RAM-knappen Host
  schrumpft Proxmox laufende VMs Richtung Balloon-Minimum — die Test-VM
  wurde bei laufendem `db reset` auf ~1,2 GB gedrückt und war nur noch
  per Ping erreichbar. Deshalb: Ballooning für die Test-VM aus, 2 GB
  Swap als Puffer, und die VM läuft grundsätzlich nur auf Abruf.

## Browser-E2E (Issue #71)

`tool/browser_e2e.sh` schließt die letzte Naht: Playwright fährt die
**echte Web-App im echten Browser** gegen den Stack — Verwalter-Konto
registrieren, den Code aus der Mailpit-Mail in die App tippen (`verifyOTP`
liefert die Sitzung gleich mit), Gruppe verknüpfen, Zustand serverseitig
gegenprüfen. Der Code statt eines Links seit Issue #102: `mailCode()`
schlägt fehl, sobald die Mail wieder einen `auth/v1/verify`-Link führt —
der wäre an das anfordernde Gerät gebunden. Flutter-Web zeichnet auf
Canvas: Bedient wird über Koordinaten bei fixiertem Viewport (in
`tool/browser_e2e/console.mjs` dokumentiert), geprüft über
Semantics-Labels und Screenshots (`tool/browser_e2e/shots/`, in CI als
Artifact). Ändert sich das Layout der Konsolen-Screens, gehören die
Koordinaten nachgezogen — der CI-Job „Browser E2E (Konsole)" ist genau
deshalb bewusst kein Required Check.

## Grenzen

- Brevo/Prod-SMTP wird hier nicht geprüft — der Stack beweist den Weg
  „App → GoTrue → SMTP → Postfach → Code"; ob Brevo in Production
  zustellt, ist reine Dashboard-Konfiguration.
- Die **Prod-Mail-Vorlagen** sieht der Stack ebenfalls nicht: `config.toml`
  verdrahtet die versionierten Kopien aus `supabase/templates/`, wirksam
  sind aber die im Dashboard. Driften sie auseinander, bleibt die Suite
  grün und Production ist kaputt — dagegen läuft `tool/config_drift.sh`
  täglich gegen die Management-API.
- Android-native Pfade (Teilen, Dateiauswahl, In-App-Update) brauchen
  weiterhin ein Gerät (siehe run-web-Skill, „Was hier nicht geht").

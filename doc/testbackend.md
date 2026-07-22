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
| Proxmox-VM `ridebuddy-test` | dauerhaft an, Handy-Browser-Tests | Suite per `E2E_*`-Variablen dagegen fahren |

## Die E2E-Suite (`test/e2e/`)

Ohne gesetzte `E2E_*`-Variablen **überspringen sich alle E2E-Tests selbst**
(gleiches Muster wie der Excel-Backtest) — `flutter test` bleibt ohne
Docker grün, auch im CI-Job „Analyze & Test".

Abgedeckt ist, was die In-Memory-Fakes nur nachbilden können:

- **Mandantentrennung** (`rls_e2e_test.dart`): Signup-Trigger inkl.
  Default-Settings (`points_weight = 1.0`), pending-Sperre, Isolation
  zweier Gruppen, nur-lesbare `app_config`, `group_id` in den
  Planer-Schlüsseln (v0.15.0-Fix) — alles gegen echte Policies.
- **Verwalter-Konsole** (`admin_console_e2e_test.dart`): kein
  Geister-pending beim Admin-Signup, Verknüpfung nur mit Gruppen-Login,
  Einrasten, Gruppenpasswort-Reset wirkt, Löschen reißt über die
  Auth-Kaskade alles mit.
- **Passwort-Workflows mit echten Mails** (`auth_mail_e2e_test.dart`):
  Recovery-Mail kommt in Mailpit an, der Link ist einlösbar, und
  Gruppen-Signups verschicken KEINE Mail (Autoconfirm — die
  Produktions-Einstellung, festgenagelt samt Begründung im Test).

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

## Proxmox-VM `ridebuddy-test` (VM 120)

Dauerhaft laufendes Testbackend im LAN — für Tests vom Handy-Browser aus
und als Ziel für Suite-Läufe ohne lokalen Docker. IP/Zugang stehen bewusst
nicht hier (öffentliches Repo), sondern in der lokalen Secrets-Ablage.

Aufbau (einmalig, so wurde sie erstellt): Ubuntu 24.04 Cloud-Image,
Docker + Supabase-CLI (gleiche Version wie CI), Repo-Klon, systemd-Unit
`supabase-stack.service` startet den Stack beim Boot (`--onboot 1`).

Suite von einem Entwicklungsrechner gegen die VM:

```bash
E2E_SUPABASE_URL=http://<vm-ip>:55321 \
E2E_SUPABASE_ANON_KEY=<ANON_KEY> \
E2E_SUPABASE_SERVICE_KEY=<SERVICE_ROLE_KEY> \
E2E_MAILPIT_URL=http://<vm-ip>:55324 \
tool/e2e.sh
```

(Die Keys zeigt `supabase status` auf der VM; es sind die bekannten
Demo-Keys des lokalen Stacks, keine Geheimnisse.)

Schema aktualisieren bzw. frisch aufsetzen — auf der VM:

```bash
cd ~/Fahrgemeinschaft && git pull && supabase db reset
```

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
- **Autoconfirm vs. Bestätigungsmail**: Mit Autoconfirm (Prod-Einstellung,
  nötig für die Fake-Gruppen-Adressen) verschickt Supabase **keine**
  Registrierungs-Bestätigung — auch nicht für Verwalter-Konten. Wer im
  Brevo-Log auf eine Signup-Mail wartet, wartet vergeblich; nur
  Passwort-Reset-Mails werden verschickt. Festgenagelt in
  `auth_mail_e2e_test.dart`.

## Grenzen

- Brevo/Prod-SMTP wird hier nicht geprüft — der Stack beweist den Weg
  „App → GoTrue → SMTP → Postfach → Link"; ob Brevo in Production
  zustellt, ist reine Dashboard-Konfiguration.
- Android-native Pfade (Teilen, Dateiauswahl, In-App-Update) brauchen
  weiterhin ein Gerät (siehe run-web-Skill, „Was hier nicht geht").

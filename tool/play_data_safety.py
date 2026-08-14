#!/usr/bin/env python3
"""play_data_safety.py – füllt Googles Data-Safety-Formular aus `doc/play-console.md`.

Die Play Console importiert die Antworten als CSV (App-Inhalte →
Datensicherheit → „Aus CSV importieren"). Dieses Werkzeug nimmt Googles
offizielle Muster-CSV (`doc/store/data_safety_template.csv`, aus der
Play-Console-Hilfe) und trägt unsere Antworten ein. Ergebnis:
`doc/store/data_safety.csv`, fertig zum Hochladen.

Damit ist das größte Formular der Console kein Abtippen von rund 60 Fragen
mehr, sondern ein Upload plus Sichtprüfung. Muster von PilzBuddy (dort
`tool/play_data_safety.py`).

**Die inhaltliche Wahrheit bleibt `doc/play-console.md`.** Die Tabelle hier
ist wörtlich von dort übernommen, inklusive der Ermessensfragen (Feedback
ist „geteilt", weil daraus öffentliche GitHub-Issues werden; das FCM-Token
ist erhoben UND geteilt). Wer eine Antwort ändert, ändert beide Stellen im
selben Commit — sonst weiß beim nächsten Dependency-Wechsel niemand mehr,
warum in der Console steht, was dort steht.

Drei Wächter gegen die naheliegenden Fehler:

* **Jeder Antwort-Schlüssel MUSS in der Vorlage existieren.** Eine
  vertippte oder von Google umbenannte ID bricht den Lauf, statt still eine
  Zeile ins Leere zu schreiben — man merkte es sonst erst daran, dass die
  Console eine Angabe vermisst, die man gemacht zu haben glaubt.
* **Die Beispielantworten der Vorlage werden gelöscht.** Googles Muster ist
  NICHT leer: Es beschreibt eine erfundene App mit 15 gesetzten Werten,
  darunter „ungefährer Standort, geteilt, für Werbung". Unverändert
  hochgeladen deklariert man genau das.
* **`--check` läuft in der CI** und hält die eingecheckte Ausgabe mit
  Vorlage + Antworten zusammen. Wer die CSV von Hand ändert, macht CI rot.

⚠️ **Groß-/Kleinschreibung folgt der Vorlage, nicht der Gewohnheit.** Googles
aktuelles Muster schreibt `true`/`false` klein; das ältere, mit dem PilzBuddy
arbeitet, schrieb `TRUE`/`FALSE` groß. Wird die Vorlage erneuert, ist das
mitzuziehen — es steht deshalb hier als eine Konstante und nicht verstreut.

Nutzung:
  python3 tool/play_data_safety.py            # schreibt doc/store/data_safety.csv
  python3 tool/play_data_safety.py --check    # CI-Wächter
"""

from __future__ import annotations

import csv
import io
import sys

TEMPLATE = "doc/store/data_safety_template.csv"
OUTPUT = "doc/store/data_safety.csv"

# Siehe Kopfkommentar: die Schreibweise stammt aus der Vorlage.
TRUE, FALSE = "true", "false"

# Beide Seiten sind live, seit 0.83.0 befördert wurde — Play prüft die URL,
# nicht das Repository (doc/play-console.md, „gebaut ist nicht ausgeliefert").
LOESCH_URL = "https://macbuchi.github.io/MitFahrBar/konto-loeschen.html"

# ---------------------------------------------------------------------------
# Die Antworten. Schlüssel: (Frage-ID, Antwort-ID) — exakt wie in der Vorlage.
# Alles, was hier nicht steht, bleibt leer; die Vorlage kennt keine
# „Nein"-Kästchen, ein nicht angekreuztes Feld IST die Verneinung.
# ---------------------------------------------------------------------------

ANSWERS: dict[tuple[str, str], str] = {
    # --- Vorfragen (doc/play-console.md, „Vorfragen") ----------------------
    ("PSL_DATA_COLLECTION_COLLECTS_PERSONAL_DATA", ""): TRUE,
    # Alle Endpunkte sind HTTPS; kein http:// im Code.
    ("PSL_DATA_COLLECTION_ENCRYPTED_IN_TRANSIT", ""): TRUE,
    # Gruppen-Login ist Handle + Passwort, Verwalter E-Mail + Passwort —
    # beides „Nutzer-ID und Passwort". Kein OAuth, kein Fremdkonto.
    ("PSL_SUPPORTED_ACCOUNT_CREATION_METHODS", "PSL_ACM_USER_ID_PASSWORD"): TRUE,
    ("PSL_ACCOUNT_DELETION_URL", ""): LOESCH_URL,
    ("PSL_SUPPORT_DATA_DELETION_BY_USER", "DATA_DELETION_YES"): TRUE,
    ("PSL_DATA_DELETION_URL", ""): LOESCH_URL,
    # Hier standen bis zum 14.08.2026 zwei ausdrückliche Neins:
    # `PSL_INDEPENDENTLY_VALIDATED` und `PSL_HAS_OUTSIDE_APP_ACCOUNTS`. Die
    # Console hat den Import abgelehnt — „Du kannst
    # PSL_HAS_OUTSIDE_APP_ACCOUNTS nicht beantworten". Beide tragen in der
    # Vorlage `OPTIONAL`, und das heißt dort nicht „darfst du weglassen",
    # sondern „wird nur unter Bedingungen überhaupt gestellt": Die Frage nach
    # Fremdkonten hängt an der Kontoerstellung, und wer nur „Nutzer-ID und
    # Passwort" ankreuzt, bekommt sie nie zu sehen. Eine Antwort auf eine
    # nicht gestellte Frage ist ein Fehler, kein zusätzliches Nein. Der
    # Riegel dagegen steht in `render()`.
    # --- Welche Datentypen -------------------------------------------------
    ("PSL_DATA_TYPES_PERSONAL", "PSL_NAME"): TRUE,
    ("PSL_DATA_TYPES_PERSONAL", "PSL_EMAIL"): TRUE,
    # Heißt in der Console „Nutzer-IDs": die Kennung des Gruppen-Kontos
    # (auth.uid) und die Personen-ID, an der das Push-Token hängt.
    ("PSL_DATA_TYPES_PERSONAL", "PSL_USER_ACCOUNT"): TRUE,
    ("PSL_DATA_TYPES_APP_ACTIVITY", "PSL_USER_GENERATED_CONTENT"): TRUE,
    ("PSL_DATA_TYPES_APP_PERFORMANCE", "PSL_CRASH_LOGS"): TRUE,
    ("PSL_DATA_TYPES_IDENTIFIERS", "PSL_DEVICE_ID"): TRUE,
    # **Standort in KEINER Form** — anders als bei PilzBuddy, und der Grund,
    # warum diese Tabelle nicht von dort abgeleitet wurde: MitFahrBar
    # deklariert keine Standort-Berechtigung und hat keinen Kartencode. Die
    # Fahrtdaten sind Datum, Teilnehmer und die Kilometerzahl des Arbeitswegs
    # als Parameter — nie eine Koordinate, nie eine Route.
}

# Je erhobenem Typ: geteilt?, Pflicht?, Zwecke der Erhebung, Zwecke der
# Weitergabe. „Kurzzeitig verarbeitet" ist überall FALSE — alles liegt in
# PostgreSQL, nichts nur für die Dauer einer Sitzung.
USAGE: dict[str, dict] = {
    # persons.name — die Mitglieder, von der Gruppe selbst eingetragen.
    "PSL_NAME": dict(
        shared=False, required=True, purposes=["PSL_APP_FUNCTIONALITY"]
    ),
    # Nur Verwalter-Konten haben eine echte Adresse; der Gruppen-Login ist
    # handle@grp.fahrgemeinschaft.app — eine synthetische Adresse ohne
    # Postfach. Brevo ist Auftragsverarbeiter, also kein „geteilt".
    "PSL_EMAIL": dict(
        shared=False, required=True, purposes=["PSL_ACCOUNT_MANAGEMENT"]
    ),
    "PSL_USER_ACCOUNT": dict(
        shared=False,
        required=True,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_ACCOUNT_MANAGEMENT"],
    ),
    # error_reports.
    "PSL_CRASH_LOGS": dict(
        shared=False, required=True, purposes=["PSL_APP_FUNCTIONALITY"]
    ),
    # Anmerkungen am Plantag UND der Feedback-Text. **Geteilt**, weil der
    # Feedback-Bot daraus öffentliche GitHub-Issues macht — außerhalb der
    # Kontrolle des Nutzers und unwiderruflich. Optional, weil beides
    # freiwillig ist.
    "PSL_USER_GENERATED_CONTENT": dict(
        shared=True,
        required=False,
        purposes=["PSL_APP_FUNCTIONALITY", "PSL_DEVELOPER_COMMUNICATIONS"],
        share_purposes=["PSL_DEVELOPER_COMMUNICATIONS"],
    ),
    # push_devices.token. **Geteilt**, weil Google die Kennung selbst erzeugt
    # und ohne Weitergabe keine Meldung zugestellt werden kann. Optional,
    # weil Benachrichtigungen ab Werk aus sind.
    "PSL_DEVICE_ID": dict(
        shared=True,
        required=False,
        purposes=["PSL_APP_FUNCTIONALITY"],
        share_purposes=["PSL_APP_FUNCTIONALITY"],
    ),
}

_PREFIX = "PSL_DATA_USAGE_RESPONSES"


def _usage_answers() -> dict[tuple[str, str], str]:
    answers: dict[tuple[str, str], str] = {}
    for dtype, use in USAGE.items():
        base = f"{_PREFIX}:{dtype}"
        answers[
            (
                f"{base}:PSL_DATA_USAGE_COLLECTION_AND_SHARING",
                "PSL_DATA_USAGE_ONLY_COLLECTED",
            )
        ] = TRUE
        if use["shared"]:
            answers[
                (
                    f"{base}:PSL_DATA_USAGE_COLLECTION_AND_SHARING",
                    "PSL_DATA_USAGE_ONLY_SHARED",
                )
            ] = TRUE
        answers[(f"{base}:PSL_DATA_USAGE_EPHEMERAL", "")] = FALSE
        control = (
            "PSL_DATA_USAGE_USER_CONTROL_REQUIRED"
            if use["required"]
            else "PSL_DATA_USAGE_USER_CONTROL_OPTIONAL"
        )
        answers[(f"{base}:DATA_USAGE_USER_CONTROL", control)] = TRUE
        for purpose in use["purposes"]:
            answers[(f"{base}:DATA_USAGE_COLLECTION_PURPOSE", purpose)] = TRUE
        for purpose in use.get("share_purposes", []):
            answers[(f"{base}:DATA_USAGE_SHARING_PURPOSE", purpose)] = TRUE
    return answers


def render() -> str:
    answers = dict(ANSWERS)
    answers.update(_usage_answers())

    with open(TEMPLATE, newline="", encoding="utf-8-sig") as handle:
        rows = list(csv.reader(handle))

    known = {(row[0], row[1]) for row in rows[1:] if row}
    unknown = sorted(key for key in answers if key not in known)
    if unknown:
        raise SystemExit(
            "Diese Antwort-IDs stehen nicht in der Vorlage — vertippt, oder "
            f"Google hat das Formular geändert: {unknown}"
        )

    # `OPTIONAL` heißt in dieser Vorlage nicht „darfst du weglassen", sondern
    # „stellt die Console nur unter Bedingungen". Wer so eine Frage trotzdem
    # beantwortet, bekommt beim Import „Du kannst <ID> nicht beantworten" —
    # und zwar erst dort, nach dem Hochladen. Hier ist es eine Zeile Ausgabe.
    requirement = {(row[0], row[1]): row[3] for row in rows[1:] if row}
    gated = sorted(key for key in answers if requirement[key] == "OPTIONAL")
    if gated:
        raise SystemExit(
            "Diese Fragen sind in der Vorlage OPTIONAL, werden also nur unter "
            "Bedingungen gestellt — eine Antwort darauf lehnt die Console ab: "
            f"{gated}"
        )

    used = set()
    for row in rows[1:]:
        if not row:
            continue
        key = (row[0], row[1])
        if key in answers:
            row[2] = answers[key]
            used.add(key)
        else:
            # Löscht auch Googles Beispielantworten — siehe Kopfkommentar.
            row[2] = ""
    assert used == set(answers)

    out = io.StringIO()
    csv.writer(out, lineterminator="\n").writerows(rows)
    return out.getvalue()


def main() -> None:
    content = render()
    filled = sum(1 for row in content.splitlines() if f",{TRUE}," in row or f",{FALSE}," in row)
    if "--check" in sys.argv:
        try:
            with open(OUTPUT, newline="", encoding="utf-8") as handle:
                current = handle.read()
        except FileNotFoundError:
            raise SystemExit(
                f"{OUTPUT} fehlt — python3 tool/play_data_safety.py"
            ) from None
        if current != content:
            raise SystemExit(
                f"{OUTPUT} passt nicht zu Vorlage + Antworten. Nicht die CSV "
                "editieren — die Antwort-Tabelle in tool/play_data_safety.py "
                "ändern (und doc/play-console.md im selben Commit), dann neu "
                "erzeugen."
            )
        print(f"data_safety.csv: deckungsgleich ({filled} gesetzte Antworten)")
        return

    with open(OUTPUT, "w", newline="", encoding="utf-8") as handle:
        handle.write(content)
    print(f"{OUTPUT}: {filled} Antworten gesetzt")


if __name__ == "__main__":
    main()

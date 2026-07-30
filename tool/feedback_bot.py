#!/usr/bin/env python3
"""Macht aus In-App-Feedback GitHub-Issues.

Liest unverarbeitete Zeilen aus der Supabase-Tabelle `feedback`, legt je
Eintrag ein gelabeltes Issue an und stempelt `processed_at`. Nur
Python-Stdlib plus die `gh`-CLI.

Auf demselben Takt hält er `public.error_reports` sichtbar (#136): ein
Issue je ISO-Woche (Label `ops`, bei jedem Lauf neu geschrieben statt
kommentiert; keine Fehler = kein Issue) und eine 90-Tage-Bereinigung.
Beides liegt HIER und nicht in einem eigenen Workflow, weil Zeitplan,
service_role-Key und Token hier schon da sind — und die Tabelle bewusst
keine select-Policy hat, lesen kann also nur dieser Job.

Aufruf (in CI):
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... GH_TOKEN=... \
  python3 tool/feedback_bot.py
"""
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

MAX_TITLE = 60
ERROR_REPORT_RETENTION_DAYS = 90


class TableMissing(Exception):
    """Die feedback-Tabelle gibt es noch nicht (Migration nicht eingespielt)."""


def api(method, path, body=None):
    url = os.environ["SUPABASE_URL"].rstrip("/") + path
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {"apikey": key, "Content-Type": "application/json"}
    # Alte service_role-Keys sind JWTs und brauchen zusätzlich Authorization;
    # neue sb_secret_*-Keys nur den apikey-Header.
    if key.startswith("eyJ"):
        headers["Authorization"] = f"Bearer {key}"
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as response:
            text = response.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as error:
        # PostgREST meldet eine unbekannte Tabelle mit 404.
        if error.code == 404:
            raise TableMissing from error
        raise


def run(*cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"::error::Command failed: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        raise subprocess.CalledProcessError(result.returncode, cmd)
    return result.stdout.strip()


def issue_exists(title):
    out = run("gh", "issue", "list", "--state", "all", "--limit", "100",
              "--search", title, "--json", "title")
    return any(item["title"] == title for item in json.loads(out or "[]"))


def mark_processed(row_id):
    now = datetime.now(timezone.utc).isoformat()
    api("PATCH", f"/rest/v1/feedback?id=eq.{row_id}", {"processed_at": now})


def digest_body(rows, week):
    """Bündelt Fehlerberichte nach (context, error_type) zu einem Issue-Text.

    Gebündelt hier statt in der Query, weil PostgREST kein GROUP BY kennt.
    Beispieltexte werden gekürzt — sie können Serverdetails tragen, aber
    konstruktionsbedingt keine Personennamen (die Felder existieren nicht).
    """
    groups = {}
    for row in rows:
        key = (row.get("context") or "?", row.get("error_type") or "?")
        group = groups.setdefault(key, {
            "count": 0, "versions": set(), "platforms": set(), "example": "",
        })
        group["count"] += 1
        if row.get("app_version"):
            group["versions"].add(row["app_version"])
        if row.get("platform"):
            group["platforms"].add(row["platform"])
        if not group["example"] and row.get("message"):
            group["example"] = row["message"].strip().replace("\n", " ")[:200]

    ranked = sorted(groups.items(), key=lambda kv: -kv[1]["count"])
    lines = [
        f"{len(rows)} caught errors reached `public.error_reports` in {week}.",
        "",
        "These are errors the app **survived** — the user saw a snackbar and "
        "carried on. Releases bypass the stores, so no vitals dashboard sees "
        "them, and neither does anyone else unless it is written down here.",
        "",
        "| # | Context | Type | Versions | Platforms |",
        "|--:|---|---|---|---|",
    ]
    for (context, error_type), group in ranked:
        lines.append(
            f"| {group['count']} | {context} | `{error_type}` | "
            f"{', '.join(sorted(group['versions'])) or '–'} | "
            f"{', '.join(sorted(group['platforms'])) or '–'} |"
        )
    lines.append("")
    for (context, error_type), group in ranked:
        if group["example"]:
            lines.append(f"**{context} · {error_type}**")
            lines.append(f"> {group['example']}")
            lines.append("")
    lines.append("_Automatically created by the feedback bot; "
                 "updated in place while the week runs. Close when triaged._")
    return "\n".join(lines)


def report_error_digest():
    """Ein Issue je ISO-Woche, bei jedem Lauf neu geschrieben.

    Neu geschrieben statt kommentiert: Dutzende Kommentare pro Woche
    begrüben die Zahlen, statt sie zu zeigen. Keine Fehler heißt kein
    Issue — nichts zu berichten ist kein Bericht.
    """
    now = datetime.now(timezone.utc)
    year, week_no, _ = now.isocalendar()
    week = f"{year}-W{week_no:02d}"
    # Montag 00:00 UTC dieser ISO-Woche.
    start = (now - timedelta(days=now.isoweekday() - 1)).replace(
        hour=0, minute=0, second=0, microsecond=0)

    try:
        rows = api(
            "GET",
            "/rest/v1/error_reports?created_at=gte."
            + start.strftime("%Y-%m-%dT%H:%M:%SZ")
            + "&select=context,error_type,message,app_version,platform"
            "&order=created_at",
        ) or []
    except TableMissing:
        print("::notice::Tabelle 'error_reports' existiert noch nicht.")
        return
    if not rows:
        print(f"Keine Fehlerberichte in {week}.")
        return

    title = f"Error reports {week}"
    body = digest_body(rows, week)
    # Label idempotent anlegen — `gh issue create` scheitert an einem
    # unbekannten Label.
    subprocess.run(["gh", "label", "create", "ops", "--color", "5319E7",
                    "--description", "Betrieb, Monitoring, Backups"],
                   capture_output=True, text=True)

    existing = json.loads(run("gh", "issue", "list", "--state", "open",
                              "--label", "ops", "--limit", "50",
                              "--json", "number,title") or "[]")
    match = next((i for i in existing if i["title"] == title), None)
    if match:
        run("gh", "issue", "edit", str(match["number"]), "--body", body)
        print(f"Fehler-Digest aktualisiert: {title} ({len(rows)} Berichte)")
    else:
        run("gh", "issue", "create", "--title", title, "--body", body,
            "--label", "ops")
        print(f"Fehler-Digest angelegt: {title} ({len(rows)} Berichte)")


def purge_error_reports():
    # Mit literalem Z statt isoformat(): Das "+00:00" einer aware datetime
    # würde im Query-String als Leerzeichen gelesen und der Filter träfe
    # still etwas anderes als gemeint.
    cutoff = (datetime.now(timezone.utc)
              - timedelta(days=ERROR_REPORT_RETENTION_DAYS)
              ).strftime("%Y-%m-%dT%H:%M:%SZ")
    # Der Filter ist das Einzige, was das hier vom Leeren der Tabelle trennt.
    try:
        api("DELETE", f"/rest/v1/error_reports?created_at=lt.{cutoff}")
    except TableMissing:
        return
    print(f"Fehlerberichte älter als {ERROR_REPORT_RETENTION_DAYS} Tage entfernt.")


def main():
    # Vor dem Feedback-Teil — der kehrt bei leerer Tabelle früh zurück, und
    # Digest und Bereinigung sollen nicht davon abhängen, ob gerade
    # Rückmeldungen offen sind.
    report_error_digest()
    purge_error_reports()

    try:
        rows = api(
            "GET",
            "/rest/v1/feedback?processed_at=is.null&order=created_at"
            "&select=id,type,message,app_version,platform,created_at,groups(name)",
        ) or []
    except TableMissing:
        # Kein Fehler: Die Migration ist noch nicht eingespielt.
        print("::notice::Tabelle 'feedback' existiert noch nicht — nichts zu tun.")
        return
    print(f"{len(rows)} unverarbeitete Rückmeldungen")

    for row in rows:
        is_bug = row["type"] == "bug"
        prefix = "Bug report: " if is_bug else "Feature request: "
        label = "bug" if is_bug else "enhancement"
        summary = " ".join(row["message"].split())
        title = prefix + summary[:MAX_TITLE] + ("…" if len(summary) > MAX_TITLE else "")

        if issue_exists(title):
            print(f"Überspringe (Issue existiert): {title}")
        else:
            group = (row.get("groups") or {}).get("name") or "unbekannte Gruppe"
            body = (
                f"> {row['message']}\n\n"
                f"Eingereicht in der App von **{group}** am {row['created_at'][:10]}.\n"
                f"App-Version: {row.get('app_version') or '–'} · "
                f"Plattform: {row.get('platform') or '–'}\n\n"
                "_Automatisch erstellt vom Feedback-Bot._"
            )
            run("gh", "issue", "create", "--title", title, "--body", body,
                "--label", label)
            print(f"Issue angelegt: {title}")

        # Sofort stempeln, damit ein späterer Abbruch nichts doppelt anlegt.
        mark_processed(row["id"])


if __name__ == "__main__":
    main()

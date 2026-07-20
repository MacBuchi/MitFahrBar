#!/usr/bin/env python3
"""Macht aus In-App-Feedback GitHub-Issues.

Liest unverarbeitete Zeilen aus der Supabase-Tabelle `feedback`, legt je
Eintrag ein gelabeltes Issue an und stempelt `processed_at`. Nur
Python-Stdlib plus die `gh`-CLI.

Aufruf (in CI):
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... GH_TOKEN=... \
  python3 tool/feedback_bot.py
"""
import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone

MAX_TITLE = 60


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
    with urllib.request.urlopen(request) as response:
        text = response.read().decode()
        return json.loads(text) if text else None


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


def main():
    rows = api(
        "GET",
        "/rest/v1/feedback?processed_at=is.null&order=created_at"
        "&select=id,type,message,app_version,platform,created_at,groups(name)",
    ) or []
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

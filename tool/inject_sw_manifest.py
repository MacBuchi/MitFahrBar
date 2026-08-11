#!/usr/bin/env python3
"""inject_sw_manifest.py – setzt das Precache-Manifest in den Service Worker.

Läuft nach `flutter build web` gegen `build/web` und ersetzt in
`build/web/sw.js` die beiden Platzhalterzeilen `const BUILD` und
`const MANIFEST`. Die Quelle unter `web/sw.js` bleibt unangetastet: Ohne
Injektion ist der Worker bewusst inert (leeres Manifest = cacht nichts),
damit ein Entwicklungs-Build keine halbe, ungeprüfte Shell festhält.

Der Bauhash benennt den Cache. Ändert sich auch nur eine Datei, ändert sich
der Hash, damit die Datei `sw.js` — und genau das ist das Signal, an dem der
Browser eine neue Fassung erkennt.

Nur Standardbibliothek, wie `tool/import_seed.py`: eine Abhängigkeit für
sechzig Zeilen Hashen wäre eine zu viel.

    python3 tool/inject_sw_manifest.py [build/web]
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

# Was NICHT vorgehalten wird, und warum. Der Build misst 42 MB, gebraucht
# werden davon rund 18,5 — der Rest gehört zu Bauarten, die dieses Projekt
# nicht ausliefert. Das ist nicht nur Datenvolumen: Beim Aktualisieren liegen
# alter und neuer Cache gleichzeitig auf dem Gerät, und 2×42 MB reißen die
# Speichergrenze älterer iOS-Fassungen. Eine gescheiterte Installation hieße
# dort: Die PWA aktualisiert sich nie wieder.
EXCLUDED_SUFFIXES = (
    # Debug-Symbole der Engine, 6,1 MB, von niemandem geladen.
    ".symbols",
)
EXCLUDED_NAMES = (
    # Flutters Aufräum-Stummel. Vorgehalten wäre er nur eine Einladung.
    "flutter_service_worker.js",
    # Der Worker selbst — der Browser verwaltet sein Skript getrennt.
    "sw.js",
    # Kopie von index.html, die erst der Server auswählt (SPA-Fallback).
    # Ohne Netz beantwortet der Worker jede Navigation ohnehin aus index.html.
    "404.html",
)
EXCLUDED_PREFIXES = (
    # skwasm/wimp/webparagraph gehören zu `--wasm`-Builds. Wir bauen dart2js
    # mit CanvasKit; diese 13,4 MB lädt niemand.
    "canvaskit/skwasm",
    "canvaskit/wimp",
    "canvaskit/experimental_webparagraph/",
)

# Beide CanvasKit-Fassungen bleiben drin (Standard ~7 MB, `chromium/`
# ~5,7 MB): Welche geladen wird, entscheidet die Engine im Browser. Nur eine
# vorzuhalten hieße, dass die Hälfte der Browser ohne Netz eine weiße Seite
# sieht. Sie erst beim Laufen nachzucachen hätte dasselbe Loch, nur seltener:
# Wer eine neue Fassung installiert bekommt und sie zum ersten Mal ohne Netz
# öffnet, hätte sie nie geholt.

# Ein Riegel gegen stilles Wachsen. Bei ~18,5 MB gemessen (Flutter 3.44);
# reißt eine neue Engine-Fassung das Maß, soll der Build laut scheitern statt
# jedem Gerät unbemerkt das Doppelte aufzuladen.
MAX_BYTES = 25 * 1024 * 1024

# Ohne diese beiden lädt gar nichts — ein Manifest ohne sie wäre ein
# stiller Fehlschlag mit vollständig aussehendem Ergebnis.
REQUIRED = ("index.html", "main.dart.js")


def collect(root: Path) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel.endswith(EXCLUDED_SUFFIXES):
            continue
        if rel in EXCLUDED_NAMES:
            continue
        if rel.startswith(EXCLUDED_PREFIXES):
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append({"url": rel, "sha256": digest})
    return entries


def replace_line(source: str, prefix: str, value: str, where: Path) -> str:
    lines = source.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.startswith(prefix):
            lines[index] = f"{prefix} {value};\n"
            return "".join(lines)
    raise SystemExit(
        f"{where}: Platzhalterzeile „{prefix}“ fehlt. Ohne sie liefe ein "
        f"Worker mit leerem Manifest aus — er installiert sich, cacht nichts, "
        f"und der Offline-Start fehlt, ohne dass etwas rot wird."
    )


def main(argv: list[str]) -> int:
    root = Path(argv[1] if len(argv) > 1 else "build/web")
    worker = root / "sw.js"
    if not worker.is_file():
        raise SystemExit(
            f"{worker} fehlt — erst `flutter build web`, dann dieses Skript."
        )

    entries = collect(root)
    names = {entry["url"] for entry in entries}
    missing = [name for name in REQUIRED if name not in names]
    if missing:
        raise SystemExit(f"{root}: {', '.join(missing)} fehlt im Build.")

    total = sum((root / entry["url"]).stat().st_size for entry in entries)
    if total > MAX_BYTES:
        raise SystemExit(
            f"Die Shell misst {total / 1e6:.1f} MB und damit mehr als die "
            f"erlaubten {MAX_BYTES / 1e6:.0f} MB. Beim Aktualisieren liegen "
            f"zwei Fassungen gleichzeitig auf dem Gerät. Erst nachsehen, was "
            f"dazugekommen ist, dann entscheiden — nicht die Grenze anheben."
        )

    # Der Bauhash über Pfade UND Inhalte: Eine umbenannte Datei mit gleichem
    # Inhalt ist ein anderer Build.
    build = hashlib.sha256(
        "".join(f"{e['url']}:{e['sha256']}\n" for e in entries).encode()
    ).hexdigest()[:16]

    source = worker.read_text()
    source = replace_line(source, "const BUILD =", json.dumps(build), worker)
    source = replace_line(
        source,
        "const MANIFEST =",
        json.dumps(entries, separators=(",", ":")),
        worker,
    )
    worker.write_text(source)

    print(
        f"Service Worker: {len(entries)} Dateien, {total / 1e6:.1f} MB, "
        f"Build {build}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

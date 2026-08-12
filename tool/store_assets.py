#!/usr/bin/env python3
"""store_assets.py – Erzeugt die Play-Store-Grafiken aus dem, was im Repo liegt.

Alles in doc/store/ ist ERZEUGT, nicht gezeichnet — dieselbe Linie wie bei
den Icons (tool/brand/) und den README-Screenshots (tool/screenshots.sh).
Nach Änderungen an Marke oder Screenshots: dieses Skript neu laufen lassen,
nie die PNGs von Hand anfassen.

    python3 tool/store_assets.py        # braucht nur Pillow

Drei Erzeugnisse:

* icon-512.png        – Play verlangt 512×512 als 32-Bit-PNG. Quelle ist das
                        maskable PWA-Icon (web/icons/Icon-maskable-512.png,
                        aus tool/brand/build_icons.sh): volle Fläche mit dem
                        Marken-Verlauf. Das normale Icon-512.png taugt NICHT,
                        es ist eine weiße Marke auf Transparenz.
* feature-graphic.png – 1024×500. Marken-Verlauf, weiße Wortmarke in Space
                        Grotesk, die Bildmarke aus dem Adaptive-Icon-
                        Vordergrund. Der Text sitzt am DUNKLEN Ende des
                        Verlaufs — Weiß auf dem hellen Endpunkt #22D3EE trägt
                        nur 1,81:1 (die Banner-Lehre aus tokens.dart); der
                        Kontrast wird unten GEMESSEN, nicht geschätzt, und
                        der Lauf bricht unter 4,5:1 ab.
* screenshots/*.png   – 1080×1920 (9:16). Die README-Screenshots sind
                        860×1800 = 1:2,09, und Play lehnt alles über 2:1 ab.
                        Skaliert auf Höhe, seitlich mit der Randfarbe des
                        jeweiligen Bildes aufgefüllt — kein Zuschnitt, der
                        die Navigationsleiste oder die App-Bar anschnitte.

doc/ ist vom Version Guard ausgenommen: Neue Store-Grafiken sind kein
Release, sie stecken in keinem Binary.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "doc" / "store"

TEAL_DARK = (11, 79, 92)  # dunkles Ende, eigens für die Textseite
TEAL_MID = (8, 145, 178)  # #0891B2 – der Ton der Marke (mark.svg)
WHITE = (255, 255, 255)


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    def channel(value: int) -> float:
        s = value / 255
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

    r, g, b = (channel(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = sorted((relative_luminance(a), relative_luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def gradient(size: tuple[int, int], left: tuple[int, int, int],
             right: tuple[int, int, int]) -> Image.Image:
    """Horizontaler Verlauf, links [left], rechts [right]."""
    width, height = size
    image = Image.new("RGB", size)
    for x in range(width):
        t = x / (width - 1)
        color = tuple(round(l + (r - l) * t) for l, r in zip(left, right))
        image.paste(color, (x, 0, x + 1, height))
    return image


def build_icon() -> None:
    source = Image.open(ROOT / "web/icons/Icon-maskable-512.png")
    icon = source.convert("RGBA")  # Play verlangt 32 Bit; die Quelle ist 24
    assert icon.size == (512, 512), icon.size
    icon.save(OUT / "icon-512.png")
    print(f"icon-512.png            512×512 RGBA")


def load_font(path: Path, size: int, weight: int | None = None) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(path), size)
    if weight is not None:
        try:
            font.set_variation_by_axes([weight])
        except OSError:
            pass  # keine Variable-Font-Unterstützung: normale Stärke reicht
    return font


def build_feature_graphic() -> None:
    canvas = gradient((1024, 500), TEAL_DARK, TEAL_MID)
    draw = ImageDraw.Draw(canvas)
    title = load_font(ROOT / "assets/fonts/SpaceGrotesk.ttf", 92, weight=700)
    sub = load_font(ROOT / "assets/fonts/Manrope.ttf", 34, weight=500)
    lines = [
        ((70, 168), "MitFahrBar", title),
        ((72, 286), "Fahrgemeinschaft, fair geregelt.", sub),
    ]
    text_right = max(
        draw.textbbox(pos, text, font=font)[2] for pos, text, font in lines
    )

    # Bildmarke rechts: der Adaptive-Icon-Vordergrund ist die weiße Marke
    # auf Transparenz, mit dem Sicherheitsrand des Adaptive-Icon-Formats —
    # deshalb erst auf den sichtbaren Inhalt beschnitten. Platziert wird
    # NACH dem Vermessen des Texts: Beim ersten Wurf lief die Unterzeile in
    # die weiße Marke hinein, und die Kontrastmessung unten hat es gefangen
    # (Weiß auf Weiß, 1,00:1) — deshalb bricht der Lauf auch bei
    # Überlappung ab, statt sie schön zu rechnen.
    mark = Image.open(
        ROOT / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png"
    ).convert("RGBA")
    mark = mark.crop(mark.getbbox())
    # Adaptiv statt fest: Die beschnittene Marke ist gut doppelt so breit
    # wie hoch — eine feste Höhe von 280 ergäbe 570 Breite und läge quer
    # über dem Text. Sie bekommt, was nach Text plus Abstand übrig ist.
    available_w = 1024 - 56 - (round(text_right) + 48)
    scale = min(available_w / mark.width, 300 / mark.height)
    mark = mark.resize(
        (round(mark.width * scale), round(mark.height * scale)),
        Image.LANCZOS,
    )
    mark_x = 1024 - mark.width - 56
    if mark_x < text_right + 40:
        sys.exit(
            f"Feature-Grafik: Marke (ab x={mark_x}) überlappt den Text "
            f"(bis x={text_right:.0f}) — Layout anpassen, nicht quetschen."
        )
    canvas.paste(mark, (mark_x, (500 - mark.height) // 2), mark)

    # Gemessen, nicht geschätzt — und VOR dem Zeichnen, sonst misst man den
    # Text statt des Untergrunds: Der Verlauf wird nach rechts heller, die
    # kritische Stelle ist also das rechte Ende der längeren Zeile. Dort
    # muss Weiß noch 4,5:1 tragen (die Banner-Lehre aus dem Design-Set —
    # zwei Vorschläge sind an genau dieser Rechnung schon gescheitert,
    # obwohl sie im Bild gut aussahen).
    ratio = min(
        contrast(
            WHITE,
            canvas.getpixel(
                (min(round(draw.textbbox(pos, text, font=font)[2]), 1023),
                 pos[1] + 10),
            )[:3],
        )
        for pos, text, font in lines
    )
    if ratio < 4.5:
        sys.exit(f"Feature-Grafik: Weiß trägt am Textende nur {ratio:.2f}:1")

    for pos, text, font in lines:
        draw.text(pos, text, font=font, fill=WHITE)

    canvas.convert("RGB").save(OUT / "feature-graphic.png")
    print(f"feature-graphic.png     1024×500, Textkontrast {ratio:.2f}:1")


def edge_color(image: Image.Image) -> tuple[int, int, int]:
    """Häufigste Farbe der äußersten Spalten — damit die Balken nahtlos an
    den Hintergrund des Screenshots anschließen."""
    edge = image.crop((0, 0, 1, image.height))
    colors = edge.convert("RGB").getcolors(image.height)
    return max(colors, key=lambda c: c[0])[1]


def build_screenshots() -> None:
    (OUT / "screenshots").mkdir(exist_ok=True)
    shots = sorted((ROOT / "doc/screenshots").glob("*.png"))
    if len(shots) < 2:
        sys.exit("Play verlangt mindestens zwei Screenshots.")
    for index, path in enumerate(shots, start=1):
        source = Image.open(path).convert("RGB")
        scaled = source.resize(
            (round(source.width * 1920 / source.height), 1920),
            Image.LANCZOS,
        )
        canvas = Image.new("RGB", (1080, 1920), edge_color(source))
        canvas.paste(scaled, ((1080 - scaled.width) // 2, 0))
        name = f"{index:02d}-{path.stem}.png"
        canvas.save(OUT / "screenshots" / name)
        print(f"screenshots/{name:<28} 1080×1920")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    build_icon()
    build_feature_graphic()
    build_screenshots()


if __name__ == "__main__":
    main()

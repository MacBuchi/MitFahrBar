#!/usr/bin/env bash
# build_icons.sh – Erzeugt alle App-Icons aus der Bildmarke.
#
# Quelle ist tool/brand/mark.svg (weiße Marke). Daraus entstehen:
#   web/icons/*          – PWA-Icons, normal und maskable
#   web/favicon.png      – Browser-Tab
#   android/.../mipmap-* – Launcher-Icons und Adaptive-Icon-Vordergrund
#
# Die Marke wird direkt in die Ziel-SVG eingebettet — eine Referenz per
# <image href> löst rsvg-convert nicht auf (Ergebnis wäre eine leere Kachel).
#
# Braucht rsvg-convert (brew install librsvg) und python3.
set -euo pipefail

cd "$(dirname "$0")/../.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert fehlt: brew install librsvg" >&2
  exit 1
}

# Inneres Markup der Marke (ohne <svg>-Hülle), zum Einbetten.
MARK_INNER=$(python3 - <<'PY'
import re
s = open('tool/brand/mark.svg', encoding='utf-8').read()
print(re.search(r'<svg[^>]*>(.*)</svg>', s, re.S).group(1).strip())
PY
)

# Das Benachrichtigungs-Icon hat eine EIGENE Quelle: tool/brand/notification.svg.
#
# Nicht aus mark.svg abgeleitet, und das ist gemessen, nicht Geschmack: Android
# gibt dem Benachrichtigungs-Icon einen QUADRATISCHEN 24-dp-Kasten, und die
# Marke misst von der Seite 1,69:1. Darin wird sie 22 x 13 dp und steht neben
# quadratischen Nachbarn (Wecker, Kalender), die 20 x 20 fuellen — sie sieht
# halb so gross aus, und randlos ausgereizt braechte das 9 % Hoehe statt des
# Doppelten. Die Frontansicht misst 1,17:1 und fuellt den Kasten mit 22 x 18.
# Gemeldet in #271 („viel zu klein"), nachgemessen am gerenderten Pixel.
#
# Die Regel „mark.svg ist die einzige Quelle" gilt unveraendert fuer Launcher,
# Web und Favicon. Dies hier ist ein anderes Artefakt fuer einen anderen
# Kasten — der Preis ist ausgesprochen: Wer die Marke aendert, zieht dieses
# Glyph von Hand nach.
#
# Gerendert wird es wie alles andere aus der SVG (rsvg-convert), nie von Hand
# gelegt. Die cyanen Flaechen werden ausgestanzt, sonst sind sie im Alphakanal
# genauso deckend wie der Aufbau — genau der weisse Klotz aus #271.
MARK_MONO=$(python3 - <<'PY'
import re
s = open('tool/brand/notification.svg', encoding='utf-8').read()
inner = re.search(r'<svg[^>]*>(.*)</svg>', s, re.S).group(1).strip()
# Maske: Luminanz = Deckung. Cyan wird schwarz (ausgestanzt), alles andere weiss.
inner = inner.replace('#0891b2', '#000000')
inner = re.sub(r'fill="#(?!000000)[0-9a-fA-F]{6}"', 'fill="#ffffff"', inner)
print(inner.strip())
PY
)

# Tinten-Bounding-Box der Marke: wo die Formen wirklich stehen, nicht wo der
# Kasten aufhoert. Die Marke fuellt nur 61 % der viewBox-Hoehe und sitzt mit
# ihrer Mitte bei y=61,5 statt 50 — auf den Kasten skaliert wird sie deshalb zu
# klein UND zu tief gezeichnet (#271). Gemessen statt eingetragen, damit die
# Zahlen nicht wegdriften, sobald jemand mark.svg aendert.
INK=$(python3 - <<'PY'
import re, xml.etree.ElementTree as ET

NS = '{http://www.w3.org/2000/svg}'

def bounds(el, dx, dy):
    t = el.tag.replace(NS, '')
    if t == 'rect':
        x, y = float(el.get('x', 0)), float(el.get('y', 0))
        return (x + dx, y + dy,
                x + dx + float(el.get('width')), y + dy + float(el.get('height')))
    if t == 'circle':
        cx, cy, r = (float(el.get(k)) for k in ('cx', 'cy', 'r'))
        return (cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r)
    raise SystemExit(f'build_icons: unbekannte Form <{t}> — die Tinten-Box kann '
                     'sie nicht messen. Erst hier ergaenzen.')

def walk(node, dx=0.0, dy=0.0):
    for el in node:
        if el.tag.replace(NS, '') != 'g':
            yield bounds(el, dx, dy)
            continue
        raw = el.get('transform')
        m = re.fullmatch(r'translate\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)', raw or '')
        if raw and not m:
            raise SystemExit(f"build_icons: Transform '{raw}' wird nicht verstanden.")
        yield from walk(el, dx + (float(m.group(1)) if m else 0.0),
                        dy + (float(m.group(2)) if m else 0.0))

def box(path):
    root = ET.parse(path).getroot()
    xs0, ys0, xs1, ys1 = zip(*walk(root))
    # NICHT am viewBox beschneiden. Naheliegend waere es — mark.svg schneidet
    # den Fahrtwind bei x=120 ab, er reicht bis 126. Die Icons betten aber nur
    # das *innere* Markup in eine eigene Leinwand ein, und die clippt dort
    # nicht: Die Striche stehen in jedem erzeugten Icon vollstaendig da.
    # Beschnitten gerechnet fiel die Marke 5 % zu gross aus und ihre Diagonale
    # auf 68,4 dp — ueber die 66-dp-Safe-Zone hinaus. Gemessen am gerenderten
    # Pixel, nicht am Quelltext geglaubt.
    return (min(xs0), min(ys0), max(xs1) - min(xs0), max(ys1) - min(ys0))

print(*[round(v, 4) for v in box('tool/brand/mark.svg')
        + box('tool/brand/notification.svg')])
PY
)
read -r INK_X INK_Y INK_W INK_H MONO_X MONO_Y MONO_W MONO_H <<<"$INK"
echo "Marke ${INK_W}x${INK_H} bei ${INK_X},${INK_Y} · Glyph ${MONO_W}x${MONO_H}"

# render <ziel> <kante> <radius> <tintenanteil> [transparent]
#
# <tintenanteil> ist die Breite der *Tinte* im Verhaeltnis zur Kante, nicht die
# des viewBox-Kastens: Danach sitzt die Marke mittig und ist so gross wie
# angegeben. Auf den Kasten bezogen war sie vertikal um 11,5 Einheiten nach
# unten versetzt, weil die Tinte nur y=31..92 belegt (#271).
render() {
  local target=$1 size=$2 radius=$3 pct=$4 transparent=${5:-}
  local scale x y bg
  scale=$(python3 -c "print(round($size*$pct/$INK_W,6))")
  x=$(python3 -c "print(round(($size-$INK_W*$scale)/2-$INK_X*$scale,3))")
  y=$(python3 -c "print(round(($size-$INK_H*$scale)/2-$INK_Y*$scale,3))")
  if [ -n "$transparent" ]; then
    bg=""
  else
    bg="<rect width=\"$size\" height=\"$size\" rx=\"$radius\" fill=\"url(#g)\"/>"
  fi
  cat > "$OUT/icon.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="$size" height="$size">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#0891b2"/>
      <stop offset="1" stop-color="#22d3ee"/>
    </linearGradient>
  </defs>
  $bg
  <g transform="translate($x,$y) scale($scale)">
$MARK_INNER
  </g>
</svg>
SVG
  mkdir -p "$(dirname "$target")"
  rsvg-convert -w "$size" -h "$size" "$OUT/icon.svg" -o "$target"
  echo "  $target"
}

echo "Web-Icons:"
# Eckradius 46/200 wie im Design-Set; Marke füllt 66 % der Kante.
render web/icons/Icon-192.png 192 44 0.66
render web/icons/Icon-512.png 512 118 0.66
# Maskable: Marke kleiner, damit sie in jeder OEM-Maske sichtbar bleibt.
render web/icons/Icon-maskable-192.png 192 0 0.46
render web/icons/Icon-maskable-512.png 512 0 0.46
render web/favicon.png 64 14 0.66

echo "Android-Launcher:"
AND=android/app/src/main/res
for entry in "mdpi 48" "hdpi 72" "xhdpi 96" "xxhdpi 144" "xxxhdpi 192"; do
  set -- $entry
  render "$AND/mipmap-$1/ic_launcher.png" "$2" \
    "$(python3 -c "print(round($2*0.22))")" 0.66
done

# Der begrenzende Wert ist die *Diagonale* der Tinte, nicht ihre Breite: Sie
# muss in die 66-dp-Safe-Zone passen. 66/hypot(119,61) = 0,494 je viewBox-
# Einheit → 58,7 dp Tintenbreite von 108, also 0,544 der Kante. Vorher waren es
# 45,0 dp, weil der ganze 120x100-Kasten hineingerechnet wurde (#271).
echo "Adaptive-Icon-Vordergrund (nur Marke, Safe-Zone 66 von 108 dp):"
FG_PCT=$(python3 -c "import math;print(round(66/math.hypot($INK_W,$INK_H)*$INK_W/108,4))")
for entry in "mdpi 108" "hdpi 162" "xhdpi 216" "xxhdpi 324" "xxxhdpi 432"; do
  set -- $entry
  render "$AND/mipmap-$1/ic_launcher_foreground.png" "$2" 0 "$FG_PCT" transparent
done

# Benachrichtigungs-Icon: EIN VectorDrawable statt fuenf PNGs.
#
# Android rastert einen Vektor erst auf dem Geraet, in dem Moment, in dem
# gezeichnet wird — und die SystemUI tut das in IHRER Dichte, wirft dann jede
# Farbe weg und behaelt nur den Alphakanal. Damit gibt es keine Groesse, die
# man vergessen koennte, und eine Dichte, die es heute noch nicht gibt,
# bekommt ihre Pixel automatisch. (Unterhalb minSdk 21 erzeugte AGP doch PNGs
# als Rueckfall; wir sind bei 24.)
#
# Deshalb ist das Gesicht ein LOCH und keine dunkle Flaeche: `fillType`
# `evenOdd` (ab API 24 — unser minSdk) macht aus einem Teilpfad im Inneren
# eine Aussparung. Muster von PilzBuddy (pilzbuddy#331).
#
# Zwei Pfade, und das ist kein Zufall: Die Raeder ueberlappen den Aufbau. In
# EINEM evenOdd-Pfad wuerde die Ueberlappung selbst zum Loch — als eigener
# Pfad uebermalt sie einfach.
echo "Benachrichtigungs-Icon (Vektor, eine Datei fuer alle Dichten):"
python3 - <<'PY'
import re

BOX, PCT = 24.0, 0.92
src = open('tool/brand/notification.svg', encoding='utf-8').read()
inner = re.search(r'<svg[^>]*>(.*)</svg>', src, re.S).group(1)

RECT = re.compile(r'<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" '
                  r'height="([\d.]+)" rx="([\d.]+)" fill="(#[0-9a-fA-F]{6})"')
CIRC = re.compile(r'<circle cx="([\d.]+)" cy="([\d.]+)" r="([\d.]+)" '
                  r'fill="(#[0-9a-fA-F]{6})"')

rects = [(float(a), float(b), float(c), float(d), float(e), f)
         for a, b, c, d, e, f in RECT.findall(inner)]
circles = [(float(a), float(b), float(c), d) for a, b, c, d in CIRC.findall(inner)]
if not rects or not circles:
    raise SystemExit('build_icons: notification.svg hat eine Form, die der '
                     'Vektor-Schritt nicht kennt. Erst hier ergaenzen.')

xs0 = [x for x, y, w, h, r, f in rects] + [cx - r for cx, cy, r, f in circles]
ys0 = [y for x, y, w, h, r, f in rects] + [cy - r for cx, cy, r, f in circles]
xs1 = [x + w for x, y, w, h, r, f in rects] + [cx + r for cx, cy, r, f in circles]
ys1 = [y + h for x, y, w, h, r, f in rects] + [cy + r for cx, cy, r, f in circles]
ix, iy = min(xs0), min(ys0)
iw, ih = max(xs1) - ix, max(ys1) - iy
scale = BOX * PCT / max(iw, ih)
ox = (BOX - iw * scale) / 2
oy = (BOX - ih * scale) / 2

def tx(x): return round((x - ix) * scale + ox, 3)
def ty(y): return round((y - iy) * scale + oy, 3)
def ts(v): return round(v * scale, 3)

def rrect(x, y, w, h, r):
    X, Y, W, H, R = tx(x), ty(y), ts(w), ts(h), ts(r)
    return (f'M{X + R},{Y} L{X + W - R},{Y} A{R},{R} 0 0,1 {X + W},{Y + R} '
            f'L{X + W},{Y + H - R} A{R},{R} 0 0,1 {X + W - R},{Y + H} '
            f'L{X + R},{Y + H} A{R},{R} 0 0,1 {X},{Y + H - R} '
            f'L{X},{Y + R} A{R},{R} 0 0,1 {X + R},{Y} Z')

def circle(cx, cy, r):
    CX, CY, R = tx(cx), ty(cy), ts(r)
    return (f'M{CX - R},{CY} A{R},{R} 0 1,0 {CX + R},{CY} '
            f'A{R},{R} 0 1,0 {CX - R},{CY} Z')

# Der Aufbau ist das groesste Rechteck; die Raeder sind die uebrigen weissen.
body = max((r for r in rects if r[5] != '#0891b2'), key=lambda r: r[2] * r[3])
holes = [r for r in rects if r[5] == '#0891b2']
wheels = [r for r in rects if r[5] != '#0891b2' and r is not body]

solid = ' '.join([rrect(*body[:5])]
                 + [rrect(*h[:5]) for h in holes]
                 + [circle(*c[:3]) for c in circles])
rims = ' '.join(rrect(*w[:5]) for w in wheels)

out = f"""<?xml version="1.0" encoding="utf-8"?>
<!-- ERZEUGT von tool/brand/build_icons.sh aus tool/brand/notification.svg.
     Nicht von Hand bearbeiten — die naechste Ausfuehrung ueberschreibt es.

     Ein Vektor statt fuenf PNGs: Android rastert ihn erst beim Zeichnen, in
     der Dichte des jeweiligen Geraets. Die Statusleiste bekommt ohnehin nur
     Paketname und Ressourcen-Id; die SystemUI schlaegt nach, rastert selbst
     und behaelt nur den Alphakanal — jede Farbe faellt weg. Deshalb ist die
     Frontscheibe ein LOCH (`evenOdd`, ab API 24 = unser minSdk) und keine
     dunkle Flaeche.

     Zwei Pfade: Die Raeder ueberlappen den Aufbau, und in einem einzigen
     evenOdd-Pfad wuerde die Ueberlappung selbst zum Loch. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="{solid}" />
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="{rims}" />
</vector>
"""
target = 'android/app/src/main/res/drawable/ic_notification.xml'
open(target, 'w', encoding='utf-8').write(out)
print(f'  {target}  (Tinte {iw:g}x{ih:g} → {iw * scale:.1f}x{ih * scale:.1f} von {BOX:g})')
PY

echo "Fertig."

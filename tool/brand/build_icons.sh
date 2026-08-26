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

# Dasselbe einfarbig, für das Benachrichtigungs-Icon: Android macht daraus
# ohnehin eine Silhouette über den Alphakanal (siehe AndroidManifest). Die
# cyanen Flächen — Fensterband und Radnaben — werden hier *ausgestanzt*, sonst
# sind sie im Alphakanal genauso deckend wie der Wagen, und übrig bleibt ein
# weißer Klotz (#271, gemeldet als „ein weißer Kreis"). Abgeleitet statt zweite
# Quelldatei: Eine Kopie der Marke driftet, sobald jemand mark.svg anfasst.
MARK_MONO=$(python3 - <<'PY'
import re
s = open('tool/brand/mark.svg', encoding='utf-8').read()
inner = re.search(r'<svg[^>]*>(.*)</svg>', s, re.S).group(1).strip()
if 'id="motion"' not in inner:
    raise SystemExit('build_icons: <g id="motion"> fehlt in mark.svg — ohne die '
                     'Markierung weiss das Mono-Icon nicht, was Dekoration ist.')
# Der Fahrtwind ragt über den viewBox hinaus und waere bei 24 dp ein Bruchstueck
# am Rand; ohne ihn wird der Wagen zugleich ein Siebtel groesser.
inner = re.sub(r'<g id="motion".*?</g>', '', inner, flags=re.S)
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
root = ET.parse('tool/brand/mark.svg').getroot()

def bounds(el, dx, dy):
    t = el.tag.replace(NS, '')
    if t == 'rect':
        x, y = float(el.get('x', 0)), float(el.get('y', 0))
        return (x + dx, y + dy,
                x + dx + float(el.get('width')), y + dy + float(el.get('height')))
    if t == 'circle':
        cx, cy, r = (float(el.get(k)) for k in ('cx', 'cy', 'r'))
        return (cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r)
    raise SystemExit(f'build_icons: unbekannte Form <{t}> in mark.svg — die '
                     'Tinten-Box kann sie nicht messen. Erst hier ergaenzen.')

def walk(node, dx=0.0, dy=0.0, skip=None):
    for el in node:
        if el.tag.replace(NS, '') != 'g':
            yield bounds(el, dx, dy)
            continue
        if skip and el.get('id') == skip:
            continue
        raw = el.get('transform')
        m = re.fullmatch(r'translate\(\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\)', raw or '')
        if raw and not m:
            raise SystemExit(f"build_icons: Transform '{raw}' wird nicht verstanden.")
        yield from walk(el, dx + (float(m.group(1)) if m else 0.0),
                        dy + (float(m.group(2)) if m else 0.0), skip)

def box(skip=None):
    xs0, ys0, xs1, ys1 = zip(*walk(root, skip=skip))
    # NICHT am viewBox beschneiden. Naheliegend waere es — mark.svg selbst
    # schneidet den Fahrtwind bei x=120 ab, er reicht bis 126. Die Icons
    # betten aber nur das *innere* Markup in eine eigene Leinwand ein, und die
    # clippt dort nicht: Die Striche stehen in jedem erzeugten Icon vollstaendig
    # da. Beschnitten gerechnet fiel die Marke 5 % zu gross aus und ihre
    # Diagonale auf 68,4 dp — ueber die 66-dp-Safe-Zone hinaus. Gemessen am
    # gerenderten Pixel, nicht am Quelltext geglaubt.
    return (min(xs0), min(ys0), max(xs1) - min(xs0), max(ys1) - min(ys0))

print(*[round(v, 4) for v in box() + box(skip='motion')])
PY
)
read -r INK_X INK_Y INK_W INK_H MONO_X MONO_Y MONO_W MONO_H <<<"$INK"
echo "Tinte ${INK_W}x${INK_H} bei ${INK_X},${INK_Y} · einfarbig ${MONO_W}x${MONO_H}"

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

# render_mono <ziel> <kante> <tintenanteil>
#
# Zeichnet die Marke als reine Silhouette: Die Maske traegt die Deckung
# (weiss = deckend, schwarz = ausgestanzt), das gefuellte Rechteck darunter
# liefert die Farbe. Ohne die Maske waere jede cyane Flaeche im Alphakanal
# genauso deckend wie der Wagen — genau der weisse Klotz aus #271.
render_mono() {
  local target=$1 size=$2 pct=$3
  local scale x y
  scale=$(python3 -c "print(round($size*$pct/$MONO_W,6))")
  x=$(python3 -c "print(round(($size-$MONO_W*$scale)/2-$MONO_X*$scale,3))")
  y=$(python3 -c "print(round(($size-$MONO_H*$scale)/2-$MONO_Y*$scale,3))")
  cat > "$OUT/mono.svg" <<SVG
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="$size" height="$size">
  <defs>
    <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="$size" height="$size">
      <g transform="translate($x,$y) scale($scale)">
$MARK_MONO
      </g>
    </mask>
  </defs>
  <rect width="$size" height="$size" fill="#ffffff" mask="url(#m)"/>
</svg>
SVG
  mkdir -p "$(dirname "$target")"
  rsvg-convert -w "$size" -h "$size" "$OUT/mono.svg" -o "$target"
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

# Benachrichtigungs-Icon: Android zeichnet davon nur den Alphakanal, eingefaerbt
# mit notification_accent. Quadratisch nach Androids Vorgabe, die Tinte mit
# etwas Luft zum Rand — randlos beschnitten wirkt sie in der Statusleiste wie
# abgeschnitten.
echo "Benachrichtigungs-Icon (einfarbig, ausgestanzt):"
for entry in "mdpi 24" "hdpi 36" "xhdpi 48" "xxhdpi 72" "xxxhdpi 96"; do
  set -- $entry
  render_mono "$AND/drawable-$1/ic_notification.png" "$2" 0.92
done

echo "Fertig."

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

# render <ziel> <kante> <radius> <markenanteil> [transparent]
render() {
  local target=$1 size=$2 radius=$3 pct=$4 transparent=${5:-}
  local markW markH x y scale bg
  markW=$(python3 -c "print($size*$pct)")
  markH=$(python3 -c "print($markW*100/120)")
  x=$(python3 -c "print(round(($size-$markW)/2,3))")
  y=$(python3 -c "print(round(($size-$markH)/2,3))")
  scale=$(python3 -c "print(round($markW/120,6))")
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

echo "Adaptive-Icon-Vordergrund (nur Marke, Safe-Zone 66 von 108 dp):"
for entry in "mdpi 108" "hdpi 162" "xhdpi 216" "xxhdpi 324" "xxxhdpi 432"; do
  set -- $entry
  render "$AND/mipmap-$1/ic_launcher_foreground.png" "$2" 0 0.42 transparent
done

echo "Fertig."

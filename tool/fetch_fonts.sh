#!/usr/bin/env bash
# Downloads Inter, Space Grotesk and JetBrains Mono (OFL, variable TTF) into assets/fonts.
# Runs in CI before the build; the fonts are then packaged INTO the APK (no runtime downloads).
set -euo pipefail

DEST="assets/fonts"
mkdir -p "$DEST"

RAW="https://raw.githubusercontent.com/google/fonts/main/ofl"
CDN="https://cdn.jsdelivr.net/gh/google/fonts@main/ofl"

fetch() {
  local name="$1"
  local rel="$2"
  local out="$DEST/$name"
  if [ -s "$out" ]; then
    echo "already present: $out"
    return 0
  fi
  local ok=0
  for base in "$RAW" "$CDN"; do
    if curl -fL --retry 3 --retry-delay 3 -o "$out" "$base/$rel"; then
      ok=1
      break
    fi
    echo "download failed from $base/$rel"
  done
  if [ "$ok" -ne 1 ]; then
    echo "ERROR: could not download $name" >&2
    exit 1
  fi
  local magic
  magic="$(head -c4 "$out" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    00010000|74727565|4f54544f) ;;
    *) echo "ERROR: $out is not a TrueType/OpenType font (magic=$magic)" >&2; exit 1 ;;
  esac
  echo "ok: $out ($(wc -c < "$out") bytes)"
}

fetch "Inter.ttf" "inter/Inter%5Bopsz%2Cwght%5D.ttf"
fetch "SpaceGrotesk.ttf" "spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf"
fetch "JetBrainsMono.ttf" "jetbrainsmono/JetBrainsMono%5Bwght%5D.ttf"

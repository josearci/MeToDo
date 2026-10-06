#!/bin/bash
# Rebuild Resources/AppIcon.icns from a logo mockup: ./scripts/make-icns.sh path/to/logo.jpg
set -euo pipefail
if [ $# -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: ./scripts/make-icns.sh <image file>   (e.g. ~/Downloads/logo.png)" >&2
  [ $# -eq 1 ] && echo "No file at: $1" >&2
  exit 1
fi
IMG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift "$IMG" Resources/AppIcon-1024.png
SET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$SET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/AppIcon-1024.png --out "$SET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Resources/AppIcon-1024.png --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns updated — run ./install.sh"

#!/bin/bash
# Rebuild Resources/AppIcon.icns from a logo mockup: ./scripts/make-icns.sh path/to/logo.jpg
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift "$1" Resources/AppIcon-1024.png
SET=$(mktemp -d)/AppIcon.iconset; mkdir -p "$SET"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz Resources/AppIcon-1024.png --out "$SET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) Resources/AppIcon-1024.png --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
echo "Resources/AppIcon.icns updated — run ./install.sh"

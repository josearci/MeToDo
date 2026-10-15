#!/bin/bash
# Installs the latest MeToDo release into /Applications (~/Applications without admin rights). After this, MeToDo updates itself.
#
#   curl -fsSL https://raw.githubusercontent.com/josearci/MeToDo/main/install.sh | bash
#
# (Building from source instead? See scripts/dev-install.sh.)
set -euo pipefail

REPO="josearci/MeToDo"
URL="https://github.com/$REPO/releases/latest/download/MeToDo.zip"

if [ "$(uname)" != "Darwin" ]; then echo "MeToDo is a macOS app." >&2; exit 1; fi
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "$MAJOR" -lt 15 ]; then echo "MeToDo needs macOS 15 or later (this Mac has $(sw_vers -productVersion))." >&2; exit 1; fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the latest MeToDo…"
curl -fsSL "$URL" -o "$TMP/MeToDo.zip"
ditto -x -k "$TMP/MeToDo.zip" "$TMP"
APP="$TMP/MeToDo.app"
if [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null)" != "com.josearci.metodo" ]; then
  echo "The download doesn't look like MeToDo; nothing was installed." >&2
  exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")

# Accounts without admin rights can't write /Applications; ~/Applications works the same.
DEST=/Applications
[ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

pkill -x MeToDo 2>/dev/null && sleep 1 || true
rm -rf "$DEST/MeToDo.app"
ditto "$APP" "$DEST/MeToDo.app"
xattr -dr com.apple.quarantine "$DEST/MeToDo.app" 2>/dev/null || true
open "$DEST/MeToDo.app"

echo "MeToDo $VERSION is installed in $DEST and running in your menu bar (✓ icon, or press ⌃⌥M)."
echo "Don't see the icon? It may be hidden by the notch or under System Settings › Menu Bar; opening MeToDo again always shows its window."
echo "It keeps itself up to date."

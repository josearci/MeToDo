#!/bin/bash
# Builds MeToDo.app, signs it for this Mac, and (re)installs it in /Applications. Data is untouched.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MeToDo"
APP=".build/MeToDo.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeToDo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"

# ponytail: SIGTERM skips applicationWillTerminate; only changes from the last 0.5s (save debounce) could be lost.
pkill -x MeToDo || true
sleep 1
rm -rf /Applications/MeToDo.app
cp -R "$APP" /Applications/
open /Applications/MeToDo.app
echo "Installed /Applications/MeToDo.app"

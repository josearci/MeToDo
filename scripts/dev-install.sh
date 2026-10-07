#!/bin/bash
# For development: builds MeToDo from this checkout and (re)installs it in /Applications. Data is untouched.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
# ponytail: SIGTERM skips applicationWillTerminate; only edits from the last 0.5s (save debounce) could be lost.
pkill -x MeToDo || true
sleep 1
rm -rf /Applications/MeToDo.app
cp -R .build/MeToDo.app /Applications/
open /Applications/MeToDo.app
echo "Installed /Applications/MeToDo.app"

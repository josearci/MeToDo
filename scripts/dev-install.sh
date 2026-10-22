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
DEST=/Applications

# The `metodo` command: a link into the app, so app updates update it too.
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
if [ -e "$BIN_DIR/metodo" ] && [ ! -L "$BIN_DIR/metodo" ]; then
  echo "Left $BIN_DIR/metodo alone (it isn't MeToDo's); the command is at $DEST/MeToDo.app/Contents/Helpers/metodo."
else
  ln -sfn "$DEST/MeToDo.app/Contents/Helpers/metodo" "$BIN_DIR/metodo"
  case ":$PATH:" in
    *":$BIN_DIR:"*) echo "The metodo command is ready: try 'metodo --help'." ;;
    *) echo "The metodo command is in $BIN_DIR, which isn't on your PATH. Add this to ~/.zshrc: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac
fi

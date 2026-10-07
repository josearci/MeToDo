#!/bin/bash
# Builds .build/MeToDo.app: release, universal (Apple Silicon + Intel), ad-hoc signed.
# Version is 1.0.<number of commits on HEAD>, so a local build of a commit matches its GitHub release.
# Updates come from the GitHub repo in METODO_UPDATE_REPO, else the "origin" remote.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)
REPO=${METODO_UPDATE_REPO:-$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##' || true)}
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/MeToDo"

APP=.build/MeToDo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MeToDo"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 1.0.$BUILD" -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
if [ -n "$REPO" ]; then
  /usr/libexec/PlistBuddy -c "Add :MeToDoUpdateRepo string $REPO" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
echo "Built $APP — MeToDo 1.0.$BUILD${REPO:+, updates from github.com/$REPO}"

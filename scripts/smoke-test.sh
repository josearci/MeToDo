#!/bin/bash
# Launches a built MeToDo.app the ways users do and checks it actually shows up:
# first launch and relaunch open the window, a launch at login stays in the menu bar, nothing crashes.
# CI runs it on every supported macOS. Uses the app's real data folder, so run it on a clean machine
# (or a copy with another bundle id).
#
#   scripts/smoke-test.sh .build/MeToDo.app
set -euo pipefail
APP=$(cd "$1" && pwd)
BIN="$APP/Contents/MacOS/MeToDo"
ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
TOOLS=$(mktemp -d)
trap 'pkill -9 -f "$BIN" 2>/dev/null || true; rm -rf "$TOOLS"' EXIT

# windows <pid>: "<normal windows on screen> <status bar windows>" (window bounds need no screen-recording permission)
cat > "$TOOLS/windows.swift" <<'EOF'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = all.filter { $0[kCGWindowOwnerPID as String] as? Int == pid }
let normal = mine.filter { $0[kCGWindowLayer as String] as? Int == 0 && $0[kCGWindowIsOnscreen as String] as? Bool == true
    && ((($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double) ?? 0) >= 400 }
let status = mine.filter { $0[kCGWindowLayer as String] as? Int == 25 }
print(normal.count, status.count)
EOF
# locked: exits 0 when the screen is locked (nothing counts as on screen then)
cat > "$TOOLS/locked.swift" <<'EOF'
import CoreGraphics
let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
exit(session["CGSSessionScreenIsLocked"] as? Bool == true ? 0 : 1)
EOF
# loginlaunch <app>: launches the app the way macOS does for a login item
cat > "$TOOLS/loginlaunch.swift" <<'EOF'
import AppKit
let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
    targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
let config = NSWorkspace.OpenConfiguration()
config.appleEvent = event
config.activates = false
let done = DispatchSemaphore(value: 0)
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: CommandLine.arguments[1]), configuration: config) { _, error in
    if let error { print(error) }
    done.signal()
}
done.wait()
EOF
swiftc -O "$TOOLS/windows.swift" -o "$TOOLS/windows" 2>/dev/null
swiftc -O "$TOOLS/loginlaunch.swift" -o "$TOOLS/loginlaunch" 2>/dev/null
swiftc -O "$TOOLS/locked.swift" -o "$TOOLS/locked" 2>/dev/null
if "$TOOLS/locked"; then echo "The screen is locked, so windows can't be checked. Unlock it and run again." >&2; exit 2; fi

FAILED=0
pid() { pgrep -f "$BIN" | head -1; }
quit() { pkill -9 -f "$BIN" 2>/dev/null || true; while pgrep -f "$BIN" >/dev/null; do sleep 0.2; done; sleep 1; }
# expect <label> <window count wanted>: waits up to 15 s for the app to settle into that state
expect() {
  local label=$1 want=$2 got="" p
  for _ in $(seq 30); do
    sleep 0.5
    p=$(pid) || true
    [ -n "$p" ] || continue
    got=$("$TOOLS/windows" "$p")
    [ "${got%% *}" = "$want" ] && [ "$want" != 0 ] && break
  done
  [ "$want" = 0 ] && sleep 3 && p=$(pid) && got=$("$TOOLS/windows" "$p")   # a window must not appear late either
  if [ -z "${p:-}" ]; then echo "FAIL $label: MeToDo isn't running"; FAILED=1; return; fi
  if [ "${got%% *}" = "$want" ]; then echo "ok   $label (windows: ${got%% *}, status bar windows: ${got##* })"
  else echo "FAIL $label: $want window(s) expected, saw ${got%% *}"; FAILED=1; fi
}

echo "MeToDo $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist") on macOS $(sw_vers -productVersion) $(uname -m)"
defaults delete "$ID" 2>/dev/null || true
quit
open "$APP";              expect "first launch shows the window" 1
quit; open "$APP";        expect "relaunch shows the window" 1
quit; "$TOOLS/loginlaunch" "$APP"; expect "launch at login stays in the menu bar" 0
open "$APP";              expect "opening it while running shows the window" 1
quit

if ls ~/Library/Logs/DiagnosticReports/MeToDo* >/dev/null 2>&1; then
  echo "FAIL crash reports:"; ls ~/Library/Logs/DiagnosticReports/MeToDo*; FAILED=1
else
  echo "ok   no crash reports"
fi
exit $FAILED

#!/bin/sh
set -eu

APP=${1:-}
RID=${2:-}
if [ -z "$APP" ] || [ -z "$RID" ]; then
  echo "usage: scripts/audit-macos-bundle.sh <app-bundle> <osx-arm64|osx-x64>" >&2
  exit 2
fi

EXECUTABLE="$APP/Contents/MacOS/CodexMonitorHud"
PLIST="$APP/Contents/Info.plist"
test -d "$APP"
test -f "$PLIST"
test -x "$EXECUTABLE"
plutil -lint "$PLIST"

EXPECTED_ARCH=arm64
if [ "$RID" = "osx-x64" ]; then EXPECTED_ARCH=x86_64; fi
file "$EXECUTABLE" | grep -q "$EXPECTED_ARCH"

if find "$APP" -type f \( -name '*.jsonl' -o -name '*.db' -o -name '*.sqlite' -o -name '*.log' \) | grep -q .; then
  echo "bundle contains a forbidden data/log file" >&2
  exit 1
fi
if grep -R -I -E 'C:\\Users\\|/Users/[^/]+/\.codex|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' "$APP" >/dev/null 2>&1; then
  echo "bundle privacy scan found a local path or private-key marker" >&2
  exit 1
fi

echo "macOS bundle audit: OK ($RID, unsigned)"

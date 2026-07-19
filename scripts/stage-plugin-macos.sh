#!/bin/sh
set -eu

ROOT=${1:-}
DESTINATION=${2:-}
if [ -z "$ROOT" ] || [ -z "$DESTINATION" ]; then
  echo "usage: scripts/stage-plugin-macos.sh <repository-root> <destination>" >&2
  exit 2
fi

rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
(
  cd "$ROOT"
  tar -cf - \
    --exclude='./.git' \
    --exclude='./.agents' \
    --exclude='./.codex' \
    --exclude='./private' \
    --exclude='./artifacts' \
    --exclude='./.test-output' \
    --exclude='./runtime' \
    --exclude='./node_modules' \
    --exclude='./sessions' \
    --exclude='./logs' \
    --exclude='./archive' \
    --exclude='*/bin' \
    --exclude='*/obj' \
    --exclude='*.jsonl' \
    --exclude='*.log' \
    --exclude='*.db' \
    --exclude='*.sqlite' \
    --exclude='*.sqlite3' \
    --exclude='*.zip' \
    --exclude='settings.json' \
    --exclude='.env*' \
    .
) | (
  cd "$DESTINATION"
  tar -xf -
)

test -f "$DESTINATION/.codex-plugin/plugin.json"
test -f "$DESTINATION/src/mcp-server.mjs"
test -f "$DESTINATION/scripts/install-macos.sh"
if find "$DESTINATION" -type f \( -name '*.jsonl' -o -name '*.db' -o -name '*.sqlite' -o -name '*.log' \) | grep -q .; then
  echo "staged plugin contains a forbidden local-data file" >&2
  exit 1
fi
echo "macOS plugin stage: OK"

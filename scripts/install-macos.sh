#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
USER_HOME=${HOME:?HOME is required}
INSTALL_ROOT=${CODEX_MONITOR_HUD_INSTALL_ROOT:-"$USER_HOME/Applications/CodexMonitorHUD.app"}
STATE_ROOT=${CODEX_MONITOR_HUD_STATE_ROOT:-"$USER_HOME/Library/Application Support/CodexMonitorHUD"}
PLUGIN_ROOT=${CODEX_MONITOR_HUD_PLUGIN_ROOT:-"$USER_HOME/plugins/codex-monitor-hud"}
MARKETPLACE_PATH=${CODEX_MONITOR_HUD_MARKETPLACE_PATH:-"$USER_HOME/.agents/plugins/marketplace.json"}
ROLLBACK_ROOT="$(dirname -- "$INSTALL_ROOT")/CodexMonitorHUD.rollback.app"
FAILED_ROOT="$(dirname -- "$INSTALL_ROOT")/CodexMonitorHUD.failed.app"
PLUGIN_ROLLBACK_ROOT="$(dirname -- "$PLUGIN_ROOT")/.codex-monitor-hud-rollback"
PLUGIN_FAILED_ROOT="$(dirname -- "$PLUGIN_ROOT")/.codex-monitor-hud-failed"
MANIFEST="$ROOT/install-manifest.json"
OPERATION=install

case "${1:-}" in
  "") ;;
  --repair) OPERATION=repair ;;
  --rollback) OPERATION=rollback ;;
  --uninstall) OPERATION=uninstall ;;
  --verify) OPERATION=verify ;;
  *) echo "usage: scripts/install-macos.sh [--repair|--rollback|--uninstall|--verify]" >&2; exit 2 ;;
esac

if [ "$(uname -s)" != "Darwin" ]; then
  echo "status=unsupported platform=$(uname -s)" >&2
  exit 3
fi

case "$(uname -m)" in
  arm64) ARCH=arm64; RID=osx-arm64 ;;
  *) echo "status=unsupported architecture=$(uname -m) supported=arm64" >&2; exit 3 ;;
esac

VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
REPOSITORY=$(sed -n 's/.*"repository": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
TAG=$(sed -n 's/.*"releaseTag": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
ASSET="CodexMonitorHUD-macos-$ARCH.zip"
HEARTBEAT="$STATE_ROOT/hud.heartbeat"
NODE_CMD=$(command -v node || true)

summary() {
  printf '%s\n' \
    "status=$1" \
    "version=$VERSION" \
    "platform=macos" \
    "architecture=$ARCH" \
    "installRoot=$INSTALL_ROOT" \
    "pluginRoot=$PLUGIN_ROOT" \
    "config=$STATE_ROOT/settings.json" \
    "heartbeat=$2" \
    "rollbackPath=$ROLLBACK_ROOT" \
    "pluginRollbackPath=$PLUGIN_ROLLBACK_ROOT"
}

verify_install() {
  EXPECTED_VERSION=${1:-$VERSION}
  test -d "$INSTALL_ROOT/Contents/MacOS"
  test -x "$INSTALL_ROOT/Contents/MacOS/CodexMonitorHud"
  plutil -lint "$INSTALL_ROOT/Contents/Info.plist" >/dev/null
  file "$INSTALL_ROOT/Contents/MacOS/CodexMonitorHud" | grep -q arm64
  mkdir -p "$STATE_ROOT"
  "$INSTALL_ROOT/Contents/MacOS/CodexMonitorHud" --health-check "$STATE_ROOT/install-health.json"
  HEALTH_VERSION=$(sed -n 's/.*"version":"\([^"]*\)".*/\1/p' "$STATE_ROOT/install-health.json" | head -n 1)
  test "$HEALTH_VERSION" = "$EXPECTED_VERSION"
  test -f "$PLUGIN_ROOT/.codex-plugin/plugin.json"
  test -f "$PLUGIN_ROOT/src/mcp-server.mjs"
  PLUGIN_VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.codex-plugin/plugin.json" | head -n 1)
  test "$PLUGIN_VERSION" = "$EXPECTED_VERSION"
  test -n "$NODE_CMD"
  "$NODE_CMD" --check "$PLUGIN_ROOT/src/mcp-server.mjs"
}

if [ "$OPERATION" = uninstall ]; then
  if [ -n "$NODE_CMD" ] && [ -f "$ROOT/scripts/update-marketplace.mjs" ]; then
    "$NODE_CMD" "$ROOT/scripts/update-marketplace.mjs" "$MARKETPLACE_PATH" uninstall
  fi
  rm -rf "$INSTALL_ROOT"
  rm -rf "$PLUGIN_ROOT"
  summary uninstalled preserved
  exit 0
fi

if [ "$OPERATION" = rollback ]; then
  if [ ! -d "$ROLLBACK_ROOT" ] || [ ! -d "$PLUGIN_ROLLBACK_ROOT" ]; then
    echo "status=failed reason=no-rollback" >&2
    exit 4
  fi
  if [ -z "$NODE_CMD" ]; then echo "status=failed reason=node-missing" >&2; exit 4; fi
  ROLLBACK_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/codex-monitor-hud-rollback.XXXXXX")
  MARKETPLACE_EXISTED=0
  if [ -f "$MARKETPLACE_PATH" ]; then
    MARKETPLACE_EXISTED=1
    cp "$MARKETPLACE_PATH" "$ROLLBACK_TEMP/marketplace.backup"
  fi
  rm -rf "$FAILED_ROOT"
  rm -rf "$PLUGIN_FAILED_ROOT"
  if [ -d "$INSTALL_ROOT" ]; then mv "$INSTALL_ROOT" "$FAILED_ROOT"; fi
  if [ -d "$PLUGIN_ROOT" ]; then mv "$PLUGIN_ROOT" "$PLUGIN_FAILED_ROOT"; fi
  mv "$ROLLBACK_ROOT" "$INSTALL_ROOT"
  mv "$PLUGIN_ROLLBACK_ROOT" "$PLUGIN_ROOT"
  ROLLBACK_VERSION=$(sed -n 's/.*"version": "\([^"]*\)".*/\1/p' "$PLUGIN_ROOT/.codex-plugin/plugin.json" | head -n 1)
  restore_failed_rollback() {
    if [ -d "$INSTALL_ROOT" ]; then mv "$INSTALL_ROOT" "$ROLLBACK_ROOT"; fi
    if [ -d "$PLUGIN_ROOT" ]; then mv "$PLUGIN_ROOT" "$PLUGIN_ROLLBACK_ROOT"; fi
    if [ -d "$FAILED_ROOT" ]; then mv "$FAILED_ROOT" "$INSTALL_ROOT"; fi
    if [ -d "$PLUGIN_FAILED_ROOT" ]; then mv "$PLUGIN_FAILED_ROOT" "$PLUGIN_ROOT"; fi
    if [ "$MARKETPLACE_EXISTED" = 1 ]; then
      mkdir -p "$(dirname -- "$MARKETPLACE_PATH")"
      cp "$ROLLBACK_TEMP/marketplace.backup" "$MARKETPLACE_PATH"
    else
      rm -f "$MARKETPLACE_PATH"
    fi
    rm -rf "$ROLLBACK_TEMP"
  }
  if ! "$NODE_CMD" "$PLUGIN_ROOT/scripts/update-marketplace.mjs" "$MARKETPLACE_PATH" install || \
     [ "${CODEX_MONITOR_HUD_TEST_FAIL_ROLLBACK:-0}" = 1 ] || \
     ! verify_install "$ROLLBACK_VERSION"; then
    restore_failed_rollback
    echo "status=failed reason=rollback-verification rollback=restored" >&2
    exit 7
  fi
  rm -rf "$ROLLBACK_TEMP" "$FAILED_ROOT" "$PLUGIN_FAILED_ROOT"
  summary rolled-back pending-launch
  exit 0
fi

if [ "$OPERATION" = verify ]; then
  verify_install
  if [ -f "$HEARTBEAT" ]; then summary verified present; else summary verified missing; fi
  exit 0
fi

TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codex-monitor-hud-install.XXXXXX")
trap 'rm -rf "$TEMP_ROOT"' EXIT HUP INT TERM
CHECKSUMS="$TEMP_ROOT/SHA256SUMS.txt"
ARCHIVE="$TEMP_ROOT/$ASSET"
SOURCE=release
BASE_URL="$REPOSITORY/releases/download/$TAG"
PLUGIN_CANDIDATE="$TEMP_ROOT/plugin-stage"
TEST_CANDIDATE_APP=${CODEX_MONITOR_HUD_TEST_CANDIDATE_APP:-}
if [ -z "$NODE_CMD" ]; then
  echo "status=failed reason=node-missing action=install-node-and-retry" >&2
  exit 5
fi
sh "$ROOT/scripts/stage-plugin-macos.sh" "$ROOT" "$PLUGIN_CANDIDATE"

download_status() {
  curl --proto '=https' --tlsv1.2 -L --silent --show-error -o "$2" -w '%{http_code}' "$1"
}

if [ -n "$TEST_CANDIDATE_APP" ]; then
  SOURCE=test-candidate
  CANDIDATE=$TEST_CANDIDATE_APP
else
  CHECKSUM_HTTP=$(download_status "$BASE_URL/SHA256SUMS.txt" "$CHECKSUMS") || {
    echo "status=failed reason=release-network" >&2
    exit 5
  }
  if [ "$CHECKSUM_HTTP" = 404 ]; then
    SOURCE=source
  elif [ "$CHECKSUM_HTTP" != 200 ]; then
    echo "status=failed reason=checksum-http-$CHECKSUM_HTTP" >&2
    exit 5
  fi

  if [ "$SOURCE" = release ]; then
    ASSET_HTTP=$(download_status "$BASE_URL/$ASSET" "$ARCHIVE") || {
      echo "status=failed reason=release-network" >&2
      exit 5
    }
    if [ "$ASSET_HTTP" = 404 ]; then
      SOURCE=source
    elif [ "$ASSET_HTTP" != 200 ]; then
      echo "status=failed reason=asset-http-$ASSET_HTTP" >&2
      exit 5
    fi
  fi

  if [ "$SOURCE" = release ]; then
    EXPECTED=$(awk -v name="$ASSET" '$2 == name || $2 == ("*" name) { print $1; exit }' "$CHECKSUMS")
    if [ -z "$EXPECTED" ]; then
      echo "status=failed reason=checksum-entry-missing" >&2
      exit 6
    fi
    ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
    if [ "$EXPECTED" != "$ACTUAL" ]; then
      echo "status=failed reason=checksum-mismatch" >&2
      exit 6
    fi
    ditto -x -k "$ARCHIVE" "$TEMP_ROOT/extracted"
    CANDIDATE="$TEMP_ROOT/extracted/CodexMonitorHUD.app"
  else
    SDK_VERSION=$(sed -n 's/.*"sdkVersion": "\([^"]*\)".*/\1/p' "$MANIFEST" | head -n 1)
    DOTNET_CMD=$(command -v dotnet || true)
    if [ -z "$DOTNET_CMD" ] || [ "$("$DOTNET_CMD" --version 2>/dev/null || true)" != "$SDK_VERSION" ]; then
      DOTNET_DIR="$STATE_ROOT/toolchain/dotnet"
      mkdir -p "$DOTNET_DIR"
      INSTALLER="$TEMP_ROOT/dotnet-install.sh"
      curl --proto '=https' --tlsv1.2 -fsSL https://dot.net/v1/dotnet-install.sh -o "$INSTALLER"
      sh "$INSTALLER" --version "$SDK_VERSION" --install-dir "$DOTNET_DIR" --no-path
      DOTNET_CMD="$DOTNET_DIR/dotnet"
    fi
    DOTNET_CMD="$DOTNET_CMD" sh "$ROOT/scripts/build-macos.sh" "$RID"
    CANDIDATE="$ROOT/artifacts/macos/$RID/CodexMonitorHUD.app"
  fi
fi

test -d "$CANDIDATE"
sh "$ROOT/scripts/audit-macos-bundle.sh" "$CANDIDATE" "$RID"
test -d "$PLUGIN_CANDIDATE"
mkdir -p "$(dirname -- "$INSTALL_ROOT")" "$(dirname -- "$PLUGIN_ROOT")" "$STATE_ROOT"
MARKETPLACE_EXISTED=0
if [ -f "$MARKETPLACE_PATH" ]; then
  MARKETPLACE_EXISTED=1
  cp "$MARKETPLACE_PATH" "$TEMP_ROOT/marketplace.backup"
fi
CURRENT_BACKUP="$ROLLBACK_ROOT"
PLUGIN_CURRENT_BACKUP="$PLUGIN_ROLLBACK_ROOT"
if [ "$OPERATION" = repair ] && [ -d "$ROLLBACK_ROOT" ]; then
  CURRENT_BACKUP="$FAILED_ROOT"
  rm -rf "$CURRENT_BACKUP"
else
  rm -rf "$ROLLBACK_ROOT"
fi
if [ "$OPERATION" = repair ] && [ -d "$PLUGIN_ROLLBACK_ROOT" ]; then
  PLUGIN_CURRENT_BACKUP="$PLUGIN_FAILED_ROOT"
  rm -rf "$PLUGIN_CURRENT_BACKUP"
else
  rm -rf "$PLUGIN_ROLLBACK_ROOT"
fi
if [ -d "$INSTALL_ROOT" ]; then mv "$INSTALL_ROOT" "$CURRENT_BACKUP"; fi
if [ -d "$PLUGIN_ROOT" ]; then mv "$PLUGIN_ROOT" "$PLUGIN_CURRENT_BACKUP"; fi
restore_transaction() {
  rm -rf "$INSTALL_ROOT"
  rm -rf "$PLUGIN_ROOT"
  if [ -d "$CURRENT_BACKUP" ]; then mv "$CURRENT_BACKUP" "$INSTALL_ROOT"; fi
  if [ -d "$PLUGIN_CURRENT_BACKUP" ]; then mv "$PLUGIN_CURRENT_BACKUP" "$PLUGIN_ROOT"; fi
  if [ "$MARKETPLACE_EXISTED" = 1 ]; then
    mkdir -p "$(dirname -- "$MARKETPLACE_PATH")"
    cp "$TEMP_ROOT/marketplace.backup" "$MARKETPLACE_PATH"
  else
    rm -f "$MARKETPLACE_PATH"
  fi
}
if ! ditto "$CANDIDATE" "$INSTALL_ROOT" || ! ditto "$PLUGIN_CANDIDATE" "$PLUGIN_ROOT"; then
  restore_transaction
  echo "status=failed reason=install-copy rollback=restored" >&2
  exit 7
fi

if ! "$NODE_CMD" "$PLUGIN_ROOT/scripts/update-marketplace.mjs" "$MARKETPLACE_PATH" install; then
  restore_transaction
  echo "status=failed reason=marketplace rollback=restored" >&2
  exit 7
fi

if [ "${CODEX_MONITOR_HUD_TEST_FAIL_AFTER_SWITCH:-0}" = 1 ] || ! verify_install; then
  restore_transaction
  echo "status=failed reason=health-check rollback=restored" >&2
  exit 7
fi
if [ "$CURRENT_BACKUP" = "$FAILED_ROOT" ]; then rm -rf "$FAILED_ROOT"; fi
if [ "$PLUGIN_CURRENT_BACKUP" = "$PLUGIN_FAILED_ROOT" ]; then rm -rf "$PLUGIN_FAILED_ROOT"; fi

if [ "${CODEX_MONITOR_HUD_TEST_SKIP_LAUNCH:-0}" = 1 ]; then
  summary installed test-skipped
  exit 0
fi

BEFORE=0
if [ -f "$HEARTBEAT" ]; then BEFORE=$(stat -f '%m' "$HEARTBEAT" 2>/dev/null || echo 0); fi
open "$INSTALL_ROOT" || true
COUNT=0
while [ "$COUNT" -lt 10 ]; do
  AFTER=0
  if [ -f "$HEARTBEAT" ]; then AFTER=$(stat -f '%m' "$HEARTBEAT" 2>/dev/null || echo 0); fi
  if [ "$AFTER" -gt "$BEFORE" ]; then
    summary installed fresh
    exit 0
  fi
  sleep 1
  COUNT=$((COUNT + 1))
done

summary needs-user-approval missing
echo "action=Control-click the app and choose Open, or use System Settings > Privacy & Security > Open Anyway; then run --verify."
exit 10

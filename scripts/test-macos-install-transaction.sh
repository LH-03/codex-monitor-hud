#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CANDIDATE=${1:-}
RID=${2:-}
if [ -z "$CANDIDATE" ] || [ ! -d "$CANDIDATE" ]; then
  echo "usage: scripts/test-macos-install-transaction.sh <CodexMonitorHUD.app> <osx-arm64|osx-x64>" >&2
  exit 2
fi
case "$RID" in osx-arm64|osx-x64) ;; *) echo "invalid RID: $RID" >&2; exit 2 ;; esac

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/codex-monitor-hud-transaction.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM
export HOME="$TEST_ROOT/home"
export CODEX_MONITOR_HUD_INSTALL_ROOT="$HOME/Applications/CodexMonitorHUD.app"
export CODEX_MONITOR_HUD_STATE_ROOT="$HOME/Library/Application Support/CodexMonitorHUD"
export CODEX_MONITOR_HUD_PLUGIN_ROOT="$HOME/plugins/codex-monitor-hud"
export CODEX_MONITOR_HUD_MARKETPLACE_PATH="$HOME/.agents/plugins/marketplace.json"
export CODEX_MONITOR_HUD_TEST_CANDIDATE_APP="$CANDIDATE"
export CODEX_MONITOR_HUD_TEST_SKIP_LAUNCH=1
mkdir -p "$HOME/.agents/plugins" "$CODEX_MONITOR_HUD_STATE_ROOT"
printf '%s\n' '{"name":"personal","plugins":[{"name":"synthetic-unrelated","source":{"source":"local","path":"./plugins/synthetic"}}]}' > "$CODEX_MONITOR_HUD_MARKETPLACE_PATH"
printf '%s\n' '{"language":"zh-CN","syntheticPreserve":"settings-survive"}' > "$CODEX_MONITOR_HUD_STATE_ROOT/settings.json"

sh "$ROOT/scripts/install-macos.sh"
sh "$ROOT/scripts/install-macos.sh" --verify
grep -q 'settings-survive' "$CODEX_MONITOR_HUD_STATE_ROOT/settings.json"
grep -q 'synthetic-unrelated' "$CODEX_MONITOR_HUD_MARKETPLACE_PATH"
grep -q 'codex-monitor-hud' "$CODEX_MONITOR_HUD_MARKETPLACE_PATH"

# A second successful install creates paired app/plugin rollback trees.
sh "$ROOT/scripts/install-macos.sh"
test -d "$HOME/Applications/CodexMonitorHUD.rollback.app"
test -d "$HOME/plugins/.codex-monitor-hud-rollback"
BEFORE_MARKETPLACE=$(shasum -a 256 "$CODEX_MONITOR_HUD_MARKETPLACE_PATH" | awk '{print $1}')
BEFORE_PLUGIN=$(shasum -a 256 "$CODEX_MONITOR_HUD_PLUGIN_ROOT/.codex-plugin/plugin.json" | awk '{print $1}')

if CODEX_MONITOR_HUD_TEST_FAIL_AFTER_SWITCH=1 sh "$ROOT/scripts/install-macos.sh"; then
  echo "forced post-switch failure unexpectedly succeeded" >&2
  exit 1
fi
test "$BEFORE_MARKETPLACE" = "$(shasum -a 256 "$CODEX_MONITOR_HUD_MARKETPLACE_PATH" | awk '{print $1}')"
test "$BEFORE_PLUGIN" = "$(shasum -a 256 "$CODEX_MONITOR_HUD_PLUGIN_ROOT/.codex-plugin/plugin.json" | awk '{print $1}')"

sh "$ROOT/scripts/install-macos.sh" --rollback
sh "$ROOT/scripts/install-macos.sh" --verify

# Recreate rollback trees, then prove a failed rollback restores all three surfaces.
sh "$ROOT/scripts/install-macos.sh"
BEFORE_MARKETPLACE=$(shasum -a 256 "$CODEX_MONITOR_HUD_MARKETPLACE_PATH" | awk '{print $1}')
BEFORE_PLUGIN=$(shasum -a 256 "$CODEX_MONITOR_HUD_PLUGIN_ROOT/.codex-plugin/plugin.json" | awk '{print $1}')
if CODEX_MONITOR_HUD_TEST_FAIL_ROLLBACK=1 sh "$ROOT/scripts/install-macos.sh" --rollback; then
  echo "forced rollback failure unexpectedly succeeded" >&2
  exit 1
fi
test "$BEFORE_MARKETPLACE" = "$(shasum -a 256 "$CODEX_MONITOR_HUD_MARKETPLACE_PATH" | awk '{print $1}')"
test "$BEFORE_PLUGIN" = "$(shasum -a 256 "$CODEX_MONITOR_HUD_PLUGIN_ROOT/.codex-plugin/plugin.json" | awk '{print $1}')"
sh "$ROOT/scripts/install-macos.sh" --verify

sh "$ROOT/scripts/install-macos.sh" --uninstall
test ! -e "$CODEX_MONITOR_HUD_INSTALL_ROOT"
test ! -e "$CODEX_MONITOR_HUD_PLUGIN_ROOT"
test -f "$CODEX_MONITOR_HUD_STATE_ROOT/settings.json"
grep -q 'synthetic-unrelated' "$CODEX_MONITOR_HUD_MARKETPLACE_PATH"
if grep -q 'codex-monitor-hud' "$CODEX_MONITOR_HUD_MARKETPLACE_PATH"; then
  echo "uninstall left the HUD marketplace entry behind" >&2
  exit 1
fi

echo "macOS app/plugin/settings/marketplace transaction: OK ($RID)"

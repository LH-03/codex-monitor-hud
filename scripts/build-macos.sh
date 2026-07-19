#!/bin/sh
set -eu

RID="${1:-}"
case "$RID" in
  osx-arm64|osx-x64) ;;
  *) echo "usage: scripts/build-macos.sh <osx-arm64|osx-x64>" >&2; exit 2 ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DOTNET_CMD=${DOTNET_CMD:-dotnet}
OUT="$ROOT/artifacts/macos/$RID"
PUBLISH="$OUT/publish"
APP="$OUT/CodexMonitorHUD.app"
HEALTH="$OUT/health-check.json"

rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

AVALONIA_TELEMETRY_OPTOUT=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 \
  "$DOTNET_CMD" publish "$ROOT/src-dotnet/CodexMonitorHud.Mac/CodexMonitorHud.Mac.csproj" \
  -c Release -f net10.0 -r "$RID" --self-contained true -p:UseAppHost=true \
  -p:RestoreLockedMode=true -o "$PUBLISH"

cp "$ROOT/src-dotnet/CodexMonitorHud.Mac/Info.plist" "$APP/Contents/Info.plist"
cp -R "$PUBLISH/." "$APP/Contents/MacOS/"
chmod +x "$APP/Contents/MacOS/CodexMonitorHud"
"$APP/Contents/MacOS/CodexMonitorHud" --health-check "$HEALTH"

sh "$ROOT/scripts/audit-macos-bundle.sh" "$APP" "$RID"

(
  cd "$OUT"
  find CodexMonitorHUD.app -type f -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done > bundle-files.sha256
  ditto -c -k --keepParent CodexMonitorHUD.app "CodexMonitorHUD-macos-${RID#osx-}.zip"
  shasum -a 256 "CodexMonitorHUD-macos-${RID#osx-}.zip" > SHA256SUMS.txt
)

echo "macOS unsigned bundle: $APP"

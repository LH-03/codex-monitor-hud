# Codex Token HUD — macOS Preview Test Guide

Codex Token HUD is a free and open-source HUD for Codex Desktop. macOS support is currently a **preview** because it has only received limited real-device testing.

This test is voluntary and unpaid. Test results, bug reports, and pull requests are welcome.

Repository:

```text
https://github.com/LH-03/codex-token-hud
```

## 1. Before testing

Please confirm that you have:

- macOS 13 or later
- Codex Desktop installed
- An Intel Mac or Apple Silicon Mac
- No sensitive Codex conversation content visible in screenshots or logs

Do not post API keys, access tokens, account information, private file paths, or Codex conversation content.

## 2. Choose the correct build

Download the latest macOS preview release from the repository's **Releases** page.

Choose:

- `macos-x64` for Intel Macs
- `macos-arm64` for Apple Silicon Macs, including M1, M2, M3, M4 and later

To check your architecture, open Terminal and run:

```bash
uname -m
```

Result:

- `x86_64` → download the x64 build
- `arm64` → download the arm64 build

## 3. Install and launch

1. Download the matching ZIP from the latest macOS preview release.
2. Extract the ZIP.
3. Move `CodexMonitorHUD.app` to `Applications` or `~/Applications`.
4. Try to open the app normally.

Record exactly what happens:

- Opens normally
- Shows an “unidentified developer” warning
- Shows an “app is damaged” warning
- Opens and immediately exits
- Opens but the HUD does not appear
- Opens and works normally

## 4. If macOS says the app is damaged

Only run the following commands on the downloaded `CodexMonitorHUD.app`.

Replace the path if your app is not in `~/Applications`.

```bash
APP="$HOME/Applications/CodexMonitorHUD.app"

codesign --remove-signature "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
xattr -dr com.apple.quarantine "$APP"
codesign --verify --deep --strict --verbose=4 "$APP"
open "$APP"
```

If the app is in `/Applications`, use:

```bash
APP="/Applications/CodexMonitorHUD.app"
```

If the repair still fails, collect the following output:

```bash
uname -m
sw_vers
file "$APP/Contents/MacOS/"*
codesign -dv --verbose=4 "$APP" 2>&1
codesign --verify --deep --strict --verbose=4 "$APP" 2>&1
xattr -lr "$APP"
```

Please remove personal usernames and private paths before posting the output.

## 5. Test checklist

Please test the following:

- [ ] The ZIP downloads and extracts normally
- [ ] The correct x64 or arm64 build was selected
- [ ] The app launches
- [ ] The HUD or menu bar icon appears
- [ ] The app remains running for at least one minute
- [ ] Codex Desktop can be opened at the same time
- [ ] The HUD detects Codex activity
- [ ] Token or task information updates
- [ ] Settings can be opened
- [ ] The HUD can be moved or configured
- [ ] The app exits normally
- [ ] The app launches again after being closed
- [ ] Existing settings remain after restart

## 6. Report template

Copy this template into the public macOS testing issue:

```markdown
### Environment

- Mac model:
- Chip: Intel / Apple Silicon
- `uname -m` result:
- macOS version:
- Codex Desktop version:
- Preview build filename:

### Installation result

- ZIP extracted successfully: Yes / No
- App opened without repair: Yes / No
- Warning shown:
- Repair commands required: Yes / No
- App remained running: Yes / No

### Functional result

- HUD or menu bar icon appeared: Yes / No
- Codex activity detected: Yes / No
- Token/task values updated: Yes / No
- Settings opened: Yes / No
- Exit and restart worked: Yes / No
- Settings survived restart: Yes / No

### Failure details

- What happened:
- Reproduction steps:
- Screenshot:
- Terminal output:
- Crash log:

### Additional notes

-
```

## 7. Pull requests

Fixes and pull requests are welcome. Please include:

- Mac architecture
- macOS version
- The original failure
- The exact change
- How the change was tested
- Whether Windows behavior remains unchanged

Thank you for helping validate the macOS preview.

# Codex Monitor HUD — macOS Preview Test Guide

Codex Monitor HUD is a free, open-source and unofficial HUD for local Codex task activity. macOS support is a preview because interactive real-device coverage is still limited.

Testing is voluntary and unpaid. The current macOS release target is Apple silicon (`arm64`) only. Intel Macs and other architectures are not supported by this preview.

## Current evidence boundary

[GitHub Actions run 4](https://github.com/LH-03/codex-monitor-hud/actions/runs/29679571150) passed the native Apple-silicon baseline. It verifies native restore/build, Core tests, executable architecture, plist validity, privacy-safe bundle inspection, bounded health output, six synthetic host modes, installation transactions and checksums.

Actions do **not** verify Gatekeeper prompts, visual fidelity, menu-bar recovery, notifications, multiple displays, Spaces, sleep/wake, live ChatGPT/Codex integration or long-running resource behavior. Those results require real Mac users.

## Requirements and test scope

- The HUD app bundle targets macOS 13 or later.
- OpenAI currently documents macOS 14 as the minimum for the new ChatGPT desktop app that includes Codex. See [OpenAI's current macOS requirements](https://help.openai.com/en/articles/9395554).
- A macOS 13 result is still useful for HUD launch and UI compatibility, but it must not be reported as validation of the current ChatGPT/Codex integration.
- Never upload Codex session files or inspect prompt, response or tool-output content for this test.

## 1. Choose the build

Download [macOS Preview 1](https://github.com/LH-03/codex-monitor-hud/releases/tag/v3.0.0-macos-preview.1):

- `CodexMonitorHUD-macos-arm64.zip` — Apple silicon (`arm64`);
- `SHA256SUMS.txt` — checksum for the arm64 ZIP.

Check the architecture:

```sh
uname -m
```

- `arm64` → continue with the arm64 ZIP.
- any other result → stop; the current preview does not support this architecture.

## 2. Verify the download

Keep `SHA256SUMS.txt` and the selected ZIP in the same directory. Compare the calculated line with the matching line in the checksum file:

```sh
cd "$HOME/Downloads"
shasum -a 256 CodexMonitorHUD-macos-arm64.zip
grep 'CodexMonitorHUD-macos-arm64.zip' SHA256SUMS.txt
```

Stop if the two hashes differ.

## 3. Test the original app before changing it

1. Extract the selected ZIP.
2. Move `CodexMonitorHUD.app` to `~/Applications` or `/Applications`.
3. Try a normal open once and record the exact result.
4. If macOS blocks an unidentified developer, Control-click the app, choose **Open**, and confirm **Open**.
5. If that choice is unavailable, use **System Settings → Privacy & Security → Open Anyway**.

The project is not signed with an Apple Developer ID and is not notarized. Manual approval is expected on some systems.

Do not disable Gatekeeper, clear quarantine, or re-sign the app as an ordinary installation step. If the app is reported as damaged or exits immediately, collect the original evidence below before modifying anything.

## 4. Collect launch diagnostics

Change `APP` only if the app is stored elsewhere:

```sh
APP="$HOME/Applications/CodexMonitorHUD.app"

uname -m
sw_vers
file "$APP/Contents/MacOS/CodexMonitorHud"
codesign -dv --verbose=4 "$APP" 2>&1
codesign --verify --deep --strict --verbose=4 "$APP" 2>&1
spctl --assess --type execute -vv "$APP" 2>&1
xattr -lr "$APP"
```

A rejected assessment is useful evidence; it is not an instruction to weaken macOS security. Remove personal usernames and private paths before posting output.

## 5. Interactive checklist

### Original package and launch

- [ ] Correct architecture selected
- [ ] ZIP hash matched `SHA256SUMS.txt`
- [ ] Original app tested before any local modification
- [ ] Normal open result recorded
- [ ] Control-click **Open** result recorded
- [ ] **Open Anyway** result recorded if offered
- [ ] App remained running for at least one minute

### HUD behavior

- [ ] HUD window or menu-bar item appeared
- [ ] Summary, list, split and quiet modes were visible
- [ ] Settings opened and saved changes
- [ ] Window movement and position persistence worked
- [ ] Menu-bar Show and Exit worked
- [ ] A second launch did not create a duplicate monitor
- [ ] Settings survived restart

### Current ChatGPT/Codex integration

Run this section only when the current ChatGPT desktop app with Codex is supported on the test machine.

- [ ] Local Codex activity was detected
- [ ] Task and token values updated
- [ ] Completion/abort state remained bounded and accurate
- [ ] Task navigation opened only the selected task

Report only visible outcomes. Do not attach the underlying JSONL files or conversation content.

### Environment behavior

- [ ] Notification allow/deny behavior recorded
- [ ] Multiple displays or display scaling recorded, if available
- [ ] Spaces/full-screen behavior recorded
- [ ] Sleep/wake behavior recorded
- [ ] Normal quit and relaunch worked

## 6. Report template

Post results in [macOS testing issue #5](https://github.com/LH-03/codex-monitor-hud/issues/5).

```markdown
### Environment

- Mac model:
- Chip and model:
- `uname -m`:
- macOS version:
- ChatGPT desktop/Codex version, or not installed:
- Preview filename:
- Calculated ZIP SHA-256:

### Original package result

- App was unmodified for this result: Yes / No
- ZIP checksum matched: Yes / No
- Normal open result:
- Control-click Open result:
- Open Anyway result:
- Exact warning or error:
- App remained running for at least one minute: Yes / No

### Functional result

- HUD appeared: Yes / No
- Menu-bar item appeared: Yes / No
- Summary/list/split/quiet checked:
- Settings opened and persisted: Yes / No
- Exit and restart worked: Yes / No
- Current ChatGPT/Codex integration was in scope: Yes / No
- Codex activity detected: Yes / No / Not tested
- Task/token values updated: Yes / No / Not tested

### Diagnostics and reproduction

- Reproduction steps:
- `codesign --verify` result:
- `spctl --assess` result:
- Relevant sanitized `xattr` result:
- Screenshot or crash report, if safe:

### Local modifications after original evidence

- App was re-signed: Yes / No
- Quarantine was cleared: Yes / No
- Any other modification:
- Result after modification:

### Additional notes

-
```

## Privacy notice

Before posting screenshots or logs, remove or hide:

- conversation content, prompts and task names;
- API keys, access tokens and account details;
- email addresses and personal usernames;
- private paths, filenames, project names and repository names.

There is no need to upload session files or contact the maintainer privately. Sanitized public reports, fixes and pull requests are welcome.

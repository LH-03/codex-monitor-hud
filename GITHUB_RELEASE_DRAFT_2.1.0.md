# GitHub Desktop and Release draft for v2.1.0

This is the current copy-ready publication handoff. It prepares a release from the local `main` branch; it does not create a commit, push, tag, or GitHub Release.

## GitHub Desktop commit

Branch: `main`

Summary:

```text
Release 2.1.0: multi-task HUD, display fixes, and bounded runtime work
```

Description:

```text
Finalize the stable v2.1.0 line.

- Restore two-line list task identity and fix the fully populated header so the task-count toggle is not clipped.
- Add bounded session/read/render reductions and document the PowerShell/WPF committed-memory boundary honestly.
- Cover list/split/quiet/terminal/title regressions with synthetic isolated WPF tests.
- Refresh bilingual product, architecture, test, installation, privacy, and release documentation.
- Add the Codex Micro display-reference attribution and non-affiliation/color-matching disclaimer.
- Add repeatable local release-package preparation with ZIP and SHA-256 output.
```

Select all intended public-source changes in GitHub Desktop. Do not add `private/`, `.test-output/`, `artifacts/`, local settings, session records, logs, archives, or a stash.

## Release fields

Target: `main` after the commit is pushed.

Tag:

```text
v2.1.0
```

Title:

```text
Codex Monitor HUD v2.1.0
```

Release body:

```markdown
## Codex Monitor HUD 2.1.0

Version 2.1.0 is the stable Windows v2 line. It combines the multi-task display work from the v2 previews with behavior controls, title handling, and runtime-path reductions validated together.

### User-visible changes

- Summary, expandable list, and independent split-bubble modes share one task state model.
- Every list row has a project/workspace main title and a subtitle line; the subtitle can reveal or always show the local Codex conversation title with time.
- Task-list information uses Compact, Balanced, and Detailed presets.
- Optional quiet mode supports one overall light or numbered horizontal/vertical task lights; terminal colors remain visible while quiet.
- Optional context alerts use editable thresholds and animate only the context metric.
- Optional double-click navigation uses a validated Codex task deep link.
- Symbol-only labels use a compact geometric vocabulary.
- The Codex Micro display-reference scheme is available alongside existing palettes. Its five values are sampled visual references, not an official OpenAI HUD palette or a color-match guarantee; see `COLOR_ATTRIBUTION.md` in the source repository.

### Runtime and privacy

- Locale, appearance, metric structure, list projection, quiet projection, and menu text are cached.
- Unchanged timer ticks do not rebuild the WPF surface; session tails use bounded streaming reads and irrelevant records are rejected before full JSON parsing.
- Settings and Color Picker use an on-demand process rather than remaining resident with the HUD.
- All monitoring remains local. The HUD does not upload data, write Codex session files, or derive status from prompt, reply, or tool-output text.

### Important limits

- Windows PowerShell/WPF can retain a high private committed-memory watermark after bursts even when physical working set is reduced. A materially lower committed-memory floor needs a future compiled .NET resident host.
- The Codex Micro reference is not an affiliation, endorsement, calibration target, or promise of matching a web page or hardware LEDs. Device, color-management, accessibility, transparency, and theme differences can alter the visible result.

See the README, TEST_RESULTS.md, COLOR_ATTRIBUTION.md, and docs/PROJECT_STATUS.md in the source repository for details.
```

Mark the GitHub Release as a normal release, not a pre-release. Attach the ZIP and SHA-256 from the local release-preparation output described below.

## Suggested screenshot order

1. `assets/hud-frost.png` — compact HUD.
2. `assets/hud-multitask-en.png` — task-list identity and multi-task projection.
3. `assets/settings.png` / `assets/settings-en.png` — current General settings.
4. `assets/settings-appearance.png` / `assets/settings-appearance-en.png` — Appearance settings, including the visible Codex Micro display-reference disclaimer.
5. `assets/settings-behavior.png` / `assets/settings-behavior-en.png` — navigation, quiet indicators, and context thresholds.

All repository screenshots use synthetic/default data only.

## Local package command

Run after the last package-affecting edit and before creating the GitHub Release:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\prepare-release.ps1
```

It writes an ignored `artifacts/release-v2.1.0-<timestamp>/` folder containing the ZIP, `SHA256SUMS.txt`, package file list, and `RELEASE_UPLOAD.md` with the exact attachment fields.

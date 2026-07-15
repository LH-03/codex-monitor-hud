# Project status

Last updated: 2026-07-15

## Current release

The current patch build is the **preview** `2.0.1-preview`; GitHub publication remains entirely user-controlled. It adds configurable completed-task retention, mixed-DPI text clarity and shadow-free persistent HUD surfaces.

## Unreleased local acceptance work

- Frequent Token records no longer replay the whole-window fade. Update animation is signature-gated to task membership, display mode, and status-phase changes, is much subtler, and does not override explicit completion or Codex notice effects.
- Broad all-date discovery no longer equals visible-task membership. Internal subagent sessions remain hidden, completed user tasks stay visible for a configurable terminal hold, and a bounded UTF-8 tail reader prevents final lifecycle records from being lost on Windows PowerShell 5.1.
- List rows use `project · Codex thread title` as their default identity. The title is live-read from `session_index.jsonl`, matching Codex Usage Tracker instead of parsing prompt text; hover adds start time, project-only remains optional, and the title is not persisted to the MCP task registry.
- List rows and independent bubbles have a matched dismiss action. It changes only in-memory HUD visibility and resets when the same conversation emits a later `task_started` event.
- If a running conversation file is removed, the next bounded scan removes its state and closes its independent bubble. With no visible tasks, the summary now says that there are no active Codex tasks instead of waiting forever for a usage record.
- Completion attention now represents a visible completed turn, not every internal/silent `task_complete` record. It waits through an eight-second continuation guard and is cancelled when the task immediately resumes.
- Attention is surface-local: summary mode reacts on the summary, list mode on only the matching row, and split mode on only the matching independent bubble.
- The reminder settings are reorganized and use contextual bilingual tooltips to explain Codex turn semantics without exposing prompt or response content.
- A new multi-resolution HUD/wave/status icon is wired to WPF windows as well as the tray, shortcut and plugin identity. The first local install proved that setting WPF `Window.Icon` alone still allowed Windows to group the settings window under PowerShell and that Explorer retained the old shortcut icon path. The accepted fix assigns a dedicated AppUserModelID, sends native large/small window icons after HWND creation, and uses a build-specific shortcut icon cache path.
- Theme Workshop accepts drag-and-drop declarative themes and safe rich ZIP theme packs. Themes can control surfaces, gradients or local images, typography, borders, shadows, density, task presentation, status-dot appearance and reminder appearance in addition to colors.
- User themes live outside the plugin under `%LOCALAPPDATA%\CodexMonitorHUD\themes`, so plugin updates do not erase them.
- API-equivalent cost is opt-in and independently selectable for the summary, list rows and task bubbles. It uses task-cumulative input/cached-input/output tokens and local prices, defaults to a bundled snapshot, accepts a tracker-compatible custom JSON, and never guesses unknown models.
- Cost is explicitly not billing or exact credits. Work and Codex may share an agentic allowance, but only local Codex activity is measurable here; the UI does not expose full pricing-file paths.
- Proactive Codex notices are separately authorized and default off. New tasks discover the tool and query current permission rather than inheriting another conversation's memory. A notice is plain text, visibly CODEX-labeled, targeted to one task and may be sent while the same turn continues.
- Expressive permission accepts only bounded declarative glow/pulse/breathe/flow choreography. Notice color, glow preset, intensity, duration and default motion are separate from automatic completion/error reminders; themes can style but cannot enable or authorize this channel.
- Active-session discovery now evaluates recent writes across every creation-date folder. This fixes resumed older conversations that previously alternated inside one list row and caused repeat numbering instead of appearing concurrently.
- The installer and `INSTALL_WITH_CODEX.md` preserve basic-monitoring defaults on first install, then present advanced DIY capabilities as explicit user choices.
- `docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md` explains the architecture and adaptation boundaries for other platforms and agent runtimes; `skills/create-monitor-hud-theme` is the distributable theme-authoring Skill.
- Test build `2.0.0-preview` is installed locally. Source/install parity is 85 files; the live registry exposes the one current user task while excluding recent internal/completed sessions. No public clone, Commit, Push, Release or Issue operation is part of this acceptance cycle.

## v2.0.0 rename work in progress

- Public product identity: Codex Monitor HUD.
- New plugin/MCP/Skill identity: `codex-monitor-hud`.
- New runtime settings root: `%LOCALAPPDATA%\CodexMonitorHUD`.
- The new installer refused to run while the legacy `codex-token-strip` plugin was present; the legacy plugin was then removed with its old settings retained.
- The v2 marketplace entry, new settings root, heartbeat and shortcuts are verified.
- Source/install parity is 73 files with zero missing, extra or changed files.
- GitHub repository rename, Commit, Push and Release remain pending user action.

- Visual presets and bubble layouts are independent.
- Six bubble layouts are public: `chips`, `compact`, `inline`, `outline`, `cards`, and `stacked`.
- Weekly remaining allowance is a public opt-in metric sourced from local `token_count.rate_limits` observations.
- Concurrent tasks use the newest account-wide allowance observation; percentages are never summed or averaged.

## v1.3.1 baseline

- Optional mouse click-through is implemented in the maintenance source and defaults to off.
- Recovery remains available through settings, installed settings shortcuts and a dedicated MCP disable tool. An uninstalled maintenance fix additionally adds a permanent notification-area recovery menu.
- Complete final JSONL records are parsed before a trailing newline arrives.
- Weekly allowance observations are ordered by their own timestamps instead of inheriting task-usage freshness.
- Font size previews and persists at 0.1-point precision.
- Four status color schemes are available without removing per-state ARGB editing.

Build `1.3.1+codex.20260714170852` fixes Windows PowerShell 5.1 notification-area label encoding by loading Chinese and English text from UTF-8 locale JSON. It is installed locally and remains the acceptance baseline while v1.4.0 is developed only in the maintenance source.

## v1.4.0 local acceptance build (installed)

- The maintenance source now has summary, list and split display modes with single-task and global detach/merge behavior.
- Stable task numbers, workspace-leaf labels, hover name reveal, number cooldown and bounded stale state are implemented without a new database.
- Per-task rows and bubbles reuse the shared incremental parser. Weekly allowance remains account-wide on the main summary only.
- Settings are divided into General, Multi-task, Metrics and Appearance tabs. Tray display-mode controls remain usable during mouse click-through.
- The default independent-bubble limit is 6, normalized to a maximum of 12; active session discovery remains capped at 64 files.
- List mode now offers compact rows, information cards and a status rail.
- Explicit completion/abort lifecycle events drive completed and aborted states. Completion, abort/error and natural-settling reminders are configurable separately.
- Reminder styles are independent for the summary bubble, relevant list task item and independent task bubble; list/task modes can animate the entire relevant surface.
- Opacity now reaches 15%, with uniform, layered-clarity and smart-focus behaviors that keep important information more visible than decoration.
- Stable-number pressure testing covers 10,000 allocation/release cycles with 64 continuously visible tasks and a bounded reuse pool.
- English and Chinese README content and screenshots now foreground the lightweight high-concurrency Pro workflow.
- Static tests pass. Isolated Windows runtime tests reached a live heartbeat and exited cleanly with 80 synthetic tasks and two complete replacement cycles in both list and split modes. The split test exposed and then verified a fix for blank JSONL lines during file churn.

Build `1.4.0+codex.20260714233609` was formally installed on 2026-07-14 after source tests, visual checks, isolated 80-task churn validation and a sensitive-information scan. The installer preserved existing user settings, refreshed the personal marketplace entry and settings shortcuts, removed obsolete installed-plugin files, and produced full file-hash parity between the maintenance source and installed copy. A fresh HUD heartbeat was observed; Windows login startup remains disabled. The public clone and GitHub remain untouched.

## v1.4.1 local acceptance build (installed)

- Task-list vertical density is independently selectable as Compact, Balanced or Relaxed; Compact is the default and all three list styles use the same density contract.
- Collapsing a list no longer hides its only expand control. The task counter remains available whenever at least one task is visible.
- List-row fields and independent-bubble fields are configured separately. Legacy `taskFields` choices migrate to the independent-bubble surface without replacing the new compact list defaults.
- Each independent task bubble has a subtle lower-right resize handle, bounded to safe desktop dimensions and retained for the lifetime of that active task.
- A manually dragged HUD position now appears as an explicit custom-position item, and ComboBox/list-toggle hover chrome matches the rounded interface.
- Source validation passed PowerShell/XAML parsing, configuration migration, visual previews, 10,000 numbering churn cycles and isolated 80-task list/split runs with two full churn cycles.

Build `1.4.1+codex.20260715000753` was installed locally after validation and a sensitive-information scan. Existing settings were preserved, source/install file hashes were checked, and the public clone and GitHub were not changed.

## v1.4.2 local acceptance build (installed)

- Status-dot reminders and per-surface reminders are independent and can run together.
- Dot controls cover soft/heartbeat/beacon rhythm, three brightness levels, three speeds and an optional subtle scale-breathing layer.
- Summary, relevant list item and independent bubble choose among off, soft halo, breathing, moving pulse light flow and strong focus pulse.
- Persistent summary/task bubbles use attention revisions, while regenerated list elements animate only during the bounded task-local reminder window and create no cleanup timers.
- One blue-violet AI-knot/terminal icon replaces the generic information and PowerShell icons across the tray, desktop shortcut, Start menu and plugin identity.
- Bilingual reminder screenshots and release text are included. Isolated 80-task list/split validation passed with two churn cycles in each mode.

Build `1.4.2+codex.20260715004349` was installed locally after validation. Existing settings were preserved, the installed copy was checked against the maintenance source, and the public clone was synchronized without committing or pushing.

## Dormant 5-hour allowance support

Codex currently does not consistently publish the 5-hour allowance window. Parsing support remains in `Convert-HudRecord` as `FiveHourRemainingPercent`, and synthetic coverage remains in `scripts/test.ps1`. It is intentionally absent from:

- `config.default.json` fields;
- `SettingsWindow.xaml` metric controls;
- locale files;
- `Get-HudMetrics` public values;
- README feature lists.

If Codex restores the 5-hour window, re-enable it with this small checklist:

1. Add `fiveHourRemaining: false` to `config.default.json`.
2. Add `FieldFiveHourRemaining` to `SettingsWindow.xaml` and the control list in `CodexMonitorHUD.ps1`.
3. Add locale labels in all three locale JSON files.
4. Add the already-parsed property to `Get-HudMetrics`.
5. Extend the metric assertion in `scripts/test.ps1` and render all six layouts.
6. Update README, changelog and privacy wording, then bump the patch version once.

Do not remove the dormant parser property unless the upstream log schema permanently removes the window.

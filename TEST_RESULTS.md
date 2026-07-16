# Test results

## 2.0.2-preview release validation - 2026-07-15

- Source validation passes PowerShell parsing, XAML and JSON parsing, locale parity, accounting, configuration migration, theme safety and active-session discovery.
- Synthetic delayed-identity fixtures cover padded headers, metadata appended after discovery, official-title refresh, internal auto-review filtering and workspace fallback from `session_meta.cwd` in both isolated list and split modes.
- Dedicated real-WPF list and split fixtures use zero retention plus the strongest completion departure; the target remains visible during its bounded animation and is removed only after it ends.
- Synthetic solid, gradient and image-theme profiles verify dark/light classification, opposite color compensation, stronger dark-surface glow gain and hard opacity/blur ceilings shared by status dots, reminders, proactive CODEX notices and completion departure.
- Node syntax validation passes for the MCP server.
- Local `2.0.2-preview` installation passes source/install parity with 87 included files and zero missing, extra or hash-changed files. The manifest version, one personal marketplace entry and a fresh heartbeat were verified; local maintenance workflow files are excluded from the installed copy.

## 2.0.1-preview release validation - 2026-07-15

- Added a synthetic four-date active-task regression for GitHub issue #2; it verifies aggregation across date folders without raising the 64-file discovery cap.
- Updated the isolated runtime fixture so its 61 user tasks plus three filtering fixtures stay within that cap. List and split-bubble runs passed with five synthetic tasks and one churn cycle each.
- Verified configurable completed-task retention, including silent completion without attention, and the return to normal monitoring after a new turn.
- Verified the Per-Monitor DPI v2 and shadow-free HUD changes through the source suite, XAML checks and installed-copy parity. Generated test output contains synthetic values only.

## Unreleased post-v2 local acceptance - 2026-07-15

- Test build `2.0.0-preview` removes the per-render 58%-to-100% whole-window fade that made frequent Token updates look like the HUD was repeatedly disappearing and reopening. A 16-record high-frequency usage burst now produces zero additional update animations; meaningful task/status transitions retain a subtle 96%-to-100% fade.
- Test build `2.0.0-preview` adds per-row and per-bubble dismissal. Dismissed state is memory-only, is excluded from the summary/list/split/registry projections, closes any matching bubble immediately, and is cleared only by a later `task_started` event for the same conversation.
- A new destructive-lifecycle regression deletes an actively monitored synthetic conversation file. Both list and split runtimes removed it from the visible registry within the scan window, kept running, and now render a truthful no-active-task state instead of an endless first-use waiting message.
- The initial prompt-derived label was rejected during live acceptance. The replacement follows Codex Usage Tracker's `load_session_index` design: map `session_meta.id` to the official `thread_name` in `~/.codex/session_index.jsonl`, refresh when the index changes, and never parse transcript text for titles.
- Build `2.0.0+codex.20260715054528` adds a user-visible-task filter after a real HUD showed six rows for one running conversation. The live evidence contained one active user task, three already completed user tasks and two `codex-auto-review` subagent sessions. Discovery remains broad, while the list, split bubbles, task counter, registry and summary now include only user tasks that are running or still inside the terminal reminder hold. Silent/internal completions disappear immediately.
- Windows PowerShell's tail reader was proven to omit a final non-newline `task_complete` and to misdecode a Chinese completion line. A bounded UTF-8 byte-tail reader now finds all three completed user sessions in the real sample in about 0.6 seconds, leaving only the one live user task eligible for display.
- Rows now show `project · Codex thread title` by default, with the start time revealed on hover. The title comes from Codex's separate `session_index.jsonl`, matching Codex Usage Tracker's aggregate-only parser, and is never written to the privacy-safe MCP task registry.
- Isolated list and split tests mixed 10/12 active user tasks with two internal subagent files and one already-completed recent-write file; the registry exposed exactly the intended user-task count through one churn cycle in each mode.
- Test build `2.0.0-preview` is installed locally. Source/install parity is 85 files with zero missing, extra or hash-changed files; the live heartbeat was under one second old at verification and the privacy-safe registry contained exactly the one current user task.
- Build `2.0.0+codex.20260714201935` passed PowerShell parsing, all XAML parses, Node syntax, locale parity, live local-log parsing, accounting, configuration normalization and the complete source suite.
- Rich Theme Workshop validation covers declarative `.json` / `.cmhud-theme` files and safe `.cmhud-theme.zip` packages with optional local PNG/JPEG assets. Scripts, network resources, traversal paths and package-size violations are rejected.
- Themes can control solid, gradient and image surfaces, typography, border/shadow treatment, status-dot size, transparency, density, task presentation and reminder appearance in addition to the original color palette.
- Visible turn completion waits through an eight-second continuation guard; silent/internal completion is ignored, and an immediately resumed turn cancels pending attention.
- Surface routing tests confirm that only the matching summary, list row or detached bubble reacts for its active display mode.
- Isolated list and split runtime tests each passed with 80 synthetic concurrent tasks and two complete replacement cycles. Stable numbering passed 10,000 churn cycles with 64 continuously visible tasks.
- The first icon install exposed two Windows-specific gaps despite static WPF icon binding: taskbar grouping inherited `powershell.exe`, and Explorer retained the stable shortcut icon path. The follow-up build uses a dedicated AppUserModelID, native `WM_SETICON` messages and build-specific shortcut icon paths with an Explorer refresh request.
- The installed plugin has 77 files with zero missing, extra or hash-changed files before this final documentation sync. A fresh HUD heartbeat and both versioned shortcut icon targets were observed.
- Official Skill validators could not import their bundled `yaml` dependency in this environment; the generated Skill frontmatter and `agents/openai.yaml` were therefore also checked with a dependency-free structural validator.
- No public-clone synchronization, Commit, Push, Release creation or Issue reply was performed in this acceptance cycle.
- The subsequent cost-estimate work validates cached-input pricing separately, cumulative task token use, unknown-model refusal, opt-in defaults on all three surfaces, local-only pricing and bilingual privacy-safe settings renders.
- Proactive Codex notices are validated as off by default, text-only by default when enabled, visibly identified, limited to 160 plain-text characters and unable to carry executable code. The MCP test covers per-task capability rediscovery, UTF-8/BOM settings compatibility and hard clamping of expressive choreography.
- Isolated 12-task list and split runs accepted one mid-turn expressive notice and confirmed that only its matching row or independent bubble reacted. Shutdown and native icon handle cleanup regressions exposed by animated split windows were fixed and rerun successfully.
- A real read-only inventory found four recently written sessions across creation dates July 10, 14 and 15. The old implementation saw one; the corrected all-date recent-write discovery saw all four. A synthetic old-date-resume regression test now guards this behavior while preserving the 64-file cap.
- Five post-install registry samples over ten seconds retained the same four task-number/workspace pairs while individual statuses changed independently, confirming multiple rows were live rather than one latest-task row being replaced.

## v2.0.0 local installation acceptance - 2026-07-15

- Build `2.0.0+codex.20260714184054` is installed as the new plugin identity.
- PowerShell parsing, all XAML parses, locale parity, accounting, configuration normalization and the complete source suite passed.
- `node --check src/mcp-server.mjs` and JSON parsing passed.
- Isolated list and split runtime tests each passed with 80 synthetic concurrent tasks and two complete replacement cycles.
- The installer stopped before writing when the legacy `codex-token-strip` plugin was detected. No legacy settings or plugin files were migrated or deleted.
- The legacy `codex-token-strip` plugin was removed without using `-RemoveSettings`; the old `%LOCALAPPDATA%\CodexTokenHUD\settings.json` remains present.
- The new marketplace has one `codex-monitor-hud` entry and no legacy entry.
- New settings, HUD heartbeat, desktop shortcut and Start menu shortcut are present; Windows login startup remains disabled.
- Source/install parity passed with 73 files and zero missing, extra or changed files.
- No Commit, Push, Release creation or Issue reply was performed.

## v1.4.2 local installation acceptance - 2026-07-15

- Version `1.4.2+codex.20260715004349` passed PowerShell parsing, all XAML parses, locale parity, live local-log parsing, accounting and configuration normalization.
- Static and preview paths cover independent dot/surface reminder wiring, soft/heartbeat/beacon dot patterns, brightness/speed controls, optional scale breathing and four surface effects.
- Off-screen renders exercised off, halo, breathe, moving light-flow and focus modes without dispatcher or binding errors.
- The unified AI-knot/terminal icon is present as SVG and ICO; tray runtime and shortcut `IconLocation` wiring are tested.
- `node --check src/mcp-server.mjs` passed.
- Isolated list and split runtime tests each passed with 80 synthetic concurrent tasks and two complete replacement cycles.
- Source/install parity, preserved settings, one marketplace entry, fresh HUD heartbeat and disabled login startup were verified after installation.
- The public clone was synchronized and release assets were prepared without Commit, Push, Release creation or Issue replies.

## v1.4.1 local installation acceptance - 2026-07-15

- Version `1.4.1+codex.20260715000753` passed PowerShell parsing, all four XAML parses, locale parity, accounting, live local-log parsing and the complete source test suite.
- Configuration tests cover the Compact default, three accepted density values, independent list/bubble field defaults and legacy `taskFields` migration.
- Synthetic visual renders confirmed distinct Compact, Balanced and Relaxed spacing without clipping task numbers, metrics or action controls. Simplified Chinese and English multi-task screenshots were refreshed.
- `node --check src/mcp-server.mjs` passed.
- Isolated Windows runtime tests passed with 80 concurrent synthetic tasks and two complete replacement cycles in both list and split modes.
- Stable numbering again passed 10,000 churn cycles with 64 continuously visible tasks and a bounded reuse pool.
- The installed-copy test suite, source/install SHA-256 parity, preserved settings, one personal marketplace entry, fresh heartbeat and disabled Windows login startup were verified after installation.
- No public clone, GitHub, session-log, database or user-settings-content operation was performed.

## v1.4.0 local installation acceptance - 2026-07-14

- Version `1.4.0+codex.20260714233609` was installed with `scripts/install.ps1` after the source test suite and Node syntax check passed.
- The installed-copy test suite passed its PowerShell, XAML, live local-log, accounting, locale, theme, multi-task, 10,000-cycle stable-number and active-session checks.
- The installer preserved `%LOCALAPPDATA%\CodexMonitorHUD\settings.json`, refreshed one personal marketplace entry and recreated desktop/Start-menu settings shortcuts.
- A full SHA-256 comparison of included files between the maintenance source and `%USERPROFILE%\plugins\codex-monitor-hud` passed after removing three obsolete files left by an older copy-only installer behavior.
- A fresh HUD heartbeat was present after the settings launch. No legacy Windows Startup shortcut is present.
- No public-clone, GitHub, session-log, database or user-settings-content operation was performed.

## v1.4.0 maintenance-source validation - 2026-07-14

- `scripts/test.ps1`: passed PowerShell parsing, all four XAML files, live local-log parsing, Token accounting, concurrent aggregation, allowance freshness, locale parity, theme schema, seven status states, per-surface reminders, click-through recovery and multi-task guardrail checks.
- `node --check src/mcp-server.mjs`: passed.
- `scripts/test-runtime-isolated.ps1 -Mode list -TaskCount 80 -ChurnCycles 2`: passed with 80 synthetic concurrent tasks and two complete old/new task replacement cycles; the isolated HUD reached a live heartbeat and exited through its own signal.
- `scripts/test-runtime-isolated.ps1 -Mode split -TaskCount 80 -ChurnCycles 2`: passed with the same churn and a six-bubble limit; the isolated HUD created and reclaimed task windows, then exited cleanly after closing them.
- The first split churn run exposed a blank-line parameter-binding dispatcher exit. `Convert-HudRecord` now accepts and safely ignores blank JSONL lines; the identical pressure run then passed.
- Stable-number testing passed 10,000 release/replacement cycles while retaining 64 unique visible task numbers and keeping the released-number pool bounded to 512 entries.
- Compact-row, information-card and status-rail list previews rendered with synthetic data; layered-clarity and smart-focus transparency previews preserved key-number readability at low opacity.
- The multilingual settings previews rendered the redesigned rounded ComboBox controls, including multi-task and general settings layouts, with synthetic/default values only.
- Settings previews rendered in Simplified Chinese and English for both General and Multi-task tabs.
- Concurrent-list HUD previews rendered in Simplified Chinese and English using synthetic data only.
- The formal installed v1.3.1 copy was not replaced, and no public clone or GitHub operation was performed.

## v1.3.1 local acceptance validation - 2026-07-14

- Existing PowerShell, XAML, live-log, Token accounting, concurrent aggregation, locale, theme, status and active-session tests pass.
- Complete final JSON records without a trailing newline are accepted immediately by the incremental reader path.
- Zero-usage allowance observations are retained without replacing visible Token counters.
- Latest account-wide allowance selection uses `AllowanceTimestamp`, independent of task usage order.
- Mouse click-through defaults to disabled and has a dedicated MCP recovery tool.
- Settings render in Simplified Chinese, English and symbol modes; the advanced status palette section remains within the settings viewport.
- Font-size configuration accepts 0.1-point precision.
- `node --check src/mcp-server.mjs` passes.

Pending interactive acceptance: real cross-process click and wheel pass-through, immediate disable/re-enable, multiple monitors and mixed DPI. This source is ready for the formal local installation; GitHub remains untouched.

## Installed-copy validation - 2026-07-14

- Installed build: `1.3.0+codex.20260714164255`.
- The installed-copy test suite passes.
- Five core files match the maintenance source by SHA-256: plugin manifest, HUD script, core module, MCP host and default configuration.
- Existing HUD settings remain present; the personal marketplace entry is present; a fresh HUD heartbeat was observed.
- No Windows login-startup shortcut is present.
- Pending user-driven acceptance: verify real click/wheel pass-through and the notification-area, desktop-shortcut, MCP and settings recovery paths on the desktop.
- A controlled Windows launch of the notification-area build reached the HUD loaded event without error output, then shut down through its own exit signal.

## v1.3.1 installed recovery validation - 2026-07-14

- Installed build: `1.3.1+codex.20260714170346`.
- The installed-copy test suite passes and all five runtime core files match the maintenance source by SHA-256.
- A formal HUD restart reached the loaded event and produced a fresh heartbeat.
- The notification-area recovery implementation is present in the installed HUD source.
- Existing settings remain present and Windows login startup remains disabled.

## v1.3.1 notification-area encoding fix - 2026-07-14

- Notification-area labels are composed from the UTF-8 `zh-CN.json` and `en.json` locale files instead of Chinese literals embedded in the Windows PowerShell script.
- Windows PowerShell produced the expected bilingual labels for opening settings, disabling click-through and exiting the HUD.
- The full source test suite passes after the encoding correction.
- Installed build `1.3.1+codex.20260714170852` matches the maintenance HUD script and produced a fresh runtime heartbeat after installation.

Date: 2026-07-13

## Passed

- PowerShell parser validation for the HUD and core module.
- XAML parsing for the HUD, settings window and HSV color picker.
- JSON parsing and exact locale-key parity for `zh-CN`, `en` and `symbols`.
- Live read-only parsing of an existing Codex `token_count` record.
- Token accounting invariants for cached, uncached, input, output and call total.
- Synthetic parsing of weekly and dormant 5-hour allowance windows, plus live weekly remaining observation.
- Synthetic two-task aggregation for input, cached input, uncached input, output, call total, task total and active-task count.
- Active session discovery against the local Codex sessions folder.
- Node.js syntax validation for the local MCP host.
- MCP `initialize` protocol response and temporary heartbeat cleanup.
- Real Windows dual-host lifecycle: shared HUD start, first-host exit preservation, last-host exit shutdown and final restart all passed.
- Off-screen visual rendering of Simplified Chinese, English and symbol-only states.
- Codex plugin manifest validation with the official local validator bundled with Codex.
- Data-driven theme discovery, schema and color parsing for 10 themes.
- Status palette parsing for active, listening, idle, paused and read-error states.
- Installed-source test run and live HUD heartbeat verification.
- Desktop and Start menu shortcut target/argument verification.
- Bilingual-safe language selector verification in Chinese and English settings renders.
- Independent, non-snapping appearance slider handlers with throttled preview/save updates.
- Six-layout render coverage and theme/layout independence checks.
- Hidden Unicode control scan: no unexpected bidi, zero-width or BOM controls.
- Release-content scan: no logs, databases, credentials, usernames, absolute machine paths or session content.

## Windows multi-host lifecycle note

A real two-host test exposed that directly spawning a detached PowerShell child was unreliable on Windows. The MCP host now invokes a short PowerShell launcher, which uses `Start-Process` to create an independent Managed HUD. The HUD follows the combined heartbeat set from every active host, so one closing task cannot stop the overlay while another task remains active. The corrected lifecycle passed the full real-process regression test.

## Local-install scope

The previous installed build was `1.2.1+codex.20260713091002`. This v1.3.0 build will be installed only through `scripts/install.ps1`, which copies the maintenance source to the formal plugin directory, refreshes its personal-marketplace entry, verifies the installed copy and creates settings shortcuts. It does not enable Windows login startup or publish to GitHub.

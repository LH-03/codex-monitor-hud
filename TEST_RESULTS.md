# Test results

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

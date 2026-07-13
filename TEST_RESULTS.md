# Test results

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

## v1.2 runtime note

The installed build is `1.2.1+codex.20260713091002`. Its live heartbeat was observed after final installation, existing settings were preserved, and the weekly allowance option was merged from the new defaults. The Codex command-line executable in the packaged Windows app may return `Access is denied` when invoked directly from PowerShell, so the source was refreshed through the already-configured personal marketplace path and cachebuster; no marketplace JSON was hand-edited during this update.

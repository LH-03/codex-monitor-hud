# Codex Monitor HUD

> English · [简体中文](README.zh-CN.md)

Codex Monitor HUD is a desktop overlay for monitoring currently active Codex Desktop tasks. It reads a bounded subset of local Codex session records and projects that state as a summary, an expandable task list, or independent task bubbles.

The project is intentionally a live monitor, not a historical analytics service, billing tool, or conversation database.

## What it shows

- active, listening, idle, paused, read-error, completed, and aborted states;
- cached and uncached input, output, reasoning output, call total, task total, and context use;
- the latest weekly-allowance observation present in local Codex records;
- stable task numbers and a two-line task identity;
- optional public-API-equivalent cost estimates, clearly labeled as estimates.

Each task-list item has a project/workspace main title and a subtitle line. The default hover mode keeps the time visible and reveals the official Codex conversation title on hover. `Always` keeps the conversation title visible; `Hidden` keeps only the project and time. Titles come from Codex's local `session_index.jsonl`, not from prompt or response text.

## Display modes

| Mode | Behavior |
| --- | --- |
| Summary | One compact aggregate HUD; no per-task windows. |
| List | Stable numbered rows inside the main HUD. Styles: rows, cards, and rail. Detail: Compact, Balanced, or Detailed. |
| Split | Up to 12 independent, resizable task bubbles backed by the same session-state table. |

Task discovery is capped at 64 recent session files. Reopened conversations are found by recent write time even when their files remain under an older creation-date folder. Internal/subagent sessions and expired terminal tasks are filtered from the user-visible projection.

![Task list rendered with synthetic data](assets/hud-multitask-en.png)

## Optional behavior

These features are disabled by default and should be enabled deliberately:

- double-click a task row or bubble to open its validated `codex://threads/<id>` deep link;
- retract a quiet HUD to one overall light or numbered horizontal/vertical task lights;
- automatic completion, abort/error, settling, and context-threshold reminders;
- proactive, task-targeted Codex notices with text-only or bounded expressive permission;
- mouse click-through, with recovery from the notification-area menu and settings shortcuts;
- API-equivalent cost estimates and imported local themes.

The HUD does not infer completion from prose. Completed and aborted states require lifecycle evidence; an activity timeout becomes idle rather than a false completion.

## Codex Micro color reference

The optional `codexMicro` scheme uses five display-reference values sampled from OpenAI's public Codex Micro page. It is not an official OpenAI HUD palette, does not imply endorsement, and is not calibrated to reproduce the page or hardware lighting. Display, color-management, accessibility, and theme differences can change the visible result. See [COLOR_ATTRIBUTION.md](COLOR_ATTRIBUTION.md) for the source, values, mapping, and limitations.

## Runtime and performance boundary

The current implementation uses Windows PowerShell 5.1, WPF, Windows Forms for the notification-area icon, and small Win32 interop helpers. It avoids a database, reads only appended session bytes after discovery, caches locale and render projections, and does not rebuild unchanged WPF trees.

Windows PowerShell/WPF can retain a high private committed-memory watermark after parsing or rendering bursts. The HUD returns unused working-set pages to Windows after updates; this reduces physical resident memory but does not make the committed watermark disappear. Local measurements are recorded in [TEST_RESULTS.md](TEST_RESULTS.md); they are machine-specific and are not a universal memory guarantee. A substantially lower committed-memory floor would require a future compiled .NET resident host.

## Privacy

Processing is local. The HUD:

- reads only the top-level usage, model, lifecycle, workspace leaf, session ID, and official local title needed for display;
- does not store prompts, assistant messages, tool output, raw transcripts, or credentials;
- does not write to Codex session files;
- makes no network requests and has no telemetry;
- keeps the MCP task registry limited to task number, workspace leaf, coarse status, and update time.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

## Requirements

- Windows 10 or Windows 11;
- Codex Desktop with local session records available;
- Windows PowerShell 5.1 or later;
- Node.js available to the Codex plugin host.

## Platform status(new)

- **Windows:** Stable
- **macOS Intel:** Preview
- **macOS Apple Silicon:** Preview

macOS support is currently experimental and has received limited real-device testing. Community testing, bug reports and pull requests are welcome.

- [Download the macOS preview](https://github.com/LH-03/codex-token-hud/releases/tag/v3.0.0-macos-preview.1)
- [Read the macOS testing guide](https://github.com/LH-03/codex-token-hud/blob/main/docs/MACOS_PREVIEW_TESTING.md)
- [Report macOS test results](https://github.com/LH-03/codex-monitor-hud/issues/5)

## Install with Codex

Give Codex the repository URL and ask it to read [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md) before installing. A minimal English request is:

```text
Install Codex Monitor HUD from this repository. Read INSTALL_WITH_CODEX.md first.
Use English for a first install, preserve existing settings on upgrade, run the project
tests, install the personal plugin, and do not enable optional notices, cost estimates,
click-through, themes, or Windows login startup without asking me.
```

For Simplified Chinese, state that the request is Chinese and use `-DefaultLanguage zh-CN` on first install.

## Manual install

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Manual first install defaults to English. Existing settings are preserved. The installer creates desktop and Start-menu settings shortcuts and does not enable Windows login startup.

## Everyday controls

- Click the task count to open or close the list.
- Detach one task or use **Split all** from the HUD/tray menu.
- Drag the main HUD to use a custom position.
- Double-click the main HUD to open Settings.
- If click-through is enabled, use the notification-area icon to disable it.
- Dismissing a row or bubble affects only the current HUD view; the task returns on its next turn.

Settings are stored at `%LOCALAPPDATA%\CodexMonitorHUD\settings.json` and are not packaged with the plugin.

## Token accounting

```text
uncached input = input tokens - cached input tokens
call total     = input tokens + output tokens
```

Reasoning output is an output detail and is not added to call total a second time. Weekly allowance is a latest local observation, not a direct account query. Cost estimates use local pricing data and are not subscription bills, charges, or exact credit conversions.

## Development

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode list -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode split -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

Tests use synthetic sessions and isolated state roots. See [Architecture](docs/ARCHITECTURE.md), [Project status](docs/PROJECT_STATUS.md), [Test results](TEST_RESULTS.md), and [Contributing](CONTRIBUTING.md).

## Project status and disclaimer

The current source version is `2.1.0`. It is Windows-only and unofficial; it is not affiliated with or endorsed by OpenAI. See [RELEASE_NOTES_2.1.0.md](RELEASE_NOTES_2.1.0.md) for the current release summary.

MIT License.

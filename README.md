# Codex Token HUD

> **English guide** · [简体中文说明 / Simplified Chinese guide](README.zh-CN.md)

Codex Token HUD is a lightweight real-time monitoring bubble for Codex Desktop on Windows. It is deliberately not a full historical analytics dashboard: leave Codex working in the background while you watch a video, play a game or use another app, and keep one small always-current bubble visible for task activity, Token counters and the latest locally observed allowance.

Its priority is low overhead, fast refresh and dependable state awareness. It follows concurrent active tasks without building a separate usage database, indexing conversation history or adding telemetry.

The installer creates desktop and Start menu settings shortcuts but does not enable Windows login startup. See the [Simplified Chinese guide](README.zh-CN.md) or [theme and UI extension points](docs/THEMING_AND_UI_EXTENSIONS.md).

A polished, local-first Token overlay for Codex Desktop on Windows.

![Frost preset](assets/hud-frost-en.png)

## Screenshots

| Grouped chips | Metric cards |
|---|---|
| ![Grouped chips with synthetic data](assets/hud-frost-en.png) | ![Metric cards with synthetic data](assets/hud-cards-en.png) |

| Settings | HSV / ARGB color picker |
|---|---|
| ![English settings](assets/settings-en.png) | ![English color picker](assets/color-picker-en.png) |

All screenshots use synthetic Token and weekly allowance values. They contain no real tasks, logs or account data.

Codex Token HUD reads the counters that Codex already writes to local session logs and turns them into a small, configurable desktop bubble. It independently tails every active Codex task, so concurrent tasks do not overwrite one another. No API key, account login, cloud service, or usage database is required.

## Highlights

- Cached input, fresh input, output, reasoning output, call total and task total.
- Optional model, context pressure and update time.
- Concurrent task tracking with latest-activity and active-task aggregate modes.
- Fully localized settings in Simplified Chinese or English; the language selector and context menu remain bilingual in every mode.
- Ten ready-to-use data-driven themes, from Frost and Midnight to Ocean, Sakura and Lavender.
- Chinese, English and symbol-only labels.
- Six independent bubble layouts: grouped chips, compact chips, inline minimal, outlined chips, metric cards and stacked cards.
- Latest-observed weekly remaining allowance from local `token_count.rate_limits` snapshots, enabled by default and configurable.
- Exact, compact and automatic number formatting.
- Custom fields, HSV/ARGB colors, five-state status palette, opacity, radius, font size, position and animation.
- Optional mouse click-through, disabled by default, with notification-area, settings-shortcut and Codex recovery paths.
- Four status color schemes plus individual ARGB editing; font size adjusts in 0.1-point increments.
- Independent monitoring for multiple concurrent Codex tasks.
- Desktop and Start menu settings shortcuts, without Windows login startup.
- Visual presets never overwrite layout, number format or selected metrics.
- Starts with the Codex plugin lifecycle instead of Windows login.
- Reads logs locally and never uploads conversation content.

## Install with Codex

Copy this repository's GitHub URL, paste it into Codex with the prompt below, and let Codex perform the local installation:

```text
Install and configure the Codex Token HUD plugin from this GitHub repository:

<PASTE_THIS_REPOSITORY_URL_HERE>

Read INSTALL_WITH_CODEX.md first. On Windows, run the repository's scripts/install.ps1,
validate the plugin and live local-log parser, enable the personal plugin entry, and open
the settings window. Do not enable Windows login startup. Do not upload, delete, or modify
my Codex session logs, usage database, prompts, or conversation content. If Codex needs a
restart or a new task for plugin discovery, tell me clearly.
```

For a Chinese copy-and-paste prompt, see [INSTALL_WITH_CODEX.md](INSTALL_WITH_CODEX.md).

## Manual install

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

Then enable `codex-token-strip` from your personal plugin marketplace and restart Codex or open a new task.

## Use

- Drag the HUD to place it anywhere.
- Double-click the HUD to open settings.
- Right-click to pause, reposition, open settings, or exit.
- Mouse click-through can be enabled from settings or the context menu. While enabled, right-click the persistent Codex Token HUD notification-area icon and choose **Disable click-through**. The icon also opens settings; desktop/Start settings shortcuts and the Codex recovery request remain available.
- Ask Codex to “open Token HUD settings” after the plugin is loaded.
- Choose **Follow latest activity** to display whichever task updated most recently, or **Aggregate active tasks** to combine all tasks updated within the configured time window.

Settings are stored under `%LOCALAPPDATA%\CodexTokenHUD\settings.json` and are not included in the repository.

## Accounting

Cached input is part of input, not an extra bucket:

```text
fresh input = input tokens - cached input tokens
call total  = input tokens + output tokens
```

Reasoning output is displayed as a detail of output and is not added again to the call total.

## Requirements

- Windows 10 or Windows 11.
- Codex Desktop with local session logs enabled.
- Windows PowerShell 5.1 or later.
- Node.js available to Codex for the local MCP host. Codex Desktop currently bundles a Node runtime for bundled local plugins.

## Privacy

The HUD reads top-level `token_count` and `turn_context` records from `~/.codex/sessions`. It does not store prompts, assistant messages or tool output, and it does not transmit logs. See [PRIVACY.md](PRIVACY.md).

## Development

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

The project has no npm dependency and no build step. See [ARCHITECTURE.md](docs/ARCHITECTURE.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT

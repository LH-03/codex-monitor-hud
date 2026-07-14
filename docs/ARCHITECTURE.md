# Architecture

```text
Codex plugin loader
        |
        v
local MCP host (Node.js, stdio)
        |
        +---- writes one heartbeat per active Codex plugin host
        +---- keeps the WPF HUD alive while any host remains active
        +---- exposes show/hide/pause/settings and click-through recovery tools
        |
        v
WPF HUD (Windows PowerShell)
        |
        +---- discovers all sessions updated inside the active-task window
        +---- keeps an independent byte offset, model and snapshot per task
        +---- follows the latest task or aggregates all active tasks
        +---- parses token_count and turn_context records
        +---- renders configured metrics
        +---- maps recent log activity to five configurable status colors
        +---- exposes the latest observed weekly remaining allowance without aggregating it across tasks
        +---- consumes a complete final JSONL record even before its trailing newline is appended
        |
        v
%LOCALAPPDATA%\CodexTokenHUD\settings.json
```

The parser performs a one-time tail read when discovering a session, then reads only appended bytes from each active file. Folder scans are limited to today and yesterday during normal operation, and inactive state is pruned according to the configured 5–60 minute window. This avoids repeatedly parsing large historical logs while supporting concurrent Codex tasks.

Cached input is treated as a subset of input. Reasoning output is treated as an output detail and is not added twice.

Token usage freshness and account allowance freshness are tracked separately. A zero-usage maintenance record may update the latest observed allowance without replacing the visible Token counters. In both latest-task and aggregate modes, the newest allowance is selected by its own observation timestamp.

Mouse click-through changes only the Win32 extended style of the HUD window. Settings and color-picker windows remain interactive. The setting defaults to off; a persistent Windows notification-area icon can disable it even when the HUD itself no longer accepts pointer input. Installed settings shortcuts and the MCP recovery signal remain independent fallbacks.

Visual presets are discovered from `themes/*.json`; locale labels are discovered from `locales/*.json`. See `THEMING_AND_UI_EXTENSIONS.md` for the supported extension surface.

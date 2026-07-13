# Architecture

```text
Codex plugin loader
        |
        v
local MCP host (Node.js, stdio)
        |
        +---- writes one heartbeat per active Codex plugin host
        +---- keeps the WPF HUD alive while any host remains active
        +---- exposes show/hide/pause/settings tools
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
        |
        v
%LOCALAPPDATA%\CodexTokenHUD\settings.json
```

The parser performs a one-time tail read when discovering a session, then reads only appended bytes from each active file. Folder scans are limited to today and yesterday during normal operation, and inactive state is pruned according to the configured 5–60 minute window. This avoids repeatedly parsing large historical logs while supporting concurrent Codex tasks.

Cached input is treated as a subset of input. Reasoning output is treated as an output detail and is not added twice.

Visual presets are discovered from `themes/*.json`; locale labels are discovered from `locales/*.json`. See `THEMING_AND_UI_EXTENSIONS.md` for the supported extension surface.

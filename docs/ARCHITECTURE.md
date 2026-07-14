# Architecture

```text
Codex plugin loader
        |
        v
local MCP host (Node.js, stdio)
        |
        +---- writes one heartbeat per active Codex plugin host
        +---- keeps the WPF HUD alive while any host remains active
        +---- exposes show/hide/pause/settings, click-through recovery and opt-in Codex notice tools
        +---- reports notice permission plus privacy-safe active task numbers to each new Codex task
        +---- accepts bounded declarative notice choreography; never evaluates model-supplied code
        |
        v
WPF HUD (Windows PowerShell)
        |
        +---- discovers all sessions updated inside the active-task window
        +---- keeps an independent byte offset, model and snapshot per task
        +---- assigns stable in-memory task numbers without indexing conversation text
        +---- renders summary, expandable-list or independent-bubble views
        +---- supports single-task detach/merge and global split/merge controls
        +---- parses token_count, turn_context and minimal lifecycle event records
        +---- renders configured aggregate and per-task metrics
        +---- maps observed activity and explicit terminal events to seven configurable status colors
        +---- directs reminders to the summary, relevant list item or independent task bubble
        +---- consumes short CODEX-labeled proactive notices independently from automatic lifecycle reminders
        +---- applies uniform, layered or smart-focus transparency without another monitoring process
        +---- exposes the latest observed weekly remaining allowance without aggregating it across tasks
        +---- optionally estimates Codex-only API-equivalent cost from local pricing JSON; never treats it as subscription billing or complete shared Work/Codex usage
        +---- consumes a complete final JSONL record even before its trailing newline is appended
        |
        v
%LOCALAPPDATA%\CodexMonitorHUD\settings.json
```

The parser performs a one-time tail read when discovering a session, then reads only appended bytes from each active file. Discovery checks recent write time across all creation-date folders because reopening an older Codex conversation continues writing to its original folder. Only files inside the configured 5–60 minute activity window are retained, discovery is capped at 64 files, and full file contents are never reparsed on each tick. This preserves reopened-task correctness while keeping the live tail bounded.

All views share the same parser and session-state table. Summary mode creates no per-task windows. List mode renders rows only when the list is open. Split mode reuses each session snapshot instead of opening another reader. Independent windows default to a maximum of six and are hard-capped at twelve after config normalization.

Task labels use only a stable runtime number, the leaf folder name from `turn_context.cwd`, and the task start time. Prompts, messages and tool output are never used for names. Visible tasks are not renumbered; released numbers cool down before reuse in a bounded FIFO/set number pool with constant-time allocation checks.

The HUD writes a small `task-registry.json` under its own local state directory. It contains only the visible task number, privacy-safe workspace leaf, coarse status, and update timestamp. The read-only `monitor_hud_notification_capabilities` tool lets a newly created Codex task rediscover current notice permission and choose a target without relying on cross-conversation memory. If workspace matching remains ambiguous, the agent is instructed to ask instead of guessing.

List mode supports compact rows, information cards and status rails over the same session-state table. Reminder events carry a task-local revision and expiry. Summary, list and independent-bubble surfaces choose their animation independently; list mode animates only the matching task item, while a detached task can animate its entire bubble. Explicit `task_complete` and `turn_aborted` events produce terminal states. A timeout without a terminal event is only treated as settled/idle.

Reminder rendering has two stackable channels. `Start-HudDotAttentionAnimation` controls dot rhythm, glow brightness, timing and an optional scale transform. `Start-HudSurfaceAttentionAnimation` independently controls the relevant shell/item with halo, breathing, translated gradient light flow or focus pulse. Persistent summary and task-bubble elements use attention revisions; regenerated list elements replay only while the task-local attention expiry is active, without background cleanup timers.

Proactive Codex notices are a third, separately authorized path. `monitor_hud_notify` writes a bounded local JSON message; the HUD sanitizes it again, resolves one target task, displays a localized CODEX badge, and routes `Start-HudAgentAnimation` only to that task's current surface. Text-only permission ignores model choreography. Expressive permission accepts at most four declarative layers from glow, pulse, breathe, and flow, with hard limits on color, intensity, tempo, cycles, radius, scale, and direction. The tool call is a brief mid-turn side channel: it does not emit a lifecycle completion, change task status, or stop subsequent Codex work.

Uniform transparency changes the whole window opacity. Layered clarity and smart focus keep window opacity at 1 and instead vary role-based brush alpha, so the shell and secondary text can fade further than important numbers and status. Smart focus raises those roles during active work or a reminder.

Cached input is treated as a subset of input. Reasoning output is treated as an output detail and is not added twice.

Token usage freshness and account allowance freshness are tracked separately. A zero-usage maintenance record may update the latest observed allowance without replacing the visible Token counters. In both latest-task and aggregate modes, the newest allowance is selected by its own observation timestamp.

Mouse click-through changes only the Win32 extended style of the HUD and independent task windows. Settings and color-picker windows remain interactive. The setting defaults to off; a persistent Windows notification-area icon can disable it even when the HUD itself no longer accepts pointer input. The same menu also switches display modes and merges all task bubbles. Installed settings shortcuts and the MCP recovery signal remain independent fallbacks.

`assets/codex-monitor-hud.ico` is generated deterministically by `scripts/build-icon.ps1`. The runtime notification icon and installed desktop/Start shortcuts use this file, while `assets/icon.svg` carries the matching higher-resolution plugin identity.

Visual presets are discovered from `themes/*.json`; locale labels are discovered from `locales/*.json`. See `THEMING_AND_UI_EXTENSIONS.md` for the supported extension surface.

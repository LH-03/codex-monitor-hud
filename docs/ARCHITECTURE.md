# Architecture

## Scope

Codex Monitor HUD is a local Windows projection over recent Codex Desktop session records. It does not maintain a historical database and does not modify Codex sessions.

```text
Codex local session JSONL + session_index.jsonl
                    |
                    v
        bounded discovery and incremental reader
                    |
                    v
             shared session-state table
          /          |          |          \
     summary       list      split      task registry
                                  \
                               quiet indicators
```

## Components

| Component | Responsibility |
| --- | --- |
| `src/MonitorHud.Core.psm1` | Configuration normalization, bounded discovery, record parsing, accounting, themes, pricing, and pure helpers. |
| `src/CodexMonitorHUD.ps1` | Process lifecycle, incremental reads, state transitions, projection caching, WPF rendering, tray integration, settings host, and recovery signals. |
| `src/HudWindow.xaml` | Main summary/list/quiet shell. |
| `src/TaskBubbleWindow.xaml` | Independent split-task surface. |
| `src/SettingsWindow.xaml` | Settings UI loaded only by the on-demand settings process. |
| `src/mcp-server.mjs` | Small local MCP control surface and bounded notice handoff. |

## Data flow

Discovery scans all Codex session date folders for files written inside the configured activity window. It keeps at most 64 candidates. Reopening an older conversation continues writing to its original date folder, so filtering only today's folder is incorrect.

On discovery, the core performs a bounded streaming tail read. During monitoring, each state stores its file identity and byte offset and reads only appended data. Records whose top-level type cannot affect identity, lifecycle, accounting, allowance, or model/workspace context are rejected before `ConvertFrom-Json` creates a full object graph.

Session identity comes from `session_meta`; user-facing conversation titles come from the separate local `session_index.jsonl`. Prompt, assistant, and tool-output text are not used for naming or lifecycle inference.

## State and projections

All surfaces read the same state objects. Split bubbles do not create new parsers. Visible membership is a projection over the discovered state table and applies internal-session, dismissal, active-window, terminal-retention, and departure rules.

Task numbering is in-memory and stable for the visible lifetime of a task. Released numbers enter a bounded cooldown queue before reuse.

The task registry is deliberately smaller than the UI state. It stores only task number, workspace leaf, coarse status, and update time so MCP controls can target a visible task without exposing titles or transcript content.

## Rendering

The dispatcher observes files and lifecycle timers every 800 ms; directory discovery is separately bounded. A timer tick does not imply a full render.

The runtime caches:

- locale objects;
- appearance signatures;
- top-level metric control structure;
- task-list visible-content signatures;
- context and tray menu signatures;
- quiet-indicator projections.

Metric values update in place. List rows rebuild only when their visible projection changes. The header uses explicit grid columns so a fully populated metric row cannot overlap the right-side list toggle.

Attention is surface-local: summary mode affects the summary, list mode the matching row, and split mode the matching independent bubble. Context alerts animate only the context metric.

## Settings process

The resident HUD does not construct the full Settings or Color Picker visual trees. `Show-HudSettings` launches a single on-demand settings host process with its own mutex. Closing the window saves configuration, writes a local reload signal, and exits. The resident HUD reloads normalized configuration and invalidates only the affected render caches.

## Memory behavior

PowerShell/WPF may commit managed heap pages during startup or large update bursts and keep that commitment after objects become unreachable. The HUD therefore distinguishes private committed bytes from the physical working set.

When an updated process has a sufficiently large working set, it performs a bounded working-set trim. A full generation-2 collection is limited to once every two minutes. This returns unused physical pages without claiming that the PowerShell heap's committed high-water mark has disappeared.

## Windows integration

- WPF provides transparent always-on-top windows.
- Per-Monitor V2 DPI awareness, layout rounding, and pixel snapping reduce mixed-DPI blur.
- Win32 extended styles implement optional click-through.
- Windows Forms provides the notification-area icon and recovery menu.
- Native window icons and a dedicated AppUserModelID prevent fallback to the PowerShell taskbar identity.

## Security and privacy boundaries

- no session-file writes;
- no telemetry or runtime network access;
- no prompt/response/tool-output parsing for identity or lifecycle;
- no model-authored XAML, script, shader, CSS, shell command, or network theme asset;
- bounded local notice messages and declarative animation recipes only;
- settings and user themes live outside the installed plugin directory.

## Testing strategy

Pure helpers and source contracts are checked by `scripts/test.ps1`. `scripts/test-runtime-isolated.ps1` launches real WPF list/split surfaces with isolated synthetic sessions. `scripts/test-behavior-isolated.ps1` checks quiet indicators, terminal retention, wake-up, and context alerts. Render-preview modes provide visual evidence for language, density, list-style, transparency, and quiet-layout checks.

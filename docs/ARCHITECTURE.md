# Architecture

## 2.2 Windows process boundary

```text
Codex local files
       |
       v
CodexMonitorHud.Core (net10.0, platform-neutral)
       | parsing / discovery / incremental state / projections
       v
Windows WPF shell
compiled resident monitor
       |
       v
on-demand legacy Settings host (exact config/UI compatibility only)
```

The resident hot path is compiled C#. `CodexMonitorHud.Core` has no WPF, Windows Forms, registry, tray, or Win32 references. The Windows application is a separate `net10.0-windows` project. The full 2.1 Settings UI remains an on-demand compatibility adapter while the resident monitor and all live display surfaces use the compiled host. This split avoids making a risky settings rewrite a prerequisite for the performance migration and leaves an explicit `-Legacy` rollback.

## Scope

Codex Monitor HUD 3.2.2 is a local Windows projection over recent Codex Desktop, VS Code, and CLI session records. It combines the normal `CODEX_HOME` (`~/.codex` by default) with an optional isolated `~/.codex-deepseek` profile without reading either profile's provider configuration or authentication files. It does not maintain a historical database and does not modify Codex sessions.

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
| `src-dotnet/CodexMonitorHud.Core` | Platform-neutral configuration, bounded discovery, streaming JSONL parsing, identity, accounting, state transitions, pricing, and presentation rules. |
| `src-dotnet/CodexMonitorHud.App` | Compiled Windows lifecycle, WPF projections, tray, DPI/Win32 integration, bubbles, signals, and MCP notice inbox. |
| `tests-dotnet/CodexMonitorHud.Core.Tests` | Zero-dependency executable regression suite for neutral behavior. |
| `src/MonitorHud.Core.psm1` | Configuration normalization, bounded discovery, record parsing, accounting, themes, pricing, and pure helpers. |
| `src/CodexMonitorHUD.ps1` | On-demand exact-compatible Settings host and explicit legacy runtime rollback. |
| `src/HudWindow.xaml` | Main summary/list/quiet shell. |
| `src/TaskBubbleWindow.xaml` | Independent split-task surface. |
| `src/SettingsWindow.xaml` | Settings UI loaded only by the on-demand settings process. |
| `src/mcp-server.mjs` | Small local MCP control surface and bounded notice handoff. |

## Data flow

Discovery scans every enabled profile's Codex session date folders for files written inside the configured activity window, then applies one global 64-candidate cap. This prevents each added profile from multiplying the resident bound. Reopening an older conversation continues writing to its original date folder, so filtering only today's folder is incorrect. After discovery, ordinary watcher changes enqueue at most 256 affected paths. A full bounded scan occurs only for creation/deletion/rename, watcher overflow, startup, or the 30-second reconciliation boundary.

On discovery, the core reverse-reads 64 KiB chunks until it has the bounded 2,000-line tail instead of decoding the whole scan window. During monitoring, each state stores its file identity and byte offset and reads only appended data. The compiled reader rents a 64 KiB buffer; the monitor gives one session at most 256 KiB and all sessions together at most 4 MiB in one dispatcher pass. It carries only the incomplete record between reads and rejects a single pending record beyond 8 MiB. Unread session and official-title work remains in explicit backlogs for later responsive ticks. Records whose top-level type cannot affect identity, lifecycle, accounting, allowance, or model/workspace context are rejected before a full object graph is created.

Session identity, client surface, originator, and bounded model-provider label come from `session_meta`; user-facing conversation titles come from the matching profile's separate local `session_index.jsonl`. `codex_vscode` is classified as VS Code before the historical `source=vscode` Desktop fallback. Prompt, assistant, and tool-output text are not used for naming, source classification, or lifecycle inference. Internal/subagent source objects remain excluded. Model IDs are not allowlisted, so unknown future models keep all non-price monitoring behavior.

## State and projections

All surfaces read the same state objects. Split bubbles do not create new parsers. Visible membership is a projection over the discovered state table and applies internal-session, dismissal, active-window, terminal-retention, and departure rules.

Task numbering is in-memory and stable for the visible lifetime of a task. Released numbers enter a bounded cooldown queue before reuse.

The task registry is deliberately smaller than the UI state. Registry v2 stores only task number, workspace leaf, coarse status, update time, and bounded client/provider/profile labels so MCP controls can target the correct Desktop, VS Code, OpenAI CLI, or DeepSeek CLI task without exposing titles or transcript content.

## Rendering

The dispatcher uses an adaptive 250/800/1,500 ms cadence: bursts and parser backlog stay responsive, active/listening tasks retain the existing cadence, and idle state backs off. File-system changes for sessions, official titles, notices, and control signals coalesce into an immediate dispatcher wake, so the idle cadence does not add interaction latency. Directory discovery is separately bounded. A no-change tick advances lifecycle state without statting every session path, and a timer tick does not imply a full render.

The runtime caches:

- locale objects;
- appearance signatures;
- top-level metric control structure;
- task-list visible-content signatures;
- context and tray menu signatures;
- quiet-indicator projections.

Metric values update in place. List rows rebuild only when their structural projection changes; token, context, status, and notice text update retained controls. The header uses explicit grid columns so a fully populated metric row cannot overlap the right-side list toggle.

Attention is surface-local: summary mode affects the summary, list mode the matching row, and split mode the matching independent bubble. Context alerts animate only the context metric.

Each visible task has exactly one source badge after its status dot and before its stable number. Desktop uses a window outline, VS Code uses its compact ribbon, normal OpenAI CLI uses a terminal mark, and the isolated DeepSeek CLI profile uses a wave-terminal mark. Closing a detached bubble changes only its projection ownership and merges it back into the main HUD; list-row dismissal is the separate operation that temporarily removes a task from the visible set.

## Settings process

The compiled resident HUD does not construct the full Settings or Color Picker visual trees. It launches the existing single on-demand Settings host with its own mutex. Closing the window saves configuration, writes a local reload signal, and exits. The compiled HUD reloads normalized configuration and invalidates only the affected render caches.

## Memory behavior

The resident parser, state table, and renderer now execute inside the compiled .NET process. Streaming buffers are pooled; changed paths and pending JSONL records are bounded; stable list structures retain controls instead of rebuilding them. The Settings process exits when closed, so its WPF tree and PowerShell heap are not resident.

Performance numbers remain machine- and fixture-specific. The migration is an architectural improvement, not a numeric memory promise; release evidence must include idle and burst measurements from the staged compiled runtime.

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

The optional STDIO MCP server negotiates `2025-11-25` plus compatible older revisions and returns structured, schema-described tool results. It reads only HUD-local configuration, heartbeat, manual-exit state, and registry v2. Plugin installation is per `CODEX_HOME`; it never rewrites model/provider selections, and a new Codex task is required to discover a newly installed plugin. See `docs/MCP_INTEGRATION.md`.

## Testing strategy

`scripts/build-dotnet.ps1` builds the solution, runs the neutral Core suite, publishes the application, stages a private Windows Desktop runtime, and executes the staged health check. With `-RunRuntimeTests`, it also launches isolated compiled list and split WPF fixtures. Pure helpers and source contracts remain checked by `scripts/test.ps1`. `scripts/test-runtime-isolated.ps1` drives the same synthetic lifecycle and routing fixture against either `-HostMode legacy` or `-HostMode compiled`; `scripts/compare-runtime-performance.ps1` runs both hosts under the same list/split workload and records private bytes, working set, CPU, handles, and threads. Installation performs health, static, behavioral, and performance gates against a separate staged copy before switching directories; the prior installed version is retained under a versioned rollback path. Render-preview modes provide visual evidence for language, density, list style, transparency, and quiet layouts.

## Portability decision

A full rewrite into C# does not by itself create a macOS application: WPF, Windows Forms, notification-area behavior, click-through flags, registry integration, and AppUserModelID are Windows-only. The portable unit is the neutral Core plus file/config contracts. A macOS product should add a separate UI/system-integration project and reuse the Core rather than conditionally compiling Win32 calls throughout one application.

The preferred next shell is Avalonia if maximum C# reuse is more important than perfectly native macOS controls; SwiftUI is the alternative if native menu-bar/window behavior is more important than shared UI code. Either route still needs macOS-specific work for `.app` packaging, signing/notarization, menu-bar recovery, transparent-window hit testing, launch-at-login, deep links, and Apple-silicon arm64 validation.

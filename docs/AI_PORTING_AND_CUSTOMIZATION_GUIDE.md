# Codex Monitor HUD: AI customization and porting guide / AI 魔改与移植理解指南

This document helps a coding AI or human maintainer understand, modify, or re-implement the project. It is also a map for adapting the idea to macOS, Linux, Claude Code, or another agent runtime. It is guidance, not a promise that every target exposes enough data or can reach feature parity.

本文帮助 Codex、Claude Code 或其他 AI/维护者深度理解、修改、重构本项目，也给 macOS、Linux 与其他智能体工具的适配者一条可执行的理解路线。它只提供架构与迁移辅助，不保证目标平台一定具备足够数据或能够做到完全一致。

## 1. Product truth / 产品本质

Codex Monitor HUD is a lightweight, local-first, real-time attention surface. Its competitive advantage is not exhaustive historical analytics. It keeps Codex in the background while a compact floating HUD answers four questions:

- Is work active, quiet, finished for this turn, aborted, or unreadable?
- Which concurrent task needs attention?
- What are the latest token/context/rate-limit figures?
- Can the user return to the right task without opening a heavy dashboard?

Any port should preserve this priority order: **reliable live state > correct task routing > glanceable UI > customization > historical analytics**.

## 2. Current implementation boundary / 当前实现边界

The shipping implementation is Windows-specific:

- PowerShell hosts the runtime and incremental file reader.
- WPF renders the summary HUD, task list, split bubbles, settings, tooltips, and animations.
- Win32 extended window styles implement mouse click-through.
- Windows Forms provides the notification-area icon and recovery menu.
- The source reads Codex session JSONL files under the current user's `.codex/sessions` directory in read-only, shared-read mode.
- User configuration and imported themes live under `%LOCALAPPDATA%\CodexMonitorHUD`; they are separate from Codex data.

Do not treat these Windows mechanisms as the product. They are replaceable platform adapters around a smaller monitoring model.

## 3. Source map / 源码地图

| Area | File | Responsibility |
|---|---|---|
| Parsing and accounting | `src/MonitorHud.Core.psm1` | Paths, config merge, JSONL record parsing, token/rate snapshots, aggregation, task numbering, themes |
| Runtime orchestration | `src/CodexMonitorHUD.ps1` | Incremental tails, task lifecycle, reminder routing, WPF binding, tray, click-through, theme import |
| Agent notice bridge | `src/mcp-server.mjs`, `skills/codex-monitor-hud/SKILL.md` | Per-task capability discovery, opt-in text notices, bounded live choreography and agent usage rules |
| HUD surfaces | `src/HudWindow.xaml`, `src/TaskBubbleWindow.xaml` | Summary/list shell and independent task bubbles |
| Settings | `src/SettingsWindow.xaml`, `src/ColorPickerWindow.xaml` | Organized controls, polished tooltips, theme workshop, color editing |
| Configuration | `config.default.json` | Defaults and the supported persisted shape |
| Localization | `locales/*.json` | Chinese, English, and symbols-only UI strings; keys must stay identical |
| Themes | `themes/*.json` | Built-in declarative themes |
| Theme creation Skill | `skills/create-monitor-hud-theme/` | AI workflow and shareable theme schema |
| Verification | `scripts/test.ps1`, `scripts/test-runtime-isolated.ps1` | Static, parsing, concurrency, UI contract, and isolated runtime checks |

## 4. Lifecycle semantics that must not be simplified / 不能偷懒的状态语义

Codex uses a **thread → turns → items** model. One conversation/thread can contain many turns. A `task_complete` record is a turn boundary, not proof that the full conversation goal is permanently complete.

The current Windows adapter therefore applies these rules:

1. `task_started` opens or replaces the active turn identity.
2. `task_complete` is user-facing only when it contains a visible final agent message.
3. A visible turn completion waits for a short continuation guard. If a new turn starts immediately, the pending reminder is cancelled.
4. Silent/internal completions are ignored for attention.
5. `turn_aborted` is immediate.
6. Quiet-time inference is optional and disabled by default because a thinking gap can look like inactivity.
7. Summary mode may animate only the summary surface; list mode only the matching row; detached/split mode only the matching task bubble.

Never infer semantic goal completion by reading prompt or answer text. The Windows implementation follows Codex Usage Tracker's aggregate parser and reads Codex's separate `session_index.jsonl` for the official `thread_name`; it does not derive identity from transcript content and does not persist the label.

## 5. Proactive agent notice contract / 主动通知契约

Agent-authored notices are deliberately separate from the automatic lifecycle monitor. A developer or user may instruct an agent to notify at a decision point, approval boundary, blocker, manual-inspection point, or named milestone while the same turn continues.

- Capability discovery must be per task, not remembered across conversations. Expose a read-only capability query through the target runtime's tool/plugin system.
- Default permission is off. First installation keeps basic monitoring only; advanced features are introduced after installation and enabled only by the user.
- Use a privacy-safe task registry or an equivalent runtime identity. Target one task. If identity is ambiguous, ask rather than broadcasting.
- Keep content plain text and bounded. Do not treat an agent notice as trusted markup, code, a URL, or a command.
- Separate text-only permission from expressive permission. Text-only uses user-configured visuals; expressive mode may accept a declarative recipe with strict ranges.
- An expressive adapter may support glow, pulse, breathe, flow, color, intensity, tempo, cycles, radius, scale, and direction. It must never evaluate model-authored scripts, shaders, XAML, CSS, shell commands, or network assets.
- The notice is an attention side channel. It must not end the turn, fabricate completion, mutate source logs, or replace the final answer.

For another agent runtime, translate this contract into its documented tool or hook model. Do not claim seamless mid-turn delivery unless the runtime can actually invoke a local tool and continue execution afterward.

## 6. Canonical adapter model / 建议的统一适配层

When porting to another runtime, normalize source-specific events into a small internal event stream before touching the UI:

```json
{
  "source": "codex|claude-code|other",
  "sessionId": "opaque-session-id",
  "turnId": "opaque-turn-id",
  "workspace": "privacy-safe-folder-name",
  "model": "optional-model-name",
  "at": "2026-07-15T12:34:56Z",
  "kind": "started|usage|visible_turn_finished|silent_turn_finished|aborted|error|session_ended",
  "usage": {
    "input": 0,
    "cached": 0,
    "output": 0,
    "contextPercent": null,
    "weeklyRemainingPercent": null
  }
}
```

An adapter may omit unavailable metrics. It must never fabricate them. The UI should degrade to state-only monitoring instead of showing invented zeroes.

## 7. Porting matrix / 移植拆分

| Layer | Windows implementation | macOS direction | Linux direction | Other agent runtime |
|---|---|---|---|---|
| Event source | Codex JSONL tail | Source adapter using documented files/API/events | Same principle | Hooks, SDK stream, CLI JSON, or documented session events |
| File/event watch | Shared `FileStream` + timer | `DispatchSource`, FSEvents, or async file tail | inotify or portable watcher | Prefer emitted lifecycle events over screen scraping |
| Floating UI | WPF transparent windows | SwiftUI/AppKit `NSPanel` | GTK/Qt transparent always-on-top windows | Reuse canonical state model |
| Tray/menu | Windows Forms `NotifyIcon` | `NSStatusItem` / menu bar extra | StatusNotifierItem/AppIndicator | Platform recovery entry is mandatory |
| Click-through | Win32 extended style | `ignoresMouseEvents` on `NSWindow` | toolkit/window-manager input region | Always provide a redundant way to turn it off |
| Autostart/host | Codex plugin MCP host | LaunchAgent or host integration | systemd user service/autostart | Follow the target tool's supported extension model |

### macOS note

Do not try to run the WPF layer through compatibility shims. Reuse the state model, theme schema, numbering policy, reminder debounce, and surface-routing rules; rewrite the shell with AppKit/SwiftUI. Verify that the target Codex surface exposes the required local events before promising parity.

### Claude Code note

Claude Code's official hooks expose lifecycle points including `SessionStart`, `UserPromptSubmit`, `Stop`, `StopFailure`, `TaskCreated`, `TaskCompleted`, `SubagentStart`, `SubagentStop`, and `SessionEnd`. A port can use a minimal hook handler to forward privacy-safe structured events to a local monitor. Its non-interactive CLI also offers JSON/stream-JSON output, which may suit controlled subprocess workflows. Do not parse colored terminal pixels or scrape prompt text when hooks or structured output are available.

Useful official references:

- <https://code.claude.com/docs/en/hooks>
- <https://docs.anthropic.com/en/docs/claude-code/cli-usage>
- <https://docs.anthropic.com/en/docs/claude-code/getting-started>

These interfaces can change. Pin and test against an explicit Claude Code version, and keep the adapter isolated from the HUD model.

## 8. Modification recipes / 常见魔改路线

### Add a monitored metric

1. Add a nullable field to the canonical snapshot in `MonitorHud.Core.psm1`.
2. Parse only a documented structured source.
3. Add the default visibility flag in `config.default.json`.
4. Add identical locale keys in all locale files.
5. Render it through the existing metric factory, not a one-off text mutation.
6. Add accounting and missing-data tests.

### Add a lifecycle state

1. Define its source evidence and false-positive boundary.
2. Add state color, status priority, terminal hold behavior, and localization.
3. Decide whether it demands attention or only changes color.
4. Route its animation by task identity and current display mode.
5. Test overlapping turns, late events, aborts, and rapid session churn.

### Add a display mode

Keep one state store and multiple projections. Never create independent parsers per surface. Verify summary/list/split transitions, click-through recovery, task numbering cooldown, 64+ concurrent sessions, and windows that disappear during rendering.

### Add a theme capability

1. Add a safe default under `themeStyle`.
2. Clamp/normalize it in `Get-HudConfig`.
3. Add it to import validation and the theme Skill schema.
4. Apply it without changing monitoring or privacy behavior.
5. Render light, dark, list, split, 16 px detail, and low-opacity cases.

## 9. Privacy, security, and performance invariants / 不可破坏的底线

Cost adapters must remain estimates: use local cumulative Codex token counters, price cached input separately, return no value for unknown models, and never present API-equivalent cost as subscription billing or exact credits. A shared Work/Codex allowance does not make Work activity visible to a Codex-only adapter.

- Read source logs; never edit, rotate, truncate, or lock them.
- Do not touch the Codex application, databases, credentials, or user prompts.
- Use incremental reads. Never reparse every full session file on each tick.
- Cap active session discovery and release task numbers with a cooldown.
- Theme packages are data, never code: no scripts, remote URLs, DLLs, fonts, or path traversal.
- Keep image packs bounded. Decode once and cache the bitmap.
- Preserve a tray/menu recovery path before enabling click-through.
- Report unavailable platform metrics as unavailable, not zero.

## 10. Verification / 验证

From the maintenance source on Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1
```

Also render and visually inspect settings, a summary HUD, a dense list, and split bubbles. A passing parser test is not proof that a live target tool still emits the same events.

## 11. Bootstrap prompt for another AI / 交给其他 AI 的启动提示

```text
Read docs/AI_PORTING_AND_CUSTOMIZATION_GUIDE.md, config.default.json,
src/MonitorHud.Core.psm1, src/CodexMonitorHUD.ps1, and scripts/test.ps1 completely.
First report the product positioning, lifecycle semantics, platform-specific
boundaries, privacy invariants, and the exact adapter surface you plan to change.
Do not modify Codex/Claude data, user settings, databases, or GitHub. Keep the
real-time monitor lightweight. When porting, normalize the target tool's
documented events into the canonical adapter model before building UI.
Clearly separate verified target capabilities from assumptions and do not
promise feature parity when the target does not expose the required metrics.
```

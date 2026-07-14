# Codex Monitor HUD v2.0.0

Codex Monitor HUD is a lightweight real-time task monitor for Codex Desktop on Windows. It stays visible while Codex works in the background and tells you when a task needs attention. It is deliberately not a retrospective analytics suite.

## A complete product rename

- Codex Token HUD is now Codex Monitor HUD.
- The plugin, MCP server, Skill, runtime paths, settings directory, mutex, shortcuts, icon filename and repository identity use the new name.
- v2 is a fresh installation identity. It does not import v1 settings or silently remove the legacy plugin.
- If `codex-token-strip` is still installed, uninstall it first, then install `codex-monitor-hud`.

## Preserved monitoring model

- Summary, task-list and split-bubble modes remain available for concurrent background tasks.
- Broad all-date discovery finds reopened conversations without turning every recently touched log into a visible row. Internal subagents, silent stops, and expired completions are filtered from the user task set.
- Stable numbers survive rapid churn, while `project · Codex thread title` keeps conversations inside the same workspace distinguishable using the official local session index rather than prompt text.
- Finished items can be dismissed per row or bubble without touching Codex data, and externally deleted conversations now leave the HUD cleanly instead of stranding it in the first-use waiting state.
- High-frequency Token updates no longer make the HUD repeatedly disappear and pop back. The optional update animation now runs only for meaningful task or status-phase changes and is deliberately subtle.
- A subtle × on each row and independent bubble lets users clear completed work without deleting the Codex conversation; the item returns if that conversation runs again.
- Status-dot reminders and whole-surface reminders remain independent, stackable channels.
- The status dot offers soft pulse, double-heartbeat and beacon rhythms; subtle, balanced and bright glow; slow, normal and fast timing; plus an independently toggleable scale-breathing layer.
- Summary, relevant list item and independent task bubble can each use Off, Soft halo, Bubble breathing, Pulse light flow or Focus pulse.
- The four surface effects provide a clear strength range from restrained ambient emphasis to a strong return-to-work signal.
- Completion, abort/error and natural-settling triggers remain separately configurable.

## New visual identity

- The generic Windows information and PowerShell marks are replaced by a dark HUD-frame, live-wave and mint-status icon designed to stay recognizable at notification-area size.
- The same multi-resolution icon is wired through the notification area, desktop shortcut, Start menu, WPF windows, native taskbar handles and plugin branding.

## New opt-in capabilities

- Proactive Codex notices are separately authorized and off by default. Text notices are visibly CODEX-labeled; expressive permission accepts only bounded declarative glow, pulse, breathe and flow layers and never executes model-supplied code.
- API-equivalent cost estimates are optional, local and clearly not billing or exact subscription credits. Cached input is priced separately, unknown models stay unpriced, and shared Work usage remains outside this Codex-only view.
- Theme Workshop accepts declarative JSON/`.cmhud-theme` files and safe ZIP packs with local PNG/JPG artwork. The bundled Skill helps users create shareable skins without granting scripts or network access.
- The AI adaptation guide documents lifecycle semantics and how to reuse the monitoring model for macOS, Linux, Claude Code or another agent runtime without promising parity.

## Preserved

- Mouse click-through remains opt-in with notification-area, shortcut and MCP recovery paths.
- Density controls, separately configurable list/bubble fields, independently resizable task bubbles, six layouts, ten built-in themes, layered transparency, bilingual settings and local-first processing remain intact.

## Validation

PowerShell, XAML, JSON, locale parity, accounting, fresh-identity installer guards, stackable animation paths and icon wiring passed the source suite. Stable numbering passed 10,000 churn cycles with 64 visible tasks. Isolated list and split runs also mix active user tasks with internal subagents and expired completions to verify that only the intended user rows and bubbles survive. Screenshots use synthetic values only.

## Install or update

Give the renamed repository URL to Codex and ask it to follow `INSTALL_WITH_CODEX.md`, or run `scripts/install.ps1` on Windows. Restart Codex or open a new task if plugin discovery does not refresh immediately.

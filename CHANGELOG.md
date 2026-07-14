# Changelog

## Unreleased - local acceptance work

- Stop replaying the whole-window fade for every Token refresh. Update animation is now keyed to task membership, display mode, and status-phase changes, uses a subtle 96%-to-100% fade, and yields to explicit attention effects.
- Separate broad session discovery from the visible task set: keep scanning every creation-date folder so resumed work is never lost, but hide internal subagent sessions, silent/internal stops and user tasks whose completion hold has expired.
- Give each row a two-level local identity, `project · Codex thread title`, using the same `session_index.jsonl` source as Codex Usage Tracker rather than deriving a label from prompt text. Index changes refresh live; hover mode reveals start time and project-only mode remains available.
- Add a visually matched dismiss action to each list row and independent bubble. Dismissal affects only the HUD's in-memory visible set; it does not modify the Codex conversation or logs, and the task returns automatically when that conversation starts a new turn.
- Remove state and any detached bubble when an actively monitored conversation file disappears; once the visible set is empty, show a stable no-active-task message rather than the first-use waiting copy.
- Replace Windows PowerShell's unreliable JSONL `Get-Content -Tail` path with a bounded UTF-8 byte-tail reader so non-ASCII completion records and final records without a newline are not lost.
- Add an off-by-default proactive Codex notice channel that is distinct from automatic lifecycle reminders. Every notice carries a visible CODEX identity, targets one task surface and can be sent mid-turn without manufacturing completion or stopping later work.
- Let each new Codex task query notice permission and privacy-safe active task numbers instead of relying on cross-conversation memory. Text-only permission uses the configured style; expressive permission accepts bounded declarative combinations of glow, pulse, breathe and flow without evaluating model-supplied code.
- Add separate Codex-notice glow presets, custom ARGB, intensity, duration and default motion. Theme packages may style this channel but cannot enable it, grant permission or change safety limits.
- Fix concurrent discovery for reopened conversations: Codex session folders use the thread creation date, so active old threads are now selected across every date folder by recent write time. This prevents multiple tasks from replacing one list row and stops the surviving task from being repeatedly renumbered.
- Add a read-only task-number registry containing only workspace leaf, coarse status and update time, plus isolated list/split routing tests for one targeted agent notice.
- Keep first installation on basic-monitoring defaults and teach the installer/AI handoff to describe proactive notices, expressive choreography, themes, cost estimates and other DIY features only after installation, without silently enabling them.
- Replace the application mark with a minimal HUD-frame, live-waveform and status-dot icon designed to remain recognizable at 16 px. Use a dedicated Windows AppUserModelID, native large/small HWND icons and build-specific shortcut icon paths so taskbar grouping and Explorer icon caching cannot fall back to the previous PowerShell/shortcut artwork.
- Distinguish visible turn completion from silent/internal turn endings, delay completion attention for an eight-second continuation guard, and cancel it when the same task immediately starts another turn.
- Route attention to only the active surface: the summary in summary mode, the matching row in list mode, or the matching detached bubble in split mode.
- Reorganize return reminders around trigger, target and intensity, add concise bilingual explanations and polished contextual tooltips, and collapse advanced status-dot tuning by default.
- Add a Theme Workshop with drag-and-drop installation for declarative `.json`, `.cmhud-theme` and `.cmhud-theme.zip` packages.
- Expand themes beyond color presets to support solid, gradient and local-image surfaces, font families, opacity, spacing, list presentation, borders, shadows, status-dot sizing, reminder styling and selected layout behavior.
- Keep installed user themes update-safe under `%LOCALAPPDATA%\CodexMonitorHUD\themes`; reject scripts, network resources, unsafe ZIP paths and oversized packages.
- Add a reusable theme-authoring Skill plus an AI-oriented architecture, customization and cross-runtime adaptation guide for Windows, macOS, Linux and other agent runtimes.
- Add opt-in API-equivalent cost estimates to the summary, list rows and independent bubbles. Use cumulative Codex tokens, separate cached-input pricing, a bundled local snapshot and an optional tracker-compatible JSON override; unknown models remain unpriced.
- State clearly that cost is not a subscription bill or exact credits, and that shared ChatGPT Work/Codex allowance cannot be reconstructed because the HUD observes only local Codex sessions.
- Keep pricing status privacy-safe by showing only “bundled snapshot” or a custom file name, never an absolute user path.

## 2.0.0 - 2026-07-15

- Rename the product to Codex Monitor HUD to make its purpose explicit: lightweight, real-time monitoring for Codex tasks running in the background.
- Use a new plugin, MCP server, Skill, runtime path, settings directory, mutex, shortcut and repository identity.
- Treat v2 as a fresh installation. The installer detects the legacy `codex-token-strip` plugin and stops without importing or deleting legacy settings.
- Reorganize the bilingual documentation around live task awareness, high-concurrency Pro workflows and the boundary between monitoring and retrospective analytics.

## 1.4.2 - 2026-07-15

- Split return-to-work reminders into two stackable channels: an independent status-dot reminder and a per-surface bubble/list reminder.
- Let the status dot choose soft pulse, double-heartbeat or beacon rhythm; subtle, balanced or bright glow; slow, normal or fast timing; and an independently toggleable scale-breathing layer.
- Replace the old mutually exclusive dot option with four surface styles spanning clear strength levels: soft halo, bubble breathing, moving pulse light flow and strong focus pulse.
- Make pulse light flow animate the relevant summary shell, list task item or independent task bubble without repeatedly restarting during refresh.
- Replace the generic Windows information/PowerShell icons with one blue-violet AI-knot and terminal-mark icon shared by the notification area, desktop shortcut, Start-menu shortcut and plugin branding.
- Add bilingual reminder-settings screenshots and extend tests for stackable reminder configuration, animation paths and unified icon wiring.

## 1.4.1 - 2026-07-15

- Add Compact, Balanced and Relaxed task-list density levels, defaulting to the lighter Compact layout.
- Keep the task counter and expand control visible after collapsing the list, including when only one task is active.
- Separate per-task fields for list rows and independent task bubbles, while migrating legacy task-bubble field choices safely.
- Let each independent task bubble be resized directly from a subtle lower-right handle, with bounded dimensions retained while that task remains active.
- Show an explicit “current dragged position” selection instead of leaving the position control blank after manual placement.
- Remove remaining system hover chrome from the rounded ComboBox controls and restyle the list toggle to match the HUD.

## 1.4.0 - Unreleased

- Add summary, expandable task-list and independent task-bubble display modes for concurrent Codex work.
- Add stable in-memory task numbers, privacy-safe workspace labels, hover/always/hidden name behavior, delayed number reuse and bounded stale-number retention.
- Support detaching or merging one task, splitting all visible tasks and merging all bubbles from both the HUD and the persistent notification-area menu.
- Keep weekly allowance account-wide on the summary bubble while per-task rows and bubbles show their own status, model, call total, task total and update time.
- Add a configurable split-bubble limit (6 by default, capped at 12) and retain the existing 64-active-file discovery ceiling.
- Add compact-row, information-card and status-rail list styles.
- Replace native square detach/merge controls with a quiet rounded glass button and crisp vector window-action icons shared by list and independent-bubble views.
- Replace system ComboBox chrome with rounded glass selection controls, vector chevrons and a matching elevated option menu.
- Add explicit completed and aborted states from local lifecycle events, plus configurable return-to-work reminders for completion, abort/error and natural settling.
- Let the summary bubble, relevant list item and independent task bubble use different reminder styles; list and task-bubble reminders can animate the entire relevant surface.
- Lower the opacity floor to 15% and add uniform, layered-clarity and smart-focus transparency behaviors that preserve important numbers and status visibility.
- Harden number allocation with a bounded O(1) reuse queue and validate 10,000 allocation/release cycles with 64 continuously visible tasks.
- Ignore blank JSONL lines safely during concurrent file churn instead of allowing a dispatcher error to close split mode.
- Refactor settings into General, Multi-task, Metrics and Appearance tabs with a concise explanation of multi-task behavior.
- Reduce new-session discovery latency from three seconds to roughly 1.5 seconds while preserving incremental byte-tail reads.
- Add isolated Windows runtime validation with 80 synthetic concurrent tasks and repeated task replacement in both list and split modes.
- Reposition split bubbles intelligently around top, bottom, left, right and custom HUD placements.
- Rewrite the English and Chinese README positioning for lightweight, high-concurrency Pro workflows.
- Clarify the README language-switch order and add a short, scope-aware recommendation for users who need Codex Usage Tracker's deeper retrospective analytics.

## 1.3.1 - 2026-07-14

- Add a permanent Windows notification-area icon with bilingual actions to open settings, disable mouse click-through and exit the HUD. The disable action stays available even when the HUD cannot receive pointer input.
- Load notification-area Chinese labels from the UTF-8 locale file instead of embedding them in the Windows PowerShell script, preventing mojibake on PowerShell 5.1.

## 1.3.0 - 2026-07-14

- Add an opt-in mouse click-through mode that leaves HUD rendering and live updates active while pointer input reaches the application underneath.
- Keep click-through disabled by default and provide recovery through the tray icon, settings window, installed settings shortcuts and the `monitor_hud_disable_click_through` MCP tool.
- Consume complete JSONL records immediately even when the writer has not appended the final newline yet, fixing new tasks that remained on the waiting state until HUD restart.
- Track account allowance timestamps independently from Token usage timestamps, so a newer weekly observation cannot remain hidden behind an older task snapshot.
- Change font-size editing from whole-point jumps to 0.1-point live increments.
- Add default, intuitive-semantics, color-vision-friendly and low-distraction status color schemes while retaining individual ARGB customization.

## 1.2.1 - 2026-07-13

- Keep bubble layout, number format and selected metrics unchanged when applying a visual preset.
- Expand bubble layouts from three to six with compact, outlined and metric-card variants.
- Add optional latest-observed weekly remaining allowance from local rate-limit snapshots.
- Keep 5-hour parsing dormant in the core for compatibility, without exposing it in settings or HUD metrics while Codex does not publish that window.
- Preserve account-wide allowance semantics in concurrent-task mode by selecting the newest observation instead of summing or averaging it.

## 1.2.0 - 2026-07-13

- Keep the language selector and HUD context menu bilingual in every language mode.
- Add an HSV color wheel while preserving direct ARGB entry.
- Add ten data-driven themes and documented UI extension points.
- Add configurable colors and timing for active, listening, idle, paused, and read-error states.
- Make appearance sliders independent, non-snapping, and throttled during live preview.
- Add desktop and Start menu settings shortcuts without enabling login startup.

## 1.1.0 - 2026-07-13

- Localized the complete settings interface in Simplified Chinese and English.
- Kept symbol-only HUD mode paired with readable English settings.
- Added independent incremental monitoring for concurrent Codex tasks.
- Added latest-activity and active-task aggregate monitoring modes.
- Added configurable active-task windows and an optional active-task count metric.
- Added deterministic in-place upgrade signaling before file replacement.
- Added a Windows `Start-Process` launcher plus multi-host heartbeats so closing one concurrent task does not stop the HUD while other tasks remain active.

## 1.0.0 - 2026-07-13

- Initial public-ready release.
- Live cached input, fresh input, output and total accounting.
- Five appearance presets and three layouts.
- Simplified Chinese, English and symbol-only labels.
- Configurable fields, colors, typography, position and animation.
- Codex MCP lifecycle host with local control tools.
- Local-only privacy model and no login startup.

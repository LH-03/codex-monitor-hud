---
name: codex-monitor-hud
description: Operate, configure, explain, troubleshoot, or send opt-in task-targeted notices through the locally installed Codex Monitor HUD overlay.
---

# Codex Monitor HUD

Use the plugin's MCP tools for normal operation:

- `monitor_hud_open_settings` opens the appearance and metric settings window.
- `monitor_hud_show` shows or restarts the HUD.
- `monitor_hud_hide` hides it without deleting settings.
- `monitor_hud_pause` toggles live updates.
- `monitor_hud_notification_capabilities` reports whether proactive notices are off, text-only, or allowed to use bounded live choreography. It also lists privacy-safe active HUD task numbers.
- `monitor_hud_notify` sends one short, visibly CODEX-labeled notice to the matching task surface without ending or pausing the current Codex turn.

## Proactive notice protocol

Do not rely on memory from another conversation. Tools are rediscovered when the plugin loads in each new task; an already-open task may need to be recreated after a plugin update.

Before the first proactive notice in a task:

1. Call `monitor_hud_notification_capabilities`.
2. If notices are disabled, continue normally and do not repeatedly retry.
3. Match the current workspace to an active task number and pass `task_number`. If two visible tasks are ambiguous, ask the user instead of guessing. Omitting the number is only a best-effort fallback to the most recently active task.
4. Follow the user's or developer's notification policy. Useful mid-turn cases include a decision that needs human review, a blocked external step, a risky action awaiting approval, or a milestone the user explicitly asked to watch. Do not notify for routine progress unless instructed.
5. Keep the message to one or two plain-text sentences, at most 160 characters. Never include secrets, full logs, private prompts, links, or rich text.

A notification is a side-channel attention cue. After the tool returns, keep working unless the underlying task genuinely requires user input. It must not change task status, manufacture a completion event, or replace the normal final answer.

With `text` permission, send only the message and task number; the user's configured style is used. With `expressive` permission, Codex may compose a bounded recipe from `glow`, `pulse`, `breathe`, and `flow`, plus color, intensity, tempo, cycles, glow radius, scale, and direction. This is declarative visual data, never executable code. Use motion semantically and avoid continuous distraction.

For creating a shareable skin, use `$create-monitor-hud-theme`. Finished `.json`, `.cmhud-theme`, and safe `.cmhud-theme.zip` files install from **Settings > General > Theme workshop**.

## Accounting rules

- Cached input is a subset of input.
- Fresh input is `input_tokens - cached_input_tokens`.
- Call total is `input_tokens + output_tokens`.
- Reasoning output is reported separately but is already represented within output accounting and must not be added to call total again.
- Task total comes from Codex's `total_token_usage.total_tokens`.

## Privacy and safety

The HUD reads local top-level `token_count` and `turn_context` records from `~/.codex/sessions`. It does not upload logs, store prompts, modify sessions, or write token data to the repository. User settings, the privacy-safe task-number registry, and queued notice files live under `%LOCALAPPDATA%\CodexMonitorHUD`.

Treat `task_complete` as the end of one Codex turn, not proof that the entire conversation goal is complete. Silent turn endings are ignored and visible completions use a short continuation guard before alerting.

When troubleshooting, run `scripts/test.ps1` first. Do not delete Codex session logs or the user's existing usage database.

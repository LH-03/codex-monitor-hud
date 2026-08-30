---
name: codex-monitor-hud
description: Operate, configure, explain, troubleshoot, or send opt-in task-targeted notices through the locally installed Codex Monitor HUD overlay. Use when the user mentions HUD, Codex Monitor, "收尾保护", "额度保护", "额度快没了", or asks to preserve a recoverable handoff.
---

# Codex Monitor HUD

Use the plugin's MCP tools for normal operation:

- `monitor_hud_open_settings` opens the appearance and metric settings window.
- `monitor_hud_show` shows or restarts the HUD.
- `monitor_hud_hide` hides it without deleting settings.
- `monitor_hud_pause` toggles live updates.
- `monitor_hud_status` reports runtime health, configured source filters, and privacy-safe active task source metadata.
- `monitor_hud_quota_guard` reports the latest locally observed 5-hour/weekly allowance and a conservative handoff advisory.
- `monitor_hud_notification_capabilities` reports whether proactive notices are off, text-only, or allowed to use bounded live choreography. It also lists privacy-safe active HUD task numbers.
- `monitor_hud_notify` sends one short, visibly CODEX-labeled notice to the matching task surface without ending or pausing the current Codex turn.

## Proactive notice protocol

Do not rely on memory from another conversation. Tools are rediscovered when the plugin loads in each new task; an already-open task may need to be recreated after a plugin update.

Before the first proactive notice in a task:

1. Call `monitor_hud_notification_capabilities`.
2. If notices are disabled, continue normally and do not repeatedly retry.
3. Match the current workspace and source (`Desktop`, `CLI · OpenAI`, or `CLI · DeepSeek`) to an active task number and pass `task_number`. If two visible tasks are ambiguous, ask the user instead of guessing. Omitting the number is only a best-effort fallback to the most recently active task.
4. Follow the user's or developer's notification policy. Useful mid-turn cases include a decision that needs human review, a blocked external step, a risky action awaiting approval, or a milestone the user explicitly asked to watch. Do not notify for routine progress unless instructed.
5. Keep the message to one or two plain-text sentences, at most 160 characters. Never include secrets, full logs, private prompts, links, or rich text.

A notification is a side-channel attention cue. After the tool returns, keep working unless the underlying task genuinely requires user input. It must not change task status, manufacture a completion event, or replace the normal final answer.

With `text` permission, send only the message and task number; the user's configured style is used. With `expressive` permission, Codex may compose a bounded recipe from `glow`, `pulse`, `breathe`, and `flow`, plus color, intensity, tempo, cycles, glow radius, scale, and direction. This is declarative visual data, never executable code. Use motion semantically and avoid continuous distraction.

## Opt-in allowance handoff guard

When the user says **“HUD 收尾保护”**, **“额度收尾保护”**, or equivalent natural language, this skill is the entry point: immediately call `monitor_hud_quota_guard` once, then follow it at natural checkpoints and before a broad, expensive next step. It returns only the latest locally observed account-level 5-hour/weekly percentages; unavailable data must stay unavailable rather than being guessed.

The user enables it and chooses the four editable thresholds in **Settings > Multi-task > Allowance handoff guard**. If the tool returns `disabled`, say that the protection is off and offer to open Settings; do not silently alter settings.

- `clear`: continue normally.
- `prepare_handoff`: at the next checkpoint, prepare a concise recoverable handoff before expanding scope.
- `handoff_now`: before an expensive next step, write/update a concise handoff with current state, changed files, verification, and the exact next command; then stop expanding scope.

For either low state, follow the tool's `instruction` field as the user's current template. First look for an existing project handoff document or prescribed project format and update that when present; create a concise new handoff only when the project has none.

`should_alert` is one-shot: it becomes true when the observed allowance first enters a low band or escalates from preparation to critical. A skip from 11% to 9% still enters the relevant band and alerts. When it is false with `event: steady`, do not repeatedly rewrite or announce the same handoff merely because the allowance remains low; apply the template again only when the work genuinely reaches another checkpoint or is about to expand.

This is an advisory read tool, not a remote interrupt. It cannot wake a model during a tool-free reasoning stretch, forcibly steer another client-owned Desktop/VS Code/CLI turn, or estimate the exact time left. Do not manufacture a completion or stop a task solely because the HUD reports a low allowance.

For creating a shareable skin, use `$create-monitor-hud-theme`. Finished `.json`, `.cmhud-theme`, and safe `.cmhud-theme.zip` files install from **Settings > General > Theme workshop**.

## Accounting rules

- Cached input is a subset of input.
- Fresh input is `input_tokens - cached_input_tokens`.
- Call total is `input_tokens + output_tokens`.
- Reasoning output is reported separately but is already represented within output accounting and must not be added to call total again.
- Task total comes from Codex's `total_token_usage.total_tokens`.

## Privacy and safety

The HUD reads local top-level identity, lifecycle, `token_count`, and `turn_context` records from enabled profile roots: the normal `CODEX_HOME` (`~/.codex` by default) and optionally `~/.codex-deepseek`. It does not read provider configuration or authentication files, upload logs, store prompts, modify sessions, or write token data to the repository. User settings, the privacy-safe task-number registry, and queued notice files live under `%LOCALAPPDATA%\CodexMonitorHUD`.

Desktop, normal CLI, and DeepSeek CLI tasks share one globally bounded monitor and stable-number pool. Source badges and registry fields keep them explicit. Closing a detached bubble only merges that surface back into the main HUD; it must not dismiss the underlying task from aggregate monitoring.

Treat `task_complete` as the end of one Codex turn, not proof that the entire conversation goal is complete. Silent turn endings are ignored and visible completions use a short continuation guard before alerting.

When troubleshooting, run `scripts/test.ps1` first. Do not delete Codex session logs or the user's existing usage database.

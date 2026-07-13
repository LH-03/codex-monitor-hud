---
name: token-hud
description: Operate, configure, explain, or troubleshoot the locally installed Codex Token HUD overlay and its token accounting.
---

# Codex Token HUD

Use the plugin's MCP tools for normal operation:

- `token_hud_open_settings` opens the appearance and metric settings window.
- `token_hud_show` shows or restarts the HUD.
- `token_hud_hide` hides it without deleting settings.
- `token_hud_pause` toggles live updates.

## Accounting rules

- Cached input is a subset of input.
- Fresh input is `input_tokens - cached_input_tokens`.
- Call total is `input_tokens + output_tokens`.
- Reasoning output is reported separately but is already represented within output accounting and must not be added to call total again.
- Task total comes from Codex's `total_token_usage.total_tokens`.

## Privacy and safety

The HUD reads local top-level `token_count` and `turn_context` records from `~/.codex/sessions`. It does not upload logs, store prompts, modify sessions, or write token data to the repository. User settings live under `%LOCALAPPDATA%\CodexTokenHUD`.

When troubleshooting, run `scripts/test.ps1` first. Do not delete Codex session logs or the user's existing usage database.

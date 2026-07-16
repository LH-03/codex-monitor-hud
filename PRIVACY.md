# Privacy

Codex Monitor HUD is local-first.

## Data read

The HUD scans recent `*.jsonl` files under `~/.codex/sessions` and parses only:

- top-level `event_msg` records with payload type `token_count`;
- top-level `event_msg` records with payload type `task_started`, `task_complete`, or `turn_aborted`, using only the event type and timestamp for status/reminder behavior;
- top-level `turn_context` records for the model label and the leaf folder name of `cwd`;
- Codex's separate `~/.codex/session_index.jsonl`, using only `id`, `thread_name`, and file update time so conversations in the same workspace can be distinguished without reading prompt text.

The workspace leaf and Codex-provided thread name are used only for per-task identity in list and split views. Lifecycle reason text and assistant-message content are not used to infer semantic completion. The full working-directory path and prompt/conversation text are never displayed or stored by the HUD. Task numbers and conversation labels exist only in runtime memory; the privacy-safe MCP registry stores the task number, workspace leaf, coarse status, and update time, but not the conversation label. Irrelevant message, compaction, and tool-output records are rejected before full JSON parsing where possible.

When enabled, the HUD also reads numeric `token_count.rate_limits` observations and calculates remaining allowance locally as `100 - used_percent`. This is a recent local observation, not a direct account API query.

## Data stored

Only user interface preferences, including the optional mouse click-through choice, are stored under `%LOCALAPPDATA%\CodexMonitorHUD\settings.json`.

The project does not copy or store prompts, assistant messages, tool output, raw transcript text, session logs, SQLite databases or account credentials.

## Network

The HUD and its MCP lifecycle host make no network requests. There is no telemetry.

## Sharing

Do not attach local logs, databases or settings when reporting a bug. A synthetic screenshot or the output of `scripts/test.ps1` is sufficient for most reports.

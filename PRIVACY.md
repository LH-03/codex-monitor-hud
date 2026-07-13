# Privacy

Codex Token HUD is local-first.

## Data read

The HUD scans recent `*.jsonl` files under `~/.codex/sessions` and parses only:

- top-level `event_msg` records with payload type `token_count`;
- top-level `turn_context` records for the model label.

When enabled, the HUD also reads numeric `token_count.rate_limits` observations and calculates remaining allowance locally as `100 - used_percent`. This is a recent local observation, not a direct account API query.

## Data stored

Only user interface preferences are stored, under `%LOCALAPPDATA%\CodexTokenHUD\settings.json`.

The project does not copy or store prompts, assistant messages, tool output, raw transcript text, session logs, SQLite databases or account credentials.

## Network

The HUD and its MCP lifecycle host make no network requests. There is no telemetry.

## Sharing

Do not attach local logs, databases or settings when reporting a bug. A synthetic screenshot or the output of `scripts/test.ps1` is sufficient for most reports.

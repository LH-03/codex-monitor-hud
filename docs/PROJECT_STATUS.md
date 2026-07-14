# Project status

Last updated: 2026-07-14

## Current release

Version `1.2.1` is the current public GitHub release.

- Visual presets and bubble layouts are independent.
- Six bubble layouts are public: `chips`, `compact`, `inline`, `outline`, `cards`, and `stacked`.
- Weekly remaining allowance is a public opt-in metric sourced from local `token_count.rate_limits` observations.
- Concurrent tasks use the newest account-wide allowance observation; percentages are never summed or averaged.

## Local v1.3.1 acceptance build

- Optional mouse click-through is implemented in the maintenance source and defaults to off.
- Recovery remains available through settings, installed settings shortcuts and a dedicated MCP disable tool. An uninstalled maintenance fix additionally adds a permanent notification-area recovery menu.
- Complete final JSONL records are parsed before a trailing newline arrives.
- Weekly allowance observations are ordered by their own timestamps instead of inheriting task-usage freshness.
- Font size previews and persists at 0.1-point precision.
- Four status color schemes are available without removing per-state ARGB editing.

Build `1.3.1+codex.20260714170852` fixes Windows PowerShell 5.1 notification-area label encoding by loading Chinese and English text from UTF-8 locale JSON. It is installed locally, the formal HUD script matches the maintenance source and a fresh heartbeat was observed. The public GitHub release remains `1.2.1`; no GitHub publishing has occurred.

## Dormant 5-hour allowance support

Codex currently does not consistently publish the 5-hour allowance window. Parsing support remains in `Convert-HudRecord` as `FiveHourRemainingPercent`, and synthetic coverage remains in `scripts/test.ps1`. It is intentionally absent from:

- `config.default.json` fields;
- `SettingsWindow.xaml` metric controls;
- locale files;
- `Get-HudMetrics` public values;
- README feature lists.

If Codex restores the 5-hour window, re-enable it with this small checklist:

1. Add `fiveHourRemaining: false` to `config.default.json`.
2. Add `FieldFiveHourRemaining` to `SettingsWindow.xaml` and the control list in `CodexTokenHUD.ps1`.
3. Add locale labels in all three locale JSON files.
4. Add the already-parsed property to `Get-HudMetrics`.
5. Extend the metric assertion in `scripts/test.ps1` and render all six layouts.
6. Update README, changelog and privacy wording, then bump the patch version once.

Do not remove the dormant parser property unless the upstream log schema permanently removes the window.

# Project status

Last updated: 2026-07-13

## Current release target

Version `1.2.1` is the GitHub publication candidate.

- Visual presets and bubble layouts are independent.
- Six bubble layouts are public: `chips`, `compact`, `inline`, `outline`, `cards`, and `stacked`.
- Weekly remaining allowance is a public opt-in metric sourced from local `token_count.rate_limits` observations.
- Concurrent tasks use the newest account-wide allowance observation; percentages are never summed or averaged.

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

# Codex Token HUD v1.3.1

Codex Token HUD is not a full after-the-fact analytics dashboard. It is a lightweight real-time monitoring bubble: leave Codex working in the background while you watch, play or use another app, and keep a small view of task state, Token counters and the latest locally observed allowance. This release focuses on the part that workflow must get right: staying visible, current and out of the way.

## New

- Optional mouse click-through keeps the HUD visible while clicks and wheel input reach the app underneath.
- Click-through is off by default. It can be enabled from settings or the HUD context menu.
- A persistent Windows notification-area icon provides a direct **Disable click-through** action even if the HUD itself can no longer receive pointer input. It also opens settings and exits the HUD.
- Settings, installed desktop/Start shortcuts and the `token_hud_disable_click_through` Codex tool remain independent recovery paths.
- Four status color schemes: current default, intuitive semantics, color-vision friendly and low distraction. Every state color still supports custom ARGB input and the HSV picker.
- Font size now adjusts and persists in 0.1-point increments for smoother visual scaling.

## Fixed

- Notification-area Chinese labels now render correctly on Windows PowerShell 5.1 because menu text is loaded from the UTF-8 locale files instead of embedded script literals.

- New tasks no longer remain on “Waiting for Codex usage” when a complete JSONL record has been written without its final newline.
- Weekly remaining allowance now follows the newest allowance observation independently of Token-counter timestamps, avoiding stale values that previously corrected only after restarting the HUD.
- Zero-usage maintenance snapshots can refresh allowance data without replacing the visible Token counters.

## Unchanged by default

- Existing users keep normal HUD dragging, double-click settings and right-click actions until they explicitly enable click-through.
- Token accounting, six layouts, ten themes, concurrent-task monitoring and local-only privacy behavior remain intact.
- The HUD makes no network requests and stores only UI preferences.

## Install or update

Give the repository URL to Codex and ask it to follow `INSTALL_WITH_CODEX.md`, or run `scripts/install.ps1` on Windows. Restart Codex or open a new task if plugin discovery does not refresh immediately.

## Important click-through recovery

While click-through is active, the HUD itself cannot be dragged, double-clicked or right-clicked. Open the installed desktop/Start settings shortcut, or ask Codex to “disable Token HUD mouse click-through.”

## Validation

PowerShell, XAML, JSON, locale parity, Token accounting, immediate final-record parsing, allowance-only refresh, newest-allowance selection, concurrent aggregation, settings previews and MCP tool discovery were checked before release. Real click and wheel pass-through, recovery, multiple-monitor and mixed-DPI behavior must pass final interactive acceptance before publishing.

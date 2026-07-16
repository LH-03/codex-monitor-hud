# Test results

Updated: 2026-07-16

## Current result

The current `2.1.0` source candidate passes the source suite, isolated real-WPF list/split matrix, behavior runtime, and visual review described below.

These results use synthetic task names and isolated state/profile roots. They do not include real prompts, responses, tool output, account details, or credentials.

## Source and parser suite

`scripts/test.ps1`: PASS

Covered contracts include:

- PowerShell, XAML, JSON, locale, and MCP syntax;
- Token accounting and allowance selection;
- configuration normalization and migration;
- official-title mapping without prompt-text parsing;
- delayed identity, internal-session filtering, and workspace fallback;
- final JSON records without trailing newlines and non-ASCII lifecycle records;
- all-date recent-write discovery with a 64-file cap;
- stable task numbering under 10,000 churn cycles;
- summary/list/split routing, dismissal, terminal departure, and deleted-session cleanup;
- context-alert dependency and three upward thresholds;
- theme bounds, status palettes, icons, tray recovery, and click-through defaults;
- locale caching, render signatures, bounded session queues, on-demand Settings, and working-set trim guards.

## Real-WPF multi-task matrix

`scripts/test-runtime-isolated.ps1`: PASS

| User fixtures | Total files including filter fixtures | List | Split | Churn |
| ---: | ---: | --- | --- | ---: |
| 1 | 6 | PASS | PASS | 1 |
| 5 | 10 | PASS | PASS | 1 |
| 12 | 17 | PASS | PASS | 2 |
| 59 | 64 | PASS | PASS | 1 |

The split projection remains capped at 12 top-level task windows while the state/discovery path still validates the full 64-file bound.

Runtime assertions cover heartbeat, visible registry count, stable numbering, delayed metadata, internal-session exclusion, official-title refresh, appended usage, notices, blank-line churn, completion departure, bubble cleanup, and clean process exit.

## Behavior runtime

`scripts/test-behavior-isolated.ps1`: PASS

- horizontal numbered quiet bars rendered;
- a collapsed independent bubble remained collapsed during terminal retention;
- a completed task retained its number and terminal color while quiet;
- new activity expanded the main HUD and matching bubble;
- exactly three context levels fired at the synthetic upward crossings.

`scripts/test-terminal-exit-isolated.ps1`: PASS in both list and split modes. The strongest beacon departure remained task-targeted, completed within its bound, removed the intended surface, and left the HUD process running.

## Visual review

Real WPF preview renders were inspected for:

- Simplified Chinese summary and list;
- English card list;
- symbol-only list with no English metric-label leakage;
- project main title plus official conversation subtitle and time;
- horizontal bar and vertical dot quiet layouts;
- white idle markers on a light Codex Micro palette;
- Settings multi-task/behavior layout.

One defect was found during this review: with all top-level metrics enabled, the task-count/list-toggle button could overlap the right edge. The header was changed from implicit docking to explicit auto-sized grid columns, and the expanded list now has a minimum width guard. The corrected render shows full right padding and the list/split runtime tests still pass.

## Historical display regressions retained in coverage

- high-frequency Token updates must not replay a whole-window 58%-to-100% fade;
- one active user conversation must not appear as multiple internal/expired rows;
- blank JSONL lines must not terminate split mode;
- final non-newline lifecycle records and Chinese text must not be lost by Windows PowerShell tail decoding;
- white idle markers must remain visible on light surfaces;
- transparent windows must remain DPI-aware and shadow-free;
- taskbar/tray identity must not fall back to the PowerShell icon;
- disappearing session files must remove their row/bubble instead of leaving an endless waiting state.

## Performance observations

Performance figures are local observations, not hardware-independent guarantees.

- Before optimization, a real active one-task process showed about 24% of one CPU core over a 30-second sample and working-set growth during repeated unchanged renders.
- After caching and dirty-projection changes, a stable real-process window measured about 4% of one CPU core.
- An isolated one-task compact-list run returned its working set from roughly 279 MB to roughly 49 MB after trimming, with zero handle or thread growth.
- A final real active sample started around 269 MB, dropped to about 47–82 MB, and settled around 142 MB after a larger live log update.
- Private committed memory can remain near 250–290 MB because PowerShell/WPF retains its managed-heap high-water mark. Working-set reduction should not be described as equivalent to eliminating that commitment.

## Verification commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode list -TaskCount 5 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode split -TaskCount 5 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

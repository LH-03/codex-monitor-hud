# Test results

Updated: 2026-08-10

## Current result

The repository source is the Windows `3.0.0` Desktop/CLI release. It is prepared as a Windows x64-only package; macOS is not supported or packaged.

The 2026-08-10 candidate passed the full source suite, a clean compiled build with zero warnings/errors, and Core `17/17`. New coverage proves that read-only runtime activity revives an old parent JSONL, clears a stale completed tail without inventing a new completion, remains discoverable for the configured 30-minute window after its three-minute active-color freshness expires, rejects paths outside the profile, keeps unclassified/internal files behind the privacy boundary, normalizes Windows `\\?\` paths, and removes the task after the discovery window expires.

Formatting and presentation regressions prove that near-perfect cache/context values remain below `100%`, the aggregate summary excludes per-task cache/context/model/task-cumulative values, every task-list density keeps model/context/cache efficiency, Detailed wraps diagnostics onto a second line, and missing context-window metadata renders as `--`. The context denominator always comes from that task's own provider record, including the isolated DeepSeek profile.

The compiled 5-task list/split gates passed. The 12-task, one-churn matrix passed for legacy list, compiled list, legacy split, and compiled split; the combined comparison command reached its outer time limit after the first three cells, so the missing compiled-split cell was rerun directly and passed. The isolated behavior runtime also passed numbered quiet-task bars, terminal retention, activity expansion, and all three context-alert stages.

New coverage verifies Desktop, normal OpenAI CLI, and isolated DeepSeek CLI identity; globally unique numbering and a shared 64-file cap across profiles; independent source filters; future-model fallback; icon-only source marks and a localized Settings icon key; no repeated source prefix in task titles; and detached-bubble close returning only that projection to the main HUD. The installed MCP smoke test negotiated `2025-11-25`, returned all eight tools with modern metadata and structured status, and read registry v2 with source-aware task fields.

The final visual pass inspected synthetic English and Simplified Chinese task lists plus matching Sources settings pages. List rows use compact blue-window, violet-terminal, and teal-wave-terminal marks without text inside the badge; project/conversation identity begins immediately after the stable number. The same three marks and their localized meanings appear in Settings. All values and task names are synthetic.

The 2026-08-03 maintenance pass refreshed the local standard API list-price snapshot: GPT-5.6 Terra is `$2.00 / $0.20 / $12.00` and GPT-5.6 Luna is `$0.20 / $0.02 / $1.20` per million input / cached-input / output tokens. The cost regression correctly prices the synthetic Luna sample at `$0.230` after cached input is excluded from the uncached-input component.

The final 2026-07-30 pass verified the new 0–100% opacity normalization, the separate 5-hour allowance metric, and the list-collapse path that preserves detached bubbles. The full source suite, Core executable (13/13), staged compiled runtime checks, 12-task legacy/compiled comparison, transactional installer, installed compiled-host heartbeat, package audit, and checksum generation all passed.

The source regression, Core regression executable, compiled list/split runtime gate, 12-task legacy/compiled comparison, behavior runtime, and list/split terminal-departure gates passed on 2026-07-23. The isolated install transaction gate also passes its forced post-switch failure recovery path.

The pre-refactor `2.1.0` baseline also passed the complete source suite and the 1/5/12/59-user-fixture list/split matrix described below. Those results remain the compatibility authority for the compiled candidate.

These results use synthetic task names and isolated state/profile roots. They do not include real prompts, responses, tool output, account details, or credentials.

## Windows 2.2.0 candidate

- Three-project solution build (`Core`, `Core.Tests`, `App`): PASS with 0 warnings and 0 errors.
- `CodexMonitorHud.Core` regression executable: PASS 13/13.
- Compiled Windows isolated runtime: PASS for 5-task list and split modes.
- Full opacity range: PASS for 0% and 100% configuration acceptance; the Settings slider, live preview, compiled host, and legacy fallback share the same 0–1 range.
- 5-hour allowance: PASS for parsing, formatting, locale parity, Settings selection, synthetic English/Chinese previews, and current-session aggregation semantics.
- Detached-bubble list collapse: PASS by source and isolated legacy/compiled list/split regression coverage; the aggregate toggle does not invoke Merge all.
- Same-fixture legacy/compiled comparison: PASS for 12-task list and split modes. On this machine, compiled private memory was 68.4% of legacy in list mode and 70.3% in split mode; these are local measurements, not product guarantees.
- Isolated behavior runtime: PASS for quiet-task retention, activity expansion and three context stages.
- Isolated terminal departure: PASS for list and split beacon modes.
- Deterministic Windows repository install protocol: PASS for three vague prompts, verified Release preference, missing-Release source fallback, checksum stop, settings preservation, repair and rollback.
- Final local Release package audit: PASS with 657 files (662 ZIP entries including directories), matching SHA-256, no macOS paths, and no forbidden private/state/data paths.

## Windows 2.2.1 candidate

- `scripts/test-dotnet.ps1`: PASS, Core regression executable `14/14`.
- `scripts/build-dotnet.ps1 -RunRuntimeTests`: PASS with `0` warnings and `0` errors; compiled 5-task list and split runtime gates passed.
- `scripts/test.ps1 -TestOutputRoot .test-output-2.2.1`: PASS, including transactional installation, deterministic repository install, parser/accounting, allowance, price, locale, UI-contract, package-boundary, and 10,000-task-churn checks.
- Price snapshot regression: PASS in both Core and PowerShell hosts. Unknown models remain unpriced and cost estimates remain opt-in.
- Second-PC transfer-kit script: source-contract coverage added. The owner-snapshot artifact is verified separately and is intentionally not a public Release asset.

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
- compiled architecture/source contracts, neutral-Core Windows dependency exclusion, exact XAML control-type bindings, valid compiled health fixture JSON, watcher wake-up, bounded parser/title backlogs, MCP restart budget, and transactional install/rollback paths;
- fully synthetic legacy self-test/session discovery, plus an isolated HOME transaction test proving successful version rollback and exact restoration of the prior tree and marketplace after a forced post-switch failure;
- retained WPF attention effects are explicitly cleared when reminders expire, targets change, or summary/list/split routing changes.
- installer/package boundaries reject private workflow roots, nested `bin/obj`, local settings/environment files, logs, JSONL, databases, and archives; the current public source scan has zero local-path or credential-shaped hits.

## Compiled and legacy runtime checkpoints

- `scripts/test-runtime-isolated.ps1 -HostMode legacy -Mode list -TaskCount 5`: PASS with heartbeat/token-burst/pre-exit process samples.
- `scripts/test-behavior-isolated.ps1`: PASS from a fresh temporary state/profile root.
- `scripts/test-terminal-exit-isolated.ps1 -Mode list`: PASS from a fresh temporary root.
- `scripts/test-terminal-exit-isolated.ps1 -Mode split`: PASS from a fresh temporary root.

The compiled host passed list and split fixtures at 5 tasks with no churn and at 12 tasks with one churn cycle. The retained legacy host also passed the 12-task list/split churn fixture, providing the direct baseline used by the performance gate.

## Real-WPF multi-task matrix

`scripts/test-runtime-isolated.ps1` against the `2.1.0` baseline: PASS

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

### 2.2.0 same-fixture gate (12 tasks, one churn cycle)

| Mode | Private bytes (legacy → compiled) | CPU time (legacy → compiled) | Result |
| --- | ---: | ---: | --- |
| List | 362.5 MB → 250.6 MB (0.691×) | 16,890.6 ms → 16,125.0 ms (0.955×) | PASS |
| Split | 321.6 MB → 229.6 MB (0.714×) | 16,843.8 ms → 12,468.8 ms (0.740×) | PASS |
| Aggregate | 0.702× private bytes | 0.847× CPU time | PASS |

The gate also kept compiled working set below its 1.10× baseline ceiling in both modes (list 1.030×, split 1.038×). These are isolated synthetic-fixture measurements on this machine, not product guarantees.

## Installed-copy validation

- Transactional installation completed successfully on 2026-07-30 with the existing Simplified Chinese settings file preserved.
- The installed manifest reports `2.2.0`; the compiled `dotnet` host produced a current heartbeat and the notification-area marketplace entry and Settings shortcut are present.
- All 144 non-runtime package files matched source to installed copy with no missing, extra, or differing files. Runtime manifest, application, and host-file hashes also matched; the installed health check validated the remaining staged runtime.
- Marketplace discovery reports `codex-monitor-hud` as available. No commit, push, release, ZIP, or GitHub write was performed.

## Verification commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode list -TaskCount 5 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode split -TaskCount 5 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-runtime-performance.ps1 -TaskCount 12 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -DefaultLanguage zh-CN
```

# Project status

Updated: 2026-07-22

## Current line

The unreleased source candidate is `3.0.0`. Windows deliberately retains the locally verified 2.2 compiled WPF behavior, its on-demand 2.1-compatible Settings host, and `scripts/start.ps1 -Legacy` fallback. A separate Avalonia macOS host consumes the same platform-neutral Core.

The repository source is the product authority. An installed copy is a deployment target, not a source of truth. Publication, release creation, and installation are separate user-controlled actions.

## Stable contracts

- One shared session-state table backs summary, list, split bubbles, quiet indicators, and the privacy-safe task registry.
- Discovery considers recent writes across all session creation-date folders and is capped at 64 files.
- User-visible projections exclude confirmed internal/subagent sessions and terminal tasks outside their configured retention window.
- Task numbers remain stable while visible and cool down before reuse.
- List rows have a project/workspace main title plus a subtitle line. Official conversation titles come from `session_index.jsonl` and are not derived from transcript text.
- Summary, list, and split views share accounting and lifecycle semantics.
- Completed and aborted states require explicit lifecycle records. Timeouts become idle.
- Mouse click-through is off by default and always has tray, shortcut, and MCP recovery paths.
- Optional notices, expressive motion, cost estimates, quiet indicators, deep-link navigation, and imported themes remain opt-in.
- The optional `codexMicro` scheme is a five-value display reference sampled from an OpenAI public page. It is not an official HUD palette, an endorsement, or a guaranteed cross-device match; see `COLOR_ATTRIBUTION.md`.

## Current implementation

- `CodexMonitorHud.Core` targets neutral `net10.0` and contains no Windows UI or Win32 references.
- Initial tails are reverse-read in bounded chunks; active appended reads use pooled buffers, a 256 KiB per-session/4 MiB global dispatcher budget, bounded session/title backlogs, and a hard cap for an incomplete JSONL record.
- Ordinary file changes enqueue affected paths. Full capped discovery is reserved for structural changes, watcher overflow, startup, and periodic reconciliation.
- Unchanged list structures retain WPF controls; values, context, status, and notices update in place.
- Summary, list, split bubbles, quiet indicators, attention/context/agent animation, tray recovery, click-through, deep links, task registry, and MCP notice routing are implemented in the compiled shell.
- Settings and the color picker remain an on-demand compatibility process. Closing Settings releases that process; the compiled HUD reloads saved configuration through the existing local signal.
- Build staging includes a private .NET runtime and a compiled health check. Installation validates a separate staged tree, including same-fixture legacy/compiled list and split performance gates, before an atomic directory switch; the preceding installed version remains available by version for rollback. Startup is compiled-first and automatically falls back to the legacy host after an early compiled failure.
- Adaptive polling backs off while idle but file watchers coalesce session, title, notice, and signal changes into an immediate dispatcher wake.
- The MCP host checks the HUD heartbeat and applies a bounded three-attempt/five-minute restart budget while respecting intentional manual exit.
- The Avalonia macOS host implements summary/list/split/quiet surfaces, settings preview and atomic persistence, saved window position, tray/menu recovery, native NSWindow click-through plus tray/signal recovery, hide-on-close, single-instance wake-up, bounded notices, validated deep links, privacy-safe heartbeat/task registry and managed lifecycle checks.
- Local six-mode synthetic host smoke tests pass. The macOS arm64 target cross-publishes on Windows, and GitHub Actions run 4 passed executable, bundle and functional-host checks on a native Apple-silicon runner.
- The unsigned Actions workflow builds and audits macOS arm64, runs Core and six-mode host tests, and exercises isolated app/plugin/settings/marketplace install transactions. These mechanical results do not establish Gatekeeper or interactive UI behavior.

## Display state

The current display regression matrix covers:

- 1, 5, 12, and 64 total session fixtures in list and split modes;
- delayed metadata, official-title refresh, internal-session filtering, file churn, and terminal departure;
- horizontal bar and vertical dot quiet indicators;
- terminal color retention while quiet and wake-up on new activity;
- Simplified Chinese, English, and symbol-only HUD labels;
- light-surface white idle markers, context-alert levels, list styles, and settings rendering;
- DPI-aware, shadow-free persistent windows and native/tray icon cleanup.

During the latest visual pass, a fully populated top metric row exposed clipping of the right-side task-count toggle. The HUD header now uses explicit grid columns and the expanded list has a minimum width guard. The corrected render and list/split runtime tests pass.

## Known limits

- The compiled build, Core regression executable, list/split isolated fixtures, same-fixture performance gate, transactional install, installed health check, source/install parity, and fresh compiled heartbeat passed locally. The v3 branch is published as draft PR #4, and an unsigned macOS preview was published separately; neither is a stable v3 release.
- Measurements are machine- and workload-specific; do not treat one number as a product guarantee.
- Split mode creates real top-level WPF windows. The hard limit is 12 even when more sessions are monitored.
- The weekly allowance value is only the latest value observed in local Codex records and can lag another Codex surface.
- Five-hour allowance parsing remains dormant because the upstream record is not consistently available.
- API-equivalent cost is an estimate based on local pricing data, not a bill or exact credit conversion.
- The project does not yet provide a validated stable macOS release or Linux host. The unsigned preview has native Actions evidence, while interactive UI, Gatekeeper, menu/Dock recovery, permission, Spaces/full-screen, display, sleep/wake, real deep-link and long-running resource validation still require real Mac users.

## Next architectural decision

Keep macOS-native adapters in the Mac host and do not move Win32/WPF or AppKit conditionals into Core. Use evidence from volunteer real-Mac testers to calibrate behavior rather than redesigning the shared state engine from automation alone.

## Verification entry points

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-dotnet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -HostMode compiled -Mode list -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -HostMode compiled -Mode split -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\compare-runtime-performance.ps1 -TaskCount 12 -ChurnCycles 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

All runtime fixtures must use synthetic data and isolated state/profile roots.

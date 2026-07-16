# Project status

Updated: 2026-07-16

## Current line

The current source version is `2.1.0`. It is a Windows-only Codex Desktop monitor implemented with Windows PowerShell 5.1 and WPF.

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

- Locale data and visible render projections are cached.
- Unchanged appearance, metrics, list rows, quiet indicators, and menus are not rebuilt every timer tick.
- Newly appended session records are filtered before JSON parsing when their top-level type is irrelevant to the HUD.
- Initial session tails use a bounded streaming queue; active sessions read only appended bytes.
- Confirmed internal sessions stop consuming appended data.
- Settings and the color picker run in an on-demand process. Closing Settings releases that process; the HUD reloads saved configuration through a local signal.
- The resident process returns unused working-set pages to Windows after updates. Full generation-2 collection is rate-limited.

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

- Windows PowerShell/WPF may keep a high private committed-memory watermark after a burst even when the physical working set has been returned to Windows.
- Measurements are machine- and workload-specific; see `TEST_RESULTS.md` for the tested environment rather than treating one number as a product guarantee.
- Split mode creates real top-level WPF windows. The hard limit is 12 even when more sessions are monitored.
- The weekly allowance value is only the latest value observed in local Codex records and can lag another Codex surface.
- Five-hour allowance parsing remains dormant because the upstream record is not consistently available.
- API-equivalent cost is an estimate based on local pricing data, not a bill or exact credit conversion.
- The project does not provide macOS or Linux binaries. Porting guidance is architectural direction, not a supported platform promise.

## Next architectural decision

Further small caching changes may still help specific paths, but a materially lower committed-memory floor requires moving the resident monitor from the monolithic PowerShell/WPF host to a compiled .NET process. Such a migration should preserve the state model, privacy boundary, display contracts, and synthetic real-window regression matrix before replacing the current host.

## Verification entry points

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode list -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-runtime-isolated.ps1 -Mode split -TaskCount 5
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-behavior-isolated.ps1
```

All runtime fixtures must use synthetic data and isolated state/profile roots.

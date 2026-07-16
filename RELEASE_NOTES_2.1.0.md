# Codex Monitor HUD 2.1.0

Version 2.1.0 is the stable v2 line for Windows. It combines the multi-task display work from the v2 previews with behavior controls, title handling, and runtime-path reductions that were validated together.

## User-visible changes

- Summary, expandable list, and independent split-bubble modes share one task state model.
- Every list row has a project/workspace main title and a subtitle line. The subtitle can reveal or always show the official local Codex conversation title together with time.
- Task-list information is controlled through Compact, Balanced, and Detailed presets.
- Optional quiet mode can show one overall light or numbered horizontal/vertical task lights; terminal colors remain visible while the quiet task strip sleeps.
- Optional context alerts use editable thresholds and animate only the context metric.
- Optional double-click navigation uses a validated Codex task deep link.
- Symbol-only labels use a compact geometric vocabulary.
- The Codex Micro display-reference scheme is available alongside the existing palettes. Its five values are sampled visual references, not an official OpenAI HUD palette or a color-match guarantee; see [COLOR_ATTRIBUTION.md](COLOR_ATTRIBUTION.md).
- Settings are organized into General, Multi-task, Behavior, Metrics, and Appearance pages.

## Runtime changes

- Locale, appearance, metric structure, list projection, quiet projection, and menu text are cached.
- Unchanged timer ticks do not rebuild the WPF surface.
- Session tails use bounded streaming reads and irrelevant records are rejected before full JSON parsing.
- Confirmed internal sessions stop consuming appended records.
- Settings and Color Picker run in an on-demand process instead of remaining in the resident HUD.
- Unused working-set pages are returned to Windows after updates; full managed collections are rate-limited.
- The top HUD header uses explicit columns and a list-width guard so a fully populated metric row cannot clip the task-count toggle.

## Privacy

All monitoring remains local. The HUD does not upload data, write Codex session files, or derive titles/status from prompt, reply, or tool-output text. Optional notices, expressive motion, cost estimates, click-through, and imported themes remain disabled by default.

## Limits

- Windows only; Windows PowerShell 5.1/WPF is the current resident host.
- Task discovery is capped at 64 files and split windows at 12.
- Weekly allowance is a latest local observation, not a direct account query.
- API-equivalent cost is an estimate, not a charge or exact credit conversion.
- PowerShell/WPF can retain a high private committed-memory watermark after bursts even after the physical working set is reduced. A materially lower committed-memory floor requires a future compiled .NET host.

See [README.md](README.md), [TEST_RESULTS.md](TEST_RESULTS.md), and [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for current usage, evidence, and known boundaries.

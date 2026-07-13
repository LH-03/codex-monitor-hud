# Changelog

## 1.2.1 - 2026-07-13

- Keep bubble layout, number format and selected metrics unchanged when applying a visual preset.
- Expand bubble layouts from three to six with compact, outlined and metric-card variants.
- Add optional latest-observed weekly remaining allowance from local rate-limit snapshots.
- Keep 5-hour parsing dormant in the core for compatibility, without exposing it in settings or HUD metrics while Codex does not publish that window.
- Preserve account-wide allowance semantics in concurrent-task mode by selecting the newest observation instead of summing or averaging it.

## 1.2.0 - 2026-07-13

- Keep the language selector and HUD context menu bilingual in every language mode.
- Add an HSV color wheel while preserving direct ARGB entry.
- Add ten data-driven themes and documented UI extension points.
- Add configurable colors and timing for active, listening, idle, paused, and read-error states.
- Make appearance sliders independent, non-snapping, and throttled during live preview.
- Add desktop and Start menu settings shortcuts without enabling login startup.

## 1.1.0 - 2026-07-13

- Localized the complete settings interface in Simplified Chinese and English.
- Kept symbol-only HUD mode paired with readable English settings.
- Added independent incremental monitoring for concurrent Codex tasks.
- Added latest-activity and active-task aggregate monitoring modes.
- Added configurable active-task windows and an optional active-task count metric.
- Added deterministic in-place upgrade signaling before file replacement.
- Added a Windows `Start-Process` launcher plus multi-host heartbeats so closing one concurrent task does not stop the HUD while other tasks remain active.

## 1.0.0 - 2026-07-13

- Initial public-ready release.
- Live cached input, fresh input, output and total accounting.
- Five appearance presets and three layouts.
- Simplified Chinese, English and symbol-only labels.
- Configurable fields, colors, typography, position and animation.
- Codex MCP lifecycle host with local control tools.
- Local-only privacy model and no login startup.

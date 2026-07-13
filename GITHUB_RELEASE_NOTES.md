# Codex Token HUD v1.2.1

Codex Token HUD is a local Windows overlay for monitoring Codex Token usage without uploading logs or conversation content.

## Highlights

- Cached input, uncached input, output, reasoning output, call totals and task totals.
- Optional latest-observed weekly remaining allowance from local Codex rate-limit snapshots.
- Concurrent-task monitoring with latest-task and aggregate modes.
- Six independent bubble layouts and ten data-driven visual themes.
- Visual presets no longer change layout, number format or selected metrics.
- Simplified Chinese, English and symbol-only display modes, with bilingual-safe navigation.
- HSV color wheel, direct ARGB input and configurable five-state status indicator.
- Desktop and Start menu settings shortcuts without Windows login startup.

## Privacy

The HUD runs locally and makes no network requests. Release screenshots use synthetic data. The archive contains no Codex logs, databases, settings, task names, account details or machine-specific paths.

## Install

Give the repository URL to Codex and ask it to follow `INSTALL_WITH_CODEX.md`, or run `scripts/install.ps1` on Windows.

## Validation

PowerShell, XAML, JSON, locale parity, Token accounting, weekly allowance parsing, six-layout rendering, concurrent-task aggregation, dual-host lifecycle and plugin manifest validation were checked before release.

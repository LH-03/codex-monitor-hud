# Codex Monitor HUD v2.0.1-preview

Codex Monitor HUD is a local-first, lightweight real-time task monitor for Codex Desktop on Windows. This remains a preview release.

## What changed

- **Finished-task retention:** choose how long a completed conversation remains visible: immediately, 30 seconds, or 1, 2, 5, 10 or 30 minutes. The default is two minutes. A new turn for that conversation resumes normal monitoring.
- **Mixed-DPI text clarity:** the HUD now opts into Windows Per-Monitor DPI Awareness v2 and uses pixel-aligned display text, improving clarity when moving between monitors or using a high-DPI laptop display.
- **Lower visual interference:** persistent drop shadows have been removed from the HUD and independent task bubbles.
- **Multi-task discovery regression coverage:** the test suite now creates synthetic sessions in four distinct date folders and verifies that all recent user tasks aggregate correctly. The existing 64-file discovery safety cap remains unchanged.

## Privacy and boundaries

- Processing remains local; no prompts, task names, session contents, token records or settings are included in this release.
- The release package contains only tracked public repository files. Test screenshots and fixture values are synthetic.
- The HUD remains a real-time monitor, not a retrospective analytics suite.

## Validation

PowerShell parsing, XAML, JSON and locale checks pass in the source suite. The release candidate is also checked with isolated synthetic list and split-bubble runs. Screenshots use synthetic values only.

## Install or update

Give the repository URL to Codex and ask it to follow `INSTALL_WITH_CODEX.md`, or run `scripts/install.ps1` on Windows. Restart Codex or open a new task if plugin discovery does not refresh immediately.

# Codex Monitor HUD 2.2.0 — Windows x64

## GitHub Desktop commit summary

```text
Release 2.2.0: compiled Windows HUD, full opacity range, and 5-hour allowance
```

## Commit description

```text
- Move the resident Windows HUD to a compiled .NET 10 WPF host while preserving the existing Settings compatibility process and legacy fallback.
- Add bounded Core discovery, incremental JSONL reading, privacy-safe task state, watcher wake-up, typed configuration, and retained-control rendering.
- Keep the existing Windows summary, list, split, quiet, tray, click-through recovery, notices, deep links, locales, settings, and local-only privacy contracts.
- Add staged health checks, compiled-first startup, transactional install/rollback, Release checksum routing, and synthetic compiled/legacy regression coverage.
- Add the locally observed 5-hour allowance window, full 0–100% opacity, and an independent list-collapse control that does not merge detached bubbles.
- Scope this release to Windows x64. macOS is not supported or packaged; source-level community adaptations are welcome.
```

## GitHub Release fields

Tag: `v2.2.0`  
Title: `Codex Monitor HUD 2.2.0 — Windows x64`

```markdown
## Windows 2.2.0

This release moves the resident HUD to a compiled .NET 10 Windows host while preserving the established WPF behavior, on-demand Settings UI, and `-Legacy` recovery path.

### Highlights

- bounded file discovery and incremental JSONL reading;
- compiled summary, list, split and quiet HUD projections;
- watcher-driven wake-up and bounded parser backpressure;
- staged health checks, private runtime packaging, transactional upgrades and versioned rollback;
- full 0–100% opacity, with notification-area recovery when set to 0%;
- latest locally observed weekly and 5-hour allowance windows, shown only when Codex emits them;
- an aggregate list control that never merges independently detached bubbles;
- preserved local-only privacy model, settings compatibility, task numbering, tray recovery, click-through recovery, deep links and MCP notice controls.

### Platform and installation

- Supported platform: Windows x64 only.
- Download `CodexMonitorHUD-windows-x64.zip` and `SHA256SUMS.txt` from this Release, or give Codex the repository URL and ask it to read `INSTALL_WITH_CODEX.md`.
- Existing settings are preserved. The installer retains the prior version for rollback.
- macOS is not supported or packaged. Community source adaptations are outside this project's validation scope.

### Verification

The release candidate passed source regression, Core tests, compiled list/split runtime gates, same-fixture legacy/compiled comparison, behavior regression, terminal-departure regression, package privacy scan and SHA-256 generation using synthetic fixtures only.

This project is local-first and unofficial. It does not upload Codex sessions, prompts, replies, tool output, logs, databases, settings, or credentials.
```

Before clicking **Publish release**, regenerate the package with `scripts/prepare-release.ps1`, upload the generated ZIP and `SHA256SUMS.txt`, then copy the exact SHA-256 line from `RELEASE_UPLOAD.md` into the release verification record.

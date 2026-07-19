# macOS portability phase 1

This document separates mechanical evidence from interactive release claims. The existing Windows WPF host remains unchanged in this phase.

## Portable Core audit

| Area | Phase 1 disposition |
| --- | --- |
| Parsing, identity, title index, accounting, lifecycle, task numbers | Already platform-neutral in `CodexMonitorHud.Core`; no WPF/Win32/Registry references were found. |
| Platform paths | `HudPaths.CreateForPlatform` explicitly maps macOS sessions to `~/.codex/sessions` and state to `~/Library/Application Support/CodexMonitorHUD`, while retaining the existing Windows route. |
| Path identity | Session state and watcher change sets use case-sensitive comparison off Windows and case-insensitive comparison on Windows. |
| File watching | The existing bounded `FileSystemWatcher` reconciliation remains in Core; synthetic regression covers creation below a missing sessions root. Actual FSEvents timing remains a live-Mac question. |
| Atomic files and UTF-8 | Synthetic tests cover a Unix workspace path, UTF-8 titles, case-distinct names, and atomic title-index replacement. |

## Project boundary

```text
CodexMonitorHud.Core
  parsing + bounded readers + state + config + presentation rules
        |                              |
        v                              v
CodexMonitorHud.App                CodexMonitorHud.Mac
Windows WPF/Win32 host             Avalonia/macOS host
verified 2.2 behavior retained     independent functional v3 candidate
```

Mac-specific activation, status-menu integration, window placement, notifications and deep-link opening stay in the Mac host. They are not added to Core. Login-item creation remains intentionally deferred until launch/quit/recovery behavior is verified interactively. A shared platform project should be introduced only when a second host genuinely shares a narrow interface.

## What automation can prove

The unsigned workflow draft uses macOS Apple-silicon and Intel runners. Once an authorized commit is pushed, it can prove:

- the pinned .NET SDK restores and Core tests pass on macOS;
- the Avalonia dependency graph is restored from the checked-in NuGet lock file with locked mode enabled;
- the Avalonia host publishes self-contained `osx-arm64` and `osx-x64` app hosts;
- `Info.plist`, executable architecture, health output, bundle layout and deterministic file hashes pass mechanical checks;
- bundles contain no JSONL/session/log/database files, local profile paths or common private-key markers;
- an unsigned ZIP and checksum evidence can be produced without Apple credentials.
- summary/list/split/quiet/settings/notification synthetic smoke cases run through the native app host;
- isolated app/plugin/settings/marketplace install, verify, forced failure, rollback and uninstall transactions preserve state and unrelated marketplace entries.

All repository build entrypoints and the workflow opt out of Avalonia build telemetry as well as .NET CLI telemetry.

No Actions result is claimed until that workflow actually runs on GitHub-hosted macOS runners.

## Locally validated on Windows

- the four-project solution, including the functional Avalonia host, builds with 0 warnings and 0 errors after opting out of build telemetry;
- Core tests pass 13/13, including the new macOS portability regression;
- self-contained cross-publish produces both `osx-arm64` and `osx-x64` app-host outputs;
- PowerShell/XAML/JSON/MCP and deterministic install-protocol regressions pass;
- `Info.plist` is well-formed XML and `install-manifest.json` is valid JSON.
- all six macOS host modes pass against isolated synthetic `/Users/synthetic/...` fixtures with privacy-safe heartbeat/registry evidence.

Windows cross-publish does not prove that either executable is a valid runnable Mach-O bundle. That claim is intentionally reserved for the macOS workflow's `file`, `plutil`, health and bundle-audit results.

## What requires an interactive cloud Mac

- first launch of the quarantined unsigned app and the exact user approval path;
- visual fidelity, Retina scaling, transparency and window behavior;
- menu-bar/Dock recovery, focus, topmost behavior, Spaces, Mission Control and full-screen apps;
- notifications and permission prompts;
- multiple displays, sleep/wake, login items and remote-control interaction;
- Codex Desktop deep links and real lifecycle integration;
- long-lived CPU, private memory, file-descriptor and latency measurements.

The exact pass/fail checklist and aggregate-only sampling command are in `docs/MACOS_CLOUD_VALIDATION.md`; it deliberately keeps Actions evidence separate from interactive claims.

The Windows-hosted functional smoke results do not prove visual parity or native integration. The Mac code now implements the main projections and adapters, but native and interactive claims remain gated as listed above.

## Unsigned distribution boundary

The project may remain free and unsigned. The installer never removes quarantine or weakens Gatekeeper; it gives the user the standard manual **Open** / **Open Anyway** action and reports `needs-user-approval` until a fresh heartbeat can be verified. Developer ID signing and notarization are optional future distribution improvements, not phase 1 requirements.

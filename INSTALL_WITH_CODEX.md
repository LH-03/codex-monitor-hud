# Install with Codex

This is the canonical agent procedure. A repository URL plus “帮我安装” or “install this” is sufficient. Do not infer installation commands from other documents.

## Deterministic procedure

1. Confirm the URL resolves to `https://github.com/LH-03/codex-monitor-hud`. Read `install-manifest.json`; do not read local Codex sessions, prompts, replies, tool output, logs, databases, settings values, or credentials.
2. Detect the platform and architecture:
   - Windows x64 → `windows-x64`;
   - macOS `arm64` → `macos-arm64`;
   - macOS `x86_64` → `macos-x64`;
   - anything else → stop as unsupported.
3. Use a user-local install. Never request administrator access unless the user explicitly asks for a machine-wide install.
4. Use a clean checkout of the manifest's exact tag when consuming a Release. If the exact Release is absent, use the currently trusted checkout only after confirming its origin and manifest version. Run exactly one platform entrypoint:
   - Windows: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows-from-repository.ps1 -DefaultLanguage <zh-CN|en>`;
   - macOS: `sh ./scripts/install-macos.sh`.
5. The entrypoint prefers the matching app asset from the manifest's exact version/tag and verifies it with `SHA256SUMS.txt`. Plugin files come from the same trusted exact-tag checkout. A missing matching Release/asset may use the pinned source-build fallback. A checksum mismatch, missing checksum entry, network error, wrong architecture, mismatched app/plugin version, or unavailable Node.js must stop; never switch silently to another artifact.
6. Preserve the existing settings/state directory. The installer must stage and health-check the candidate before switching, retain the previous app and plugin as a paired rollback, update the personal marketplace atomically without changing unrelated entries, launch it, and check a fresh heartbeat.
7. If an unsigned macOS build is blocked, ask the user to Control-click the app and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway**. Do not clear quarantine, weaken Gatekeeper, or automate the approval. Then run `sh ./scripts/install-macos.sh --verify`.
8. Report only the bounded summary emitted by the installer: version, platform, architecture, app/plugin roots, config status/path, heartbeat status, and paired rollback paths. Do not upload local evidence.

## Maintenance commands

| Operation | Windows | macOS |
| --- | --- | --- |
| Repair | `scripts/install-windows-from-repository.ps1 -Operation Repair` | `sh scripts/install-macos.sh --repair` |
| Verify | installer health/heartbeat checks | `sh scripts/install-macos.sh --verify` |
| Roll back | `scripts/install-windows-from-repository.ps1 -Operation Rollback -RollbackVersion <version>` | `sh scripts/install-macos.sh --rollback` |
| Uninstall | `scripts/uninstall.ps1` | `sh scripts/install-macos.sh --uninstall` |

Uninstall preserves user settings unless the user separately and explicitly requests a settings reset.

## Language

Use `zh-CN` for a Simplified Chinese first-install request and `en` for English or any language without a reviewed locale. Never infer language from session content, and never replace an existing saved preference during upgrade/repair.

## Required stop conditions

Stop and explain the reason when the repository identity, platform/architecture, checksum, staged health check, install switch, or rollback restoration cannot be verified. If the legacy `codex-token-strip` is present, stop and ask the user to handle it; do not migrate or delete it.

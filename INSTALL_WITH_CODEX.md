# Install with Codex

This is the canonical agent procedure. A repository URL plus “帮我安装” or “install this” is sufficient. Do not infer installation commands from other documents.

## Deterministic procedure

1. Confirm the URL resolves to `https://github.com/LH-03/codex-monitor-hud`. Read `install-manifest.json`; do not read local Codex sessions, prompts, replies, tool output, logs, databases, settings values, or credentials.
2. Detect the platform and architecture:
   - Windows x64 → `windows-x64`;
   - anything else → stop as unsupported.
3. Use a user-local install. Never request administrator access unless the user explicitly asks for a machine-wide install.
4. Use a clean checkout of the manifest's exact tag when consuming a Release. If the exact Release is absent, use the currently trusted checkout only after confirming its origin and manifest version. Run exactly one platform entrypoint:
   - Windows: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-windows-from-repository.ps1 -DefaultLanguage <zh-CN|en>`.
5. The entrypoint prefers the matching app asset from the manifest's exact version/tag and verifies it with `SHA256SUMS.txt`. Plugin files come from the same trusted exact-tag checkout. A missing matching Release/asset may use the pinned source-build fallback. A checksum mismatch, missing checksum entry, network error, wrong architecture, mismatched app/plugin version, or unavailable Node.js must stop; never switch silently to another artifact.
6. Preserve the existing settings/state directory. The installer must stage and health-check the candidate before switching, retain the previous app and plugin as a paired rollback, update the personal marketplace atomically without changing unrelated entries, launch it, and check a fresh heartbeat.
7. Report only the bounded summary emitted by the installer: version, platform, architecture, app/plugin roots, config status/path, heartbeat status, and paired rollback paths. Do not upload local evidence.
8. First installation enables only basic local monitoring. After it succeeds, tell the user that source filters, themes, cost estimates, proactive CODEX notices, and the optional MCP/plugin control surface exist; let the user decide whether to enable or install those extras.

## Desktop and CLI monitoring

The installed HUD can monitor three independently selectable sources without reading provider configuration or authentication files:

- Codex Desktop sessions under the normal `CODEX_HOME` (`~/.codex` by default);
- Codex CLI sessions under that normal profile, usually OpenAI/GPT;
- Codex CLI sessions under the optional isolated `~/.codex-deepseek` profile.

The three sources are enabled by default after configuration merge and can be changed in **Settings > Sources**. Source detection comes from bounded session metadata; do not open `config.toml`, auth files, prompts, replies, or archives merely to identify a source. Future model IDs remain monitorable without adding them to an allowlist.

## Optional plugin and MCP connection

Do this only when the user explicitly asks Codex to operate the HUD, send opt-in notices, or install the plugin. A normal HUD installation does not require it.

The installer registers the installed plugin in the personal `local` marketplace. Install it into the normal Codex profile with:

```powershell
codex plugin add codex-monitor-hud@local --json
```

If the user actually uses the isolated DeepSeek profile, install the same local plugin into that profile without changing its provider/model configuration:

```powershell
$previousCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = Join-Path $HOME '.codex-deepseek'
    codex plugin add codex-monitor-hud@local --json
}
finally {
    $env:CODEX_HOME = $previousCodexHome
}
```

Verify plugin presence separately in both profiles. Do not add a second direct MCP entry when the plugin already bundles `.mcp.json`. Newly installed or updated plugin tools are discovered by a new Codex task; an already-open task is not proof of failure if it cannot hot-load them.

The bundled server negotiates MCP `2025-11-25` and compatible older revisions. Its tools expose only HUD operations and privacy-safe task number/source metadata. See [docs/MCP_INTEGRATION.md](docs/MCP_INTEGRATION.md).

## Maintenance commands

| Operation | Windows |
| --- | --- |
| Repair | `scripts/install-windows-from-repository.ps1 -Operation Repair` |
| Verify | installer health/heartbeat checks |
| Roll back | `scripts/install-windows-from-repository.ps1 -Operation Rollback -RollbackVersion <version>` |
| Uninstall | `scripts/uninstall.ps1` |

Uninstall preserves user settings unless the user separately and explicitly requests a settings reset.

## Language

Use `zh-CN` for a Simplified Chinese first-install request and `en` for English or any language without a reviewed locale. Never infer language from session content, and never replace an existing saved preference during upgrade/repair.

## Required stop conditions

Stop and explain the reason when the repository identity, platform/architecture, checksum, staged health check, install switch, or rollback restoration cannot be verified. If the legacy `codex-token-strip` is present, stop and ask the user to handle it; do not migrate or delete it.

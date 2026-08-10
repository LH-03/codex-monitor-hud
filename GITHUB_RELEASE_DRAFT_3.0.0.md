# GitHub Release: v3.0.0

## Title

```text
Codex Monitor HUD 3.0.0 — Desktop + CLI monitoring for Windows x64
```

## Body

Codex Monitor HUD 3.0.0 is the first major release that monitors **Codex Desktop and Codex CLI together** in the same lightweight, real-time Windows overlay.

### What is new

- Monitor Codex Desktop, the normal Codex CLI profile, and an optional isolated DeepSeek-backed Codex CLI profile in one bounded task table.
- Distinct, compact source marks make Desktop, OpenAI CLI, and DeepSeek CLI tasks recognizable without repeating source names in every title.
- Independently enable or hide each source under **Settings > Sources**.
- Show each task's project, official local conversation title, model, cache hit rate, provider-reported context usage/window, current-call usage and detailed accounting at the appropriate information-density level.
- Recover long-running Desktop activity from a privacy-safe read-only heartbeat when a resumed parent session file is temporarily quiet.
- Keep closing a detached bubble separate from dismissing a task: closing merges that bubble back into the main HUD and monitoring continues.
- Keep model detection future-friendly. Unknown model IDs remain monitorable; only unavailable price estimates fall back to `--`.
- Upgrade the optional local MCP surface with current protocol negotiation, structured results, source-aware task targeting and explicit errors.

### Native CLI vs optional isolated provider

Normal Codex CLI monitoring works immediately; no extra profile is required. Advanced users may optionally use the tested `~/.codex-deepseek` isolation convention. The public [CLI profile guide](https://github.com/LH-03/codex-monitor-hud/blob/v3.0.0/docs/CLI_PROFILE_ISOLATION.md) explains the boundary, safe launch wrappers, credential handling and rollback. Third-party provider compatibility remains experimental and is not guaranteed by the HUD.

### Privacy and scope

The HUD stays local and reads bounded session metadata/counters only. It does not read or store prompt/reply text, provider configuration, authentication files or credentials; it does not modify Codex sessions; it has no telemetry or cloud service.

This package supports **Windows 10/11 x64 only**. macOS and Linux are not packaged or claimed as supported.

### Install or upgrade

Extract `CodexMonitorHUD-windows-x64.zip`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

The installer preserves existing settings, validates the staged build before switching, and retains the prior installed version for rollback. New installs can add `-DefaultLanguage zh-CN` for Simplified Chinese.

### Assets

- `CodexMonitorHUD-windows-x64.zip`
- `SHA256SUMS.txt`

### Notes

- The optional cost display is an API-list-price equivalent estimate, not a Codex/ChatGPT subscription bill, credit balance or exact account charge.
- Shared ChatGPT Work/Codex allowance observations cover more than HUD-visible CLI/Desktop token accounting; the HUD can only total the Codex records it reads locally.
- Codex Monitor HUD is independent and unofficial. It is not affiliated with or endorsed by OpenAI or DeepSeek.

## Final release checklist

- [ ] `scripts/build-dotnet.ps1 -RunRuntimeTests` passes.
- [ ] `scripts/test.ps1` passes.
- [ ] English README uses English synthetic screenshots; Chinese README uses Chinese synthetic screenshots.
- [ ] Release ZIP and checksum were regenerated after the final included-file change.
- [ ] ZIP contains no settings, logs, databases, session JSONL, credentials, private handoffs, `.git`, `.codex`, `.agents`, `bin`, or `obj`.
- [ ] Installed 3.0.0 health check and fresh heartbeat pass with settings preserved.
- [ ] `main` is pushed before creating tag `v3.0.0`.
- [ ] Release is public, non-draft, non-prerelease, and marked latest.

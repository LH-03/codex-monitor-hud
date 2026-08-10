# Continuation guide for the next Codex

Read this file before changing or installing Codex Monitor HUD on a new computer.

## Authority and safety

- Work from the repository checkout, never from an installed plugin copy.
- Treat `main` as public source truth only after its owner has pushed it. Preserve unrelated local changes.
- Do not read, copy, package, or upload real Codex prompts, replies, tool output, session JSONL, logs, databases, settings, credentials, or private experiments.
- Do not commit, push, tag, publish a Release, alter GitHub settings, or delete rollback data unless the user explicitly asks.
- This project ships and validates Windows x64 only. Do not claim macOS support or validation.

## Read order

1. `README.md` and `README.zh-CN.md`
2. `docs/PROJECT_STATUS.md`
3. `docs/PROJECT_LEDGER.md`
4. `docs/ARCHITECTURE.md`
5. `docs/MCP_INTEGRATION.md` when touching CLI control or notices
6. `INSTALL_WITH_CODEX.md` when installing
7. `CHANGELOG.md` and `scripts/prepare-release.ps1` when preparing a Release

Private handoffs may exist on an owner's original machine. They are not required for ordinary public maintenance and must not be copied into GitHub or release archives. For the same owner's second computer, `scripts/prepare-transfer-kit.ps1 -IncludeOwnerPrivate` intentionally includes them in a physical owner snapshot.

## Current 3.0.0 maintenance facts

- Resident host: compiled .NET 10 WPF; Settings retains a compatibility process; `scripts/start.ps1 -Legacy` is recovery only.
- Core project: `src-dotnet/CodexMonitorHud.Core`; WPF shell: `src-dotnet/CodexMonitorHud.App`; legacy compatibility host: `src/`.
- Optional cost estimate is a local standard API list-price conversion, not Codex credits or a subscription bill.
- Built-in pricing was rechecked 2026-08-10. GPT-5.6 Terra is `$2.50/$0.25/$15`; GPT-5.6 Luna is `$1/$0.10/$6`, each per million standard input/cached-input/output text tokens. Dated model snapshots reuse the matching catalog entry; entirely unknown prices remain unpriced.
- 5-hour and weekly allowance fields are observed local account windows, never calculated by adding tasks and never fetched from a network API.
- Session monitoring covers Desktop and normal CLI under the normal `CODEX_HOME`, plus the conventional isolated `~/.codex-deepseek` CLI profile. All profiles share one global 64-candidate cap and one stable-number pool.
- Do not read or rewrite either profile's `config.toml`, auth files, provider choice, model choice, prompts, replies, or archives to support monitoring. Source identity comes from bounded session metadata.
- The source badge is part of task identity: Desktop window, OpenAI CLI terminal, or DeepSeek CLI wave-terminal. Closing a detached bubble merges only that surface; list dismissal is a different action.
- The optional MCP server currently prefers protocol `2025-11-25`, returns structured source-aware results, and is installed separately per `CODEX_HOME`. A newly installed plugin becomes available to new Codex tasks, not necessarily the task that performed installation.

## Safe operating sequence

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test-dotnet.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-dotnet.ps1 -RunRuntimeTests
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\test.ps1
```

Run behavior or isolated runtime tests when touching rendering, task lifecycle, list/split routing, settings, installation, or the compiled host. Use only their generated synthetic profiles. For an authorized local install, use `scripts/install.ps1 -DefaultLanguage zh-CN`, then verify the installed manifest, health check, settings preservation, marketplace entry, shortcut, and heartbeat.

## Price-update procedure

1. Use only the official OpenAI pricing page and identify the processing tier. The HUD's default is **standard short-context API list price**.
2. Update `pricing.default.json` source metadata and the affected model rates.
3. Update pricing assertions in both `scripts/test.ps1` and `tests-dotnet/CodexMonitorHud.Core.Tests/Program.cs`.
4. State exclusions explicitly: Codex credits, subscriptions, long context, Batch, Flex, Fast mode, regional processing, and cache writes are different rates.
5. Run the full verification sequence and create a maintenance release rather than silently changing an installed estimate.

## One-line starter prompt

```text
Read README.md, docs/PROJECT_STATUS.md, docs/PROJECT_LEDGER.md, and docs/CODEX_CONTINUATION.md in this repository; preserve privacy and Git boundaries, verify the current 3.0.0 Windows HUD state with synthetic tests, then install or modify only what I explicitly request.
```

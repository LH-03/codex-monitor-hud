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
5. `INSTALL_WITH_CODEX.md` when installing
6. `GITHUB_RELEASE_DRAFT_2.2.1.md` when preparing a commit or Release

Private handoffs may exist on an owner's original machine. They are not required for ordinary public maintenance and must not be copied into GitHub or release archives. For the same owner's second computer, `scripts/prepare-transfer-kit.ps1 -IncludeOwnerPrivate` intentionally includes them in a physical owner snapshot.

## Current 2.2.1 maintenance facts

- Resident host: compiled .NET 10 WPF; Settings retains a compatibility process; `scripts/start.ps1 -Legacy` is recovery only.
- Core project: `src-dotnet/CodexMonitorHud.Core`; WPF shell: `src-dotnet/CodexMonitorHud.App`; legacy compatibility host: `src/`.
- Optional cost estimate is a local standard API list-price conversion, not Codex credits or a subscription bill.
- Built-in pricing was checked 2026-08-03. GPT-5.6 Terra is `$2/$0.20/$12`; GPT-5.6 Luna is `$0.20/$0.02/$1.20`, each per million input/cached-input/output tokens.
- 5-hour and weekly allowance fields are observed local account windows, never calculated by adding tasks and never fetched from a network API.

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
Read README.md, docs/PROJECT_STATUS.md, docs/PROJECT_LEDGER.md, and docs/CODEX_CONTINUATION.md in this repository; preserve privacy and Git boundaries, verify the current 2.2.1 Windows HUD state with synthetic tests, then install or modify only what I explicitly request.
```

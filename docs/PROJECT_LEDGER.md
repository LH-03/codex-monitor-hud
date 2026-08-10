# Project ledger

Updated: 2026-08-10
Scope: public, portable maintenance record for Codex Monitor HUD.

## How to use this ledger

This is the small durable record a new maintainer or Codex instance should read after `README.md`, `docs/PROJECT_STATUS.md`, and `docs/CODEX_CONTINUATION.md`. It records decisions and evidence, not private chat history. Do not add usernames, local paths, settings, session content, task titles, prompts, responses, logs, credentials, or package hashes from an unpublished private build.

## Current release lane

| Item | Value |
| --- | --- |
| Target | Windows x64 only |
| Release | 3.0.0 |
| Packaging | `scripts/prepare-release.ps1` |
| Install | `scripts/install.ps1 -DefaultLanguage zh-CN` or repository installer |
| Recovery | transactional previous-version rollback and `scripts/start.ps1 -Legacy` |
| Public source truth | GitHub `main` after the user performs the intended commit/push |
| Privacy rule | bounded local metadata/counters only; no transcript or network upload |

## Decision ledger

| Date | Decision | Reason and verification boundary |
| --- | --- | --- |
| 2026-07-30 | 2.2.0 moved the resident Windows HUD to compiled .NET/WPF while retaining Settings compatibility and a legacy fallback. | Must preserve Windows UI/lifecycle/privacy behavior; validation is Windows-only. |
| 2026-07-30 | Added observed 5-hour allowance, full 0–100% opacity, and independent list collapse. | Allowance is shown only when local Codex records provide it; detached bubbles must remain detached. |
| 2026-08-03 | Updated the offline price snapshot for GPT-5.6 Terra and Luna. | OpenAI's standard API pricing was checked on the official page. Values remain estimates, not Codex credit billing. |
| 2026-08-03 | Added a second-PC transfer kit. | It can create either a portable clean kit or an owner-only full snapshot containing private handoffs, toolchains, and Git history. The owner snapshot is never a GitHub Release asset. |
| 2026-08-10 | Promoted Desktop plus CLI monitoring to 3.0.0. | The normal Codex CLI profile works by default; the conventional isolated `~/.codex-deepseek` profile is optional, bounded, independently filterable, and documented without publishing private credentials or machine-specific configuration. |

## Evidence ledger template

For every release candidate, append a concise row to `TEST_RESULTS.md` and `SENSITIVE_SCAN.md` with:

1. source commit/ref and candidate version;
2. exact commands run and pass/fail result;
3. release ZIP name, file count, and SHA-256;
4. package privacy scan result;
5. installation parity, settings-preservation, shortcut, and heartbeat result when installation is authorized;
6. any unverified platform or UI surface stated explicitly as unverified.

Never turn local benchmark figures into universal claims. Do not include task names or copied live records as proof.

## Release ledger template

1. Make the intended source changes and update deterministic tests.
2. Run Core, source, compiled-runtime, behavior, and package checks appropriate to the touched surface.
3. Run `scripts/prepare-release.ps1 -Version <version>` only after source changes are final.
4. Inspect ZIP contents for `private/`, settings, JSONL, logs, databases, `.git`, `.agents`, `.codex`, `bin/`, and `obj/` exclusions.
5. Re-run package generation if any package-included file changes afterward.
6. Let the user commit/push/release unless they explicitly delegate those writes.

## Transfer ledger template

1. Build the regular release ZIP first.
2. Run `scripts/prepare-transfer-kit.ps1 -ReleasePackage <release-zip> -IncludeOwnerPrivate` for the owner's complete cross-PC snapshot, or omit the switch for a portable clean kit.
3. Verify the generated transfer ZIP contains `source/`, `release/`, and `START_HERE_ON_SECOND_PC.md`.
4. Move the transfer ZIP using a user-approved private channel. Neither form is a GitHub Release asset.
5. On the other PC, read the start file and continuation guide before installing or editing.

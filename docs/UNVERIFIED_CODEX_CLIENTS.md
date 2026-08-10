# Unverified Codex client compatibility

> [简体中文](UNVERIFIED_CODEX_CLIENTS.zh-CN.md)

This page documents **likely compatibility, not supported compatibility**. The maintainer has not individually validated the clients below and is not planning to chase every Codex surface one by one. If you like trying your luck, feel free to test one and report what happens.

## Why accidental compatibility is plausible

Codex Monitor HUD does not talk to Codex Desktop, VS Code, or the CLI through a product-specific API. Its normal hot path watches the enabled local `CODEX_HOME` roots, discovers Codex rollout/session JSONL files, reads bounded `session_meta` metadata plus usage/lifecycle records, and projects those records into the HUD. The source badge is a later classification step based mainly on `originator`, `source`, profile, and provider metadata.

That architecture means another local Codex client can be readable **before the HUD knows what to call it**, as long as the client writes compatible persisted Codex sessions into a local profile the HUD already watches. This is exactly why VS Code worked before first-class VS Code support existed: the session data was already readable, but the source classifier presented it as Desktop.

The important boundary is therefore not simply “which front end is supported?” It is closer to: **does this local Codex surface persist compatible rollout/session data into a `CODEX_HOME` that the Windows HUD can see?**

## Likely candidates

| Surface | Why it may already be readable | Likely current presentation | Maintainer validation |
| --- | --- | --- | --- |
| Cursor | OpenAI documents Cursor as a VS Code-compatible editor using the Codex extension. | Probably VS Code | Not tested |
| Windsurf | OpenAI documents Windsurf as a VS Code-compatible editor using the Codex extension. | Probably VS Code | Not tested |
| VS Code Insiders | Uses the same Codex extension family. | Probably VS Code | Not tested |
| `codex exec` | OpenAI's CLI supports `codex exec` for scripts and CI; current upstream source starts it with `SessionSource::Exec` and client name `codex_exec`. | Probably Unknown | Not tested |
| TypeScript Codex SDK | The current official TypeScript SDK launches `codex exec --experimental-json` and sets originator `codex_sdk_ts`. | Probably Unknown | Not tested |
| Python Codex SDK | The current official Python SDK controls a local `codex app-server` over JSON-RPC and identifies itself as `codex_python_sdk`. | May be readable but may be mislabeled | Not tested |
| Custom `codex app-server` clients | App Server is explicitly intended to power rich custom Codex clients and accepts a caller-supplied `clientInfo.name`. | Unknown or possibly mislabeled | Not tested |
| JetBrains Codex integration | OpenAI documents JetBrains as a separate Codex integration rather than the VS Code extension family. | Unknown | Not tested; no compatibility assumption |

Xcode is also a separate integration, but this project does not ship or validate macOS. Codex Cloud/web tasks are outside the local-session assumption and should not be expected to appear automatically. Remote SSH, WSL, or dev-container sessions are also only visible if their persisted Codex files are actually reachable through a local profile path monitored by the Windows HUD.

## Why source badges can be wrong

The current HUD intentionally recognizes only a small set of source identities: Desktop, `codex_vscode`, and CLI, plus the separate DeepSeek profile convention. Everything else falls back to an unknown/default classification.

There is also an upstream ambiguity to be aware of. An open issue in `openai/codex` documents that the umbrella `codex app-server` path can persist third-party client sessions with their real `originator` but `source=vscode`. A client may therefore be completely readable while looking like the wrong front end to software that trusts only `source`. This is the same class of problem that originally caused VS Code sessions to be shown as Desktop in this HUD.

For that reason, **a correct token/context/status display does not prove the source badge is correct** for an unverified client.

## Evidence used for this analysis

Checked on 2026-08-11:

- OpenAI Codex IDE documentation: VS Code and compatible editors use the Codex extension; Cursor, Windsurf, and VS Code Insiders are listed in that group, while Xcode and JetBrains provide separate integrations.  
  https://developers.openai.com/codex/ide/
- OpenAI Codex App Server documentation: App Server powers rich clients such as the VS Code extension and asks clients to identify themselves with `clientInfo.name`; the documented VS Code example uses `codex_vscode`.  
  https://developers.openai.com/codex/app-server/
- OpenAI Codex CLI documentation: `codex exec` is the non-interactive path for repeatable workflows and CI.  
  https://developers.openai.com/codex/cli/
- OpenAI Codex SDK documentation: the TypeScript SDK starts/resumes local Codex threads; the Python SDK controls a local Codex app-server over JSON-RPC.  
  https://developers.openai.com/codex/sdk/
- Current `openai/codex` TypeScript SDK source: it launches `codex exec --experimental-json` and sets `CODEX_INTERNAL_ORIGINATOR_OVERRIDE=codex_sdk_ts`.  
  https://github.com/openai/codex/blob/main/sdk/typescript/src/exec.ts
- Current `openai/codex` Python SDK source: its default `client_name` is `codex_python_sdk` and it launches `codex app-server --listen stdio://`.  
  https://github.com/openai/codex/blob/main/sdk/python/src/openai_codex/client.py
- Current `openai/codex` exec source: the non-interactive runtime uses `SessionSource::Exec` and client name `codex_exec`.  
  https://github.com/openai/codex/blob/main/codex-rs/exec/src/lib.rs
- Upstream issue report describing `codex app-server` third-party sessions with a faithful `originator` but `source=vscode`. Treat this as an upstream issue report rather than a compatibility guarantee.  
  https://github.com/openai/codex/issues/23442

## If you want to try one

Run one small local task from the client you care about and see whether a new HUD row appears. If the tokens/context/status look right but the badge is wrong, that still counts as useful evidence.

If you report a result, please do **not** upload a full rollout JSONL. The useful source-classification fields are usually just `originator`, `source`, and `model_provider`; redact session IDs, paths, workspace names, credentials, prompts, replies, and tool output.

No support promise is implied by this page. Compatibility may change when Codex changes its local session format, metadata, storage path, or client behavior.
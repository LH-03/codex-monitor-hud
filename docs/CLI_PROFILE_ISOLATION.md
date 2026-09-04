# Codex CLI profiles and optional provider isolation

> [简体中文](CLI_PROFILE_ISOLATION.zh-CN.md) · Windows x64 · Codex Monitor HUD 3.2.2

Codex Monitor HUD monitors the normal Codex CLI installation out of the box. You do **not** need a second profile to use CLI monitoring. The optional isolated profile described here is only for people who deliberately run Codex CLI against a separate, compatible model provider and want its configuration, authentication state, sessions, and HUD identity kept apart from their normal OpenAI profile.

## What the HUD watches

| CLI setup | HUD support |
| --- | --- |
| Native Codex CLI using the normal `CODEX_HOME` | Supported by default |
| A second Codex CLI home at `~/.codex-deepseek` | Optional, separately identifiable and filterable |
| An arbitrary custom `CODEX_HOME` path | Not currently configurable in the HUD |
| A different CLI that does not write Codex session records | Not supported |

The second source is called “DeepSeek CLI” in the UI because that is the tested isolation convention. It is still Codex CLI; only the provider/profile root is different. Third-party provider compatibility can change when either Codex or the provider changes. The HUD can display the sessions that Codex writes, but it cannot make an incompatible provider work.

## The isolation model

Keep the profile and the project as separate concepts:

```text
CODEX_HOME       -> configuration, authentication state and Codex sessions
working folder   -> the project Codex is allowed to work on
model provider   -> the API backend selected by that profile
```

The normal profile is usually:

```text
%USERPROFILE%\.codex
```

The optional profile recognized by HUD 3.2.2 is:

```text
%USERPROFILE%\.codex-deepseek
```

Do not merge these directories or copy authentication files between them.

## Safe Windows launchers

Start the native OpenAI profile in PowerShell:

```powershell
$env:CODEX_HOME = "$HOME\.codex"
Write-Host "Profile: OpenAI`nCODEX_HOME: $env:CODEX_HOME`nProject: $PWD"
codex
```

Start the isolated profile:

```powershell
$env:CODEX_HOME = "$HOME\.codex-deepseek"
Write-Host "Profile: isolated provider`nCODEX_HOME: $env:CODEX_HOME`nProject: $PWD"
codex
```

To make the choice reusable without changing the machine-wide environment, add functions like these to your PowerShell profile:

```powershell
function codex-openai {
    $env:CODEX_HOME = "$HOME\.codex"
    Write-Host "Profile: OpenAI`nCODEX_HOME: $env:CODEX_HOME`nProject: $PWD"
    codex @args
}

function codex-isolated {
    $env:CODEX_HOME = "$HOME\.codex-deepseek"
    Write-Host "Profile: isolated provider`nCODEX_HOME: $env:CODEX_HOME`nProject: $PWD"
    codex @args
}
```

The environment assignment above affects only that PowerShell process and its children. It does not rewrite the default profile.

## Configure the isolated provider

1. Create `~/.codex-deepseek` without changing `~/.codex`.
2. Put the isolated profile's user-level `config.toml` in that directory.
3. Follow the current Codex configuration reference for `model_provider` and `model_providers.<id>`.
4. Follow the provider's current API documentation for its endpoint, model name, protocol and compatibility limits.
5. Keep the real API key in the provider's documented environment variable or another supported secret mechanism. Never commit it to this repository, a launcher, a screenshot, or a tutorial.
6. Run a small canary task before trusting the profile with real work: read a disposable file, write and verify another, execute a harmless command, complete several tool-call turns, then test `codex resume`.

Codex's configuration format evolves. Do not blindly paste a provider block from an old guide. As of the 3.1.0 release preparation, Codex documents `responses` as the supported custom-provider wire API; verify the live documentation again when you configure or upgrade Codex.

## Make the HUD see both profiles

1. Install and start Codex Monitor HUD normally. Native CLI monitoring uses the normal profile automatically.
2. In **Settings > Sources**, enable both **Codex CLI · OpenAI** and **Codex CLI · DeepSeek**.
3. Launch the isolated CLI with `CODEX_HOME=$HOME\.codex-deepseek`.
4. Start a real top-level turn. The HUD should show the wave-terminal source mark for that task.

Installing the optional HUD plugin/MCP controls into each `CODEX_HOME` is useful if you want Codex in both profiles to send opt-in HUD notices. It is not required for read-only session monitoring itself.

## Verify and recover

Before each launch, check the three identities printed by your wrapper: profile, `CODEX_HOME`, and working folder. Inside Codex, use the current status/model commands to confirm the selected backend.

To return to native Codex CLI, close the isolated shell or run:

```powershell
$env:CODEX_HOME = "$HOME\.codex"
codex
```

If a Codex or provider update breaks the isolated profile, stop using that profile and keep the normal one unchanged. Do not migrate, merge, or edit Codex session databases to repair it.

## References

- [Codex configuration reference](https://developers.openai.com/codex/config-reference)
- [DeepSeek API quick start](https://api-docs.deepseek.com/zh-cn/)

Codex Monitor HUD is independent and unofficial. The project does not redistribute provider credentials, certify third-party backends, or alter Codex configuration during HUD installation.

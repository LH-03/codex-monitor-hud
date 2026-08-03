# Codex Monitor HUD 2.2.1 — Windows x64

## GitHub Desktop commit summary

```text
Release 2.2.1: refresh GPT-5.6 Terra and Luna cost estimates
```

## Commit description

```text
- Refresh the built-in offline standard API price snapshot from OpenAI's official pricing page.
- Update GPT-5.6 Terra to $2.00 / $0.20 / $12.00 and GPT-5.6 Luna to $0.20 / $0.02 / $1.20 per million input / cached-input / output tokens.
- Keep cost estimates explicitly separate from Codex credits, subscription billing, and non-standard API processing tiers.
- Add a safe second-PC transfer kit, portable project ledger, and next-Codex continuation guide.
- Keep the release Windows x64 only, with transactional installation, rollback, and local-first privacy boundaries unchanged.
```

## GitHub Release fields

Tag: `v2.2.1`  
Title: `Codex Monitor HUD 2.2.1 — Windows x64`

```markdown
## Windows 2.2.1

This maintenance release refreshes the built-in offline API-equivalent cost snapshot and adds a portable project-continuity kit for a second Windows PC.

### Updated cost snapshot

- GPT-5.6 Terra: `$2.00 / $0.20 / $12.00` per million input / cached-input / output tokens.
- GPT-5.6 Luna: `$0.20 / $0.02 / $1.20` per million input / cached-input / output tokens.
- Prices are standard short-context API list prices checked against OpenAI's official pricing page on 2026-08-03.
- The HUD's optional cost figure remains an API-equivalent estimate, not a Codex credit balance, ChatGPT subscription bill, or Fast/Batch/Flex/long-context/regional-processing quote.

### Continuity and safety

- The repository now includes a public project ledger and next-Codex guide.
- `scripts/prepare-transfer-kit.ps1` creates a private physical-transfer ZIP containing public source, the verified Windows release ZIP, checksums, and the guidance needed on another PC.
- Its explicit `-IncludeOwnerPrivate` mode produces an owner-only full snapshot with private handoffs, toolchains, and Git history. Neither transfer mode is a GitHub Release asset.

### Platform and installation

- Supported platform: Windows x64 only.
- Download `CodexMonitorHUD-windows-x64.zip` and `SHA256SUMS.txt`, or give Codex the repository URL and ask it to read `INSTALL_WITH_CODEX.md`.
- Existing settings are preserved. The installer retains the prior version for rollback.

This project is local-first and unofficial. It does not upload Codex sessions, prompts, replies, tool output, logs, databases, settings, or credentials.
```

Before clicking **Publish release**, run `scripts/prepare-release.ps1`, upload the generated ZIP and `SHA256SUMS.txt`, then use the exact SHA-256 line from `RELEASE_UPLOAD.md`.

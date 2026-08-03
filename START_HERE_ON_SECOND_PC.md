# Codex Monitor HUD second-PC handoff

This transfer kit is for a private physical move between the owner's Windows computers. It contains public source, a separately checksummed Windows release ZIP, continuation guidance, and—when marked as an owner snapshot—the owner's private project handoffs, toolchains, records, and Git history. It is not a GitHub Release asset.

## Start here

1. Extract this archive to a normal writable folder.
2. In `source/`, ask Codex to read `README.md`, `docs/PROJECT_STATUS.md`, `docs/PROJECT_LEDGER.md`, and `docs/CODEX_CONTINUATION.md`.
3. To install the prepared version, give Codex the `release/` ZIP and ask it to install from the source checkout using the documented Windows installer. It should preserve existing settings and retain rollback.
4. Before editing, run the synthetic test sequence from `docs/CODEX_CONTINUATION.md`.
5. Do not copy this archive to a public GitHub Release. Publish only the regular `release/CodexMonitorHUD-windows-x64.zip` and its `SHA256SUMS.txt` after the owner chooses to release it.

## Copy-ready prompt

```text
Open the source folder in this transfer kit. Read START_HERE_ON_SECOND_PC.md, README.md, docs/PROJECT_STATUS.md, docs/PROJECT_LEDGER.md, and docs/CODEX_CONTINUATION.md. Treat the source checkout as authoritative, use only synthetic test data, do not inspect or upload my Codex sessions/settings, and install the included Windows release only after verifying its SHA256SUMS.txt.
```
